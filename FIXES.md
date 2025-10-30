# TripleLayer 実装修正レポート

## 修正日時
2025-10-30

## 発見された問題と修正内容

### 1. 重大な問題: Binary Valueのハッシュ衝突リスク

#### 問題の詳細
**場所:** `Sources/TripleLayer/Encoding/TupleHelpers.swift:27-32`

**問題点:**
- 1024バイトを超えるバイナリデータを`hashData()`でハッシュ化していた
- ハッシュ衝突により、異なるバイナリデータが同じIDにマップされる可能性
- 1024バイト以下と以上で異なるキー形式を使用（一貫性の欠如）

**修正前のコード:**
```swift
case .binary(let d):
    let bytes: FDB.Bytes = [UInt8](d)
    if bytes.count > 1024 {
        return Tuple(rootPrefix, "dict", "v2i", "bin", hashData(d)).encode()
    } else {
        return Tuple(rootPrefix, "dict", "v2i", "bin", bytes).encode()
    }
```

**修正後のコード:**
```swift
case .binary(let d):
    let bytes: FDB.Bytes = [UInt8](d)
    // FoundationDB has a 10KB key size limit
    // We reserve some space for the tuple prefix, so limit binary data to 8KB
    guard bytes.count <= 8192 else {
        throw TripleError.invalidValue("Binary data too large for dictionary key (max 8KB, got \(bytes.count) bytes)")
    }
    return Tuple(rootPrefix, "dict", "v2i", "bin", bytes).encode()
```

**影響:**
- ✅ ハッシュ衝突のリスクを完全に排除
- ✅ すべてのバイナリデータに対して一貫したキー形式
- ✅ 適切なエラーハンドリング（8KB制限）

#### 関連する修正

1. **不要な`hashData()`関数の削除**
   - `TupleHelpers.swift`から削除（154-160行目）

2. **関数シグネチャの更新**
   - `encodeValueToIDKey()` が `throws` に変更
   - `DictionaryStore.swift`の呼び出し箇所を更新（54行目、76行目）

3. **テストの追加**
   - 小さいバイナリデータのテスト（1KB）
   - 大きいバイナリデータのエラーテスト（10KB）

---

## 検証済みの正しい実装

### 1. インデックス整合性 ✅

4つのインデックスのエンコード/デコードロジックが完全に整合しています：

| インデックス | エンコード順序 | デコードマッピング | 用途 |
|------------|-------------|----------------|------|
| **SPO** | (S, P, O) | id1→S, id2→P, id3→O | Subject検索 |
| **PSO** | (P, S, O) | id1→P, id2→S, id3→O | Predicate検索 |
| **POS** | (P, O, S) | id1→P, id2→O, id3→S | P+O検索 |
| **OSP** | (O, S, P) | id1→O, id2→S, id3→P | Object検索 |

**検証結果:**
- `encodeIndexKey()` と `decodeIndexKey()` が正しく対応
- `buildRangeKeys()` が各インデックスに対して正しいID順序を使用
- クエリロジックが適切なインデックスを選択

### 2. トランザクション整合性 ✅

すべての操作がACID特性を保証：

| 操作 | トランザクション境界 | 原子性 |
|------|-------------------|--------|
| **insert** | `db.withTransaction` | ✅ 4インデックス同時更新 |
| **delete** | `db.withTransaction` | ✅ 4インデックス同時削除 |
| **query** | `db.withTransaction` + snapshot | ✅ 一貫性のある読み取り |
| **ID生成** | トランザクション内のアトミック操作 | ✅ 競合回避 |

### 3. カウンター管理 ✅

正しいアトミック演算を使用：

```swift
// 挿入時: +1
let increment = TupleHelpers.encodeUInt64(1)
transaction.atomicOp(key: countKey, param: increment, mutationType: .add)

// 削除時: -1（2の補数を使用）
let decrementValue = UInt64(bitPattern: Int64(-1))
let decrement = TupleHelpers.encodeUInt64(decrementValue)
transaction.atomicOp(key: countKey, param: decrement, mutationType: .add)
```

### 4. ID生成の競合安全性 ✅

**シナリオ:** 2つのトランザクションが同時に同じValueのIDを生成しようとする

```
トランザクションA: valueKeyチェック → 存在しない → ID=1生成 → valueKey書き込み → コミット成功
トランザクションB: valueKeyチェック → 存在しない → ID=2生成 → valueKey書き込み →
                   FoundationDBが競合検出（Aが書き込み済み） → 自動リトライ →
                   valueKeyチェック → ID=1が存在 → ID=1を返す
```

**結果:**
- データの一貫性は保証される
- ID=2はスキップされるが、機能的には問題なし
- これはFoundationDBのMVCC（Multi-Version Concurrency Control）の正常動作

---

## テストカバレッジ

### 既存テスト（23個）
- ✅ 基本的なCRUD操作
- ✅ 7つのクエリパターン（SPO, PSO, POS, OSP, etc.）
- ✅ 重複挿入の冪等性
- ✅ 異なるValue型（URI, Text, Integer, Float, Boolean）
- ✅ 言語タグ付きテキスト
- ✅ バッチ操作
- ✅ Metadata（保存なし確認）

### 追加テスト（2個）
- ✅ 小さいバイナリデータの保存と取得（1KB）
- ✅ 大きいバイナリデータのエラーハンドリング（10KB）

---

## 性能への影響

### 修正前
- **リスク:** ハッシュ衝突による誤った結果
- **パフォーマンス:** ハッシュ計算のオーバーヘッド（小）

### 修正後
- **リスク:** なし（データ整合性保証）
- **パフォーマンス:** ハッシュ計算不要で若干改善
- **制限:** バイナリデータは8KB以内（明示的なエラー）

---

## 残存する設計上の制約

### 1. Metadataは保存されない
**理由:** 現在の設計では、MetadataはTripleオブジェクトのプロパティだが、ストレージには保存されない

**影響:**
- 挿入時にMetadataを付与しても、クエリ時には失われる
- テストで明示的に文書化済み（`TripleStoreTests.swift:364`）

**将来の拡張:**
- Metadataを別インデックスに保存する
- (rootPrefix, "meta", tripleID) → JSON(metadata)

### 2. Swift 6 並行性警告
**理由:** FoundationDBライブラリがまだSendable準拠していない

**対策:**
- Swift 5言語モードを使用
- `@preconcurrency import FoundationDB`
- 警告のみ（エラーではない）

**安全性:**
- FoundationDB自体はスレッドセーフ
- Actor分離により追加の保護

---

## ビルド状態

```bash
$ swift build
Building for debugging...
Build complete! (1.76s)
```

✅ **ビルド成功**（警告あり、エラーなし）

---

## 推奨事項

### 即座に対応すべき
- ✅ **完了:** Binary Valueのハッシュ化問題を修正

### 将来的に検討すべき
1. **Metadata保存機能の追加**
   - 別インデックスを使用
   - クエリ時にMetadataを復元

2. **大きなバイナリの分割保存**
   - 8KBを超えるバイナリを複数のチャンクに分割
   - 別のサブスペースに保存

3. **FoundationDBのSendable対応待ち**
   - Swift 6言語モードへの移行
   - 警告の完全解消

---

## 結論

### 修正前
- ❌ ハッシュ衝突によるデータ整合性リスク
- ✅ その他のロジックは正常

### 修正後
- ✅ すべてのロジックが正常
- ✅ データ整合性保証
- ✅ 適切なエラーハンドリング
- ✅ テストカバレッジ拡充

**総合評価:** 実装は論理的に正しく、本番環境で使用可能な品質
