import Foundation
import WaiveraAPI

/// The SignalR client only binds argument types that conform to `Decodable`, and it passes
/// scalars and `null` through as raw Foundation values that a typed cast rejects. `AnyHashable`
/// accepts both: objects decode here into `JSONValue`, scalars and `NSNull` cast directly.
/// This conformance is retroactive and process-wide; nothing else in the app decodes
/// `AnyHashable`, and the decoded value is always a `JSONValue`.
extension AnyHashable: @retroactive Decodable {
    public init(from decoder: any Decoder) throws {
        self.init(try JSONValue(from: decoder))
    }
}

extension JSONValue {
    /// A bound hub argument: a decoded `JSONValue`, or a raw scalar or `NSNull`.
    init(hubArgument: AnyHashable) {
        if let json = hubArgument.base as? JSONValue {
            self = json
        } else {
            self.init(any: hubArgument.base)
        }
    }
}
