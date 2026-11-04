import Foundation
import WaiveraAPI

/// A published resource a chat link points at. `provider` is left out when it only repeats the title.
public struct LinkedResource: Sendable, Hashable {
    public var id: String
    public var title: String
    public var provider: String?
    public var city: String?

    public init(id: String, title: String, provider: String?, city: String?) {
        self.id = id
        self.title = title
        self.provider = provider
        self.city = city
    }
}

/// A published FAQ article the reader may open.
public struct LinkedFaq: Sendable, Hashable {
    public var id: String
    public var slug: String
    public var title: String
    public var summary: String?

    public init(id: String, slug: String, title: String, summary: String?) {
        self.id = id
        self.slug = slug
        self.title = title
        self.summary = summary
    }
}

/// What a Waivera link in a chat message points at, read with the reader's own access: a task in
/// another agency, a draft resource or an FAQ the reader can't see fails with `.notFound` or
/// `.forbidden`.
public protocol LinkLookupRepository: Sendable {
    /// The task people call by `number` in the reader's agency.
    func task(number: Int) async throws -> TaskDetail
    func resource(id: String) async throws -> LinkedResource
    /// Every published FAQ article the reader may open.
    func faqs() async throws -> [LinkedFaq]
}

public struct LiveLinkLookupRepository: LinkLookupRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func task(number: Int) async throws -> TaskDetail {
        do {
            return TaskMapping.detail(try await api.lookupTask(friendlyId: number))
        } catch {
            throw WaiveraError.from(error)
        }
    }

    public func resource(id: String) async throws -> LinkedResource {
        let dto: ResourceChatPreviewResponse
        do {
            dto = try await api.resourcePreview(id: id)
        } catch {
            throw WaiveraError.from(error)
        }
        guard let title = dto.title?.trimmed, !title.isEmpty else { throw WaiveraError.notFound }
        let provider = dto.providerName?.trimmed
        return LinkedResource(
            id: id,
            title: title,
            provider: provider.flatMap { $0.isEmpty || $0.caseInsensitiveCompare(title) == .orderedSame ? nil : $0 },
            city: dto.city?.trimmed.nilIfBlank
        )
    }

    public func faqs() async throws -> [LinkedFaq] {
        let categories: [FaqCategoryListResponse]
        do {
            categories = try await api.publishedFaqs()
        } catch {
            throw WaiveraError.from(error)
        }
        return categories.flatMap(\.articles).compactMap { article in
            guard let id = article.id?.lowercased(), let title = article.title?.trimmed, !title.isEmpty else {
                return nil
            }
            return LinkedFaq(
                id: id,
                slug: article.slug ?? "",
                title: title,
                summary: article.summary?.trimmed.nilIfBlank
            )
        }
    }
}

/// No lookups: every link shows as unavailable.
public struct EmptyLinkLookupRepository: LinkLookupRepository {
    public init() {}
    public func task(number: Int) async throws -> TaskDetail { throw WaiveraError.notFound }
    public func resource(id: String) async throws -> LinkedResource { throw WaiveraError.notFound }
    public func faqs() async throws -> [LinkedFaq] { [] }
}
