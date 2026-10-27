import Foundation
import WaiveraAPI

public enum ResourcePhase: Sendable, Equatable {
    /// Nothing requested yet.
    case idle
    /// A request is in flight. With a cached `value`, this is a background refresh.
    case loading
    case loaded
    /// The last request failed; `value` keeps whatever was shown before.
    case failed(WaiveraError)
}

/// What a repository stream emits: the latest value (possibly from the offline cache) plus
/// where the next refresh stands. Screens map this to skeleton, empty, content and error.
public struct Resource<Value: Sendable>: Sendable {
    public typealias Phase = ResourcePhase

    public var value: Value?
    public var phase: Phase
    /// When `value` last came from the server; `nil` for cache-only or no value.
    public var updatedAt: Date?

    public init(value: Value? = nil, phase: Phase = .idle, updatedAt: Date? = nil) {
        self.value = value
        self.phase = phase
        self.updatedAt = updatedAt
    }

    public static var idle: Resource { Resource() }

    /// First load with nothing to show: render a skeleton.
    public var isLoadingWithoutValue: Bool { value == nil && (phase == .loading || phase == .idle) }
    public var isRefreshing: Bool { value != nil && phase == .loading }

    public var error: WaiveraError? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    public func map<Other: Sendable>(_ transform: (Value) -> Other) -> Resource<Other> {
        Resource<Other>(value: value.map(transform), phase: phase, updatedAt: updatedAt)
    }
}

extension Resource: Equatable where Value: Equatable {}

extension Resource where Value: Collection {
    /// Loaded and nothing there: render the empty state.
    public var isEmpty: Bool { phase == .loaded && (value?.isEmpty ?? true) }
}
