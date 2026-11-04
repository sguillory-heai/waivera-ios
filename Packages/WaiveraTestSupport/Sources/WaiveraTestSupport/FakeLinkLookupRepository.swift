import Foundation
import WaiveraAPI
import WaiveraData

/// Chat link lookups over the demo tasks, one resource and two FAQ articles. Records every call.
public final class FakeLinkLookupRepository: LinkLookupRepository {
    public static let resourceId = "5b0f6c2e-3d4a-4f1b-9c8e-2a7d6e1f0b3c"
    public static let faqId = "0c9e8d7f-6b5a-4c3d-8e2f-1a0b9c8d7e6f"

    private let tasks: FakeTasksRepository
    public let calls = CallLog()
    public let failure = LockedValue<WaiveraError?>(nil)

    public init(tasks: FakeTasksRepository) { self.tasks = tasks }

    public func task(number: Int) async throws -> TaskDetail {
        calls.record("task:\(number)")
        if let error = failure.get() { throw error }
        return try await tasks.lookup(number: number)
    }

    public func resource(id: String) async throws -> LinkedResource {
        calls.record("resource:\(id)")
        if let error = failure.get() { throw error }
        guard id == Self.resourceId else { throw WaiveraError.notFound }
        return LinkedResource(id: id, title: "North County Respite", provider: "Family Care Network", city: "Austin")
    }

    public func faqs() async throws -> [LinkedFaq] {
        calls.record("faqs")
        if let error = failure.get() { throw error }
        return [
            LinkedFaq(
                id: Self.faqId,
                slug: "time-off",
                title: "How do I ask for time off?",
                summary: "Requests go to your supervisor and show on your schedule once approved."
            ),
            LinkedFaq(
                id: "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d",
                slug: "mileage",
                title: "Logging mileage",
                summary: nil
            ),
        ]
    }
}
