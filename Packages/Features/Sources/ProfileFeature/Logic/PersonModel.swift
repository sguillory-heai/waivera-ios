import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Another person's profile with a Message action that reuses or creates the direct
/// conversation (06 §C2). The directory name shows at once; details load after.
@MainActor
@Observable
public final class PersonModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case failed(WaiveraError)
        case loaded(PersonProfile)
    }

    public let userID: String
    public private(set) var phase = Phase.loading
    /// From the directory cache until the details arrive.
    public private(set) var directoryName: String?
    public private(set) var celebration: Celebration?
    public private(set) var isOpeningChat = false
    /// "Message" failed; the person stays on the profile and sees why.
    public private(set) var messageError: WaiveraError?
    public private(set) var me: CurrentUser?

    @ObservationIgnored private let people: any PeopleRepository
    @ObservationIgnored private let conversations: any ConversationsRepository
    @ObservationIgnored private let session: any SessionRepository
    @ObservationIgnored private let calendar: any CalendarRepository
    @ObservationIgnored private let realtime: any RealtimeStatusRepository
    @ObservationIgnored private var milestones = MilestoneIndex.empty
    @ObservationIgnored private var loadInFlight = false

    public init(
        userID: String,
        people: any PeopleRepository,
        conversations: any ConversationsRepository,
        session: any SessionRepository,
        calendar: any CalendarRepository,
        realtime: any RealtimeStatusRepository
    ) {
        self.userID = userID
        self.people = people
        self.conversations = conversations
        self.session = session
        self.calendar = calendar
        self.realtime = realtime
        me = session.currentState.user
    }

    public convenience init(userID: String, environment: DataEnvironment) {
        self.init(
            userID: userID,
            people: environment.people,
            conversations: environment.conversations,
            session: environment.session,
            calendar: environment.calendar,
            realtime: environment.realtimeStatus
        )
    }

    public var person: PersonProfile? {
        if case .loaded(let person) = phase { return person }
        return nil
    }

    public var displayName: String? { ProfileText.displayName(person: person, fallback: directoryName) }

    /// No chat with yourself, and none before the session is known.
    public var canMessage: Bool {
        guard let me else { return false }
        return me.id != userID && me.firebaseUid != userID
    }

    public func run() async {
        async let directory: Void = observeDirectory()
        async let sessions: Void = observeSession()
        async let milestones: Void = observeMilestones()
        async let reconnects: Void = onReconnect(realtime) {
            if self.person == nil { await self.load() }
        }
        await load()
        _ = await (directory, sessions, milestones, reconnects)
    }

    private func observeDirectory() async {
        for await value in people.directory() { apply(directory: value.value ?? []) }
    }

    private func observeSession() async {
        for await state in session.states() { me = state.user }
    }

    private func observeMilestones() async {
        for await index in calendar.milestones() { apply(milestones: index.value ?? .empty) }
    }

    /// Loads, or after an error retries, the details. A loaded profile stays on a later failure.
    public func load() async {
        guard !loadInFlight else { return }
        loadInFlight = true
        if person == nil { phase = .loading }
        do {
            let loaded = try await people.person(id: userID)
            phase = .loaded(loaded)
        } catch {
            if person == nil { phase = .failed(WaiveraError.from(error)) }
        }
        loadInFlight = false
    }

    /// Opens the direct conversation, creating it when it does not exist yet. Returns its id,
    /// or `nil` on failure (then `messageError` is set). Double taps are ignored.
    public func message() async -> Int? {
        guard canMessage, !isOpeningChat else { return nil }
        isOpeningChat = true
        messageError = nil
        defer { isOpeningChat = false }
        do {
            return try await conversations.openDirectConversation(with: userID).id
        } catch {
            messageError = WaiveraError.from(error)
            return nil
        }
    }

    public func dismissMessageError() {
        messageError = nil
    }

    private func apply(directory: [DirectoryPerson]) {
        directoryName = directory.first { $0.id == userID }?.name.nonBlank
    }

    private func apply(milestones index: MilestoneIndex) {
        milestones = index
        celebration = index.celebration(for: userID, on: calendar.today())
    }
}
