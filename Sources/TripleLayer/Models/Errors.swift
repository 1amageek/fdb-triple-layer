import Foundation

/// Errors that can occur during TripleLayer operations
public enum TripleError: Error, Sendable {
    /// The provided value is invalid (e.g., exceeds size limits)
    case invalidValue(String)

    /// The requested triple was not found
    case tripleNotFound

    /// Failed to lookup a value in the dictionary
    case dictionaryLookupFailed(value: Value)

    /// Transaction size exceeded FoundationDB's 10MB limit
    case transactionTooLarge

    /// Maximum retry attempts exceeded
    case maxRetriesExceeded

    /// Internal error with a descriptive message
    case internalError(String)
}

// MARK: - LocalizedError

extension TripleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidValue(let description):
            return "Invalid value: \(description)"
        case .tripleNotFound:
            return "Triple not found"
        case .dictionaryLookupFailed(let value):
            return "Failed to lookup value in dictionary: \(value)"
        case .transactionTooLarge:
            return "Transaction size exceeded 10MB limit"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidValue:
            return "Check that the value size is within limits (keys: 10KB, values: 100KB)"
        case .tripleNotFound:
            return "Verify that the triple exists in the store before attempting to delete or query it"
        case .dictionaryLookupFailed:
            return "This is likely an internal consistency error. Check store integrity."
        case .transactionTooLarge:
            return "Reduce the batch size or split the operation into smaller transactions"
        case .maxRetriesExceeded:
            return "Check FoundationDB cluster health and network connectivity"
        case .internalError:
            return "This is an unexpected error. Please report this issue with the error message."
        }
    }
}

// MARK: - CustomStringConvertible

extension TripleError: CustomStringConvertible {
    public var description: String {
        return errorDescription ?? "Unknown error"
    }
}
