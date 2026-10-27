import SignalRClient
import WaiveraAPI

/// The client's methods take variadic `Any...`, which an array cannot be splatted into; these
/// spell out every arity the chat hub uses (`SendMessage` has six arguments).
extension HubConnection {
    static let maxArguments = 6

    func sendSpreading(_ method: String, _ args: [JSONValue]) async throws {
        switch args.count {
        case 0: try await send(method: method)
        case 1: try await send(method: method, arguments: args[0])
        case 2: try await send(method: method, arguments: args[0], args[1])
        case 3: try await send(method: method, arguments: args[0], args[1], args[2])
        case 4: try await send(method: method, arguments: args[0], args[1], args[2], args[3])
        case 5: try await send(method: method, arguments: args[0], args[1], args[2], args[3], args[4])
        case 6: try await send(method: method, arguments: args[0], args[1], args[2], args[3], args[4], args[5])
        default: throw SignalRError.invalidOperation("Too many arguments")
        }
    }

    func invokeVoidSpreading(_ method: String, _ args: [JSONValue]) async throws {
        switch args.count {
        case 0: try await invoke(method: method) as Void
        case 1: try await invoke(method: method, arguments: args[0]) as Void
        case 2: try await invoke(method: method, arguments: args[0], args[1]) as Void
        case 3: try await invoke(method: method, arguments: args[0], args[1], args[2]) as Void
        case 4: try await invoke(method: method, arguments: args[0], args[1], args[2], args[3]) as Void
        case 5: try await invoke(method: method, arguments: args[0], args[1], args[2], args[3], args[4]) as Void
        case 6:
            try await invoke(method: method, arguments: args[0], args[1], args[2], args[3], args[4], args[5]) as Void
        default: throw SignalRError.invalidOperation("Too many arguments")
        }
    }

    func invokeSpreading(_ method: String, _ args: [JSONValue]) async throws -> JSONValue {
        let result: AnyHashable
        switch args.count {
        case 0: result = try await invoke(method: method)
        case 1: result = try await invoke(method: method, arguments: args[0])
        case 2: result = try await invoke(method: method, arguments: args[0], args[1])
        case 3: result = try await invoke(method: method, arguments: args[0], args[1], args[2])
        case 4: result = try await invoke(method: method, arguments: args[0], args[1], args[2], args[3])
        case 5: result = try await invoke(method: method, arguments: args[0], args[1], args[2], args[3], args[4])
        case 6:
            result = try await invoke(method: method, arguments: args[0], args[1], args[2], args[3], args[4], args[5])
        default: throw SignalRError.invalidOperation("Too many arguments")
        }
        return JSONValue(hubArgument: result)
    }

    /// Binds `target` with `arity` positional arguments, each as `AnyHashable`.
    func registerHashable(
        _ target: String,
        arity: Int,
        handler: @escaping @Sendable ([JSONValue]) -> Void
    ) {
        typealias Arg = AnyHashable
        let wrap: @Sendable ([Arg]) -> Void = { handler($0.map(JSONValue.init(hubArgument:))) }
        switch arity {
        case 0: on(target) { () async in wrap([]) }
        case 1: on(target) { (first: Arg) async in wrap([first]) }
        case 2: on(target) { (first: Arg, second: Arg) async in wrap([first, second]) }
        case 3: on(target) { (first: Arg, second: Arg, third: Arg) async in wrap([first, second, third]) }
        case 4:
            on(target) { (first: Arg, second: Arg, third: Arg, fourth: Arg) async in
                wrap([first, second, third, fourth])
            }
        default:
            on(target) { (first: Arg, second: Arg, third: Arg, fourth: Arg, fifth: Arg) async in
                wrap([first, second, third, fourth, fifth])
            }
        }
    }
}
