import Foundation

public enum MediaSFUBridgeError: LocalizedError, Equatable {
    case connectFailed(String)
    case produceFailed(String)
    case consumeFailed(String)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case let .connectFailed(message):
            return "Connect failed: \(message)"
        case let .produceFailed(message):
            return "Produce failed: \(message)"
        case let .consumeFailed(message):
            return "Consume failed: \(message)"
        case let .invalidState(message):
            return "Invalid state: \(message)"
        }
    }
}