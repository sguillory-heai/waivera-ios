import Foundation

/// `dto/Response/Wiki/FaqResponse.cs` `FaqCategoryListResponse`, from `GET api/help/faqs`.
public struct FaqCategoryListResponse: Decodable, Sendable, Hashable {
    public var id: String?
    public var name: String?
    public var articles: [FaqListArticleResponse]

    public init(id: String? = nil, name: String? = nil, articles: [FaqListArticleResponse]) {
        self.id = id
        self.name = name
        self.articles = articles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(LenientID.self, forKey: .id)?.value
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        articles =
            (try? container.decodeIfPresent(LossyArray<FaqListArticleResponse>.self, forKey: .articles))??
            .elements ?? []
    }

    enum CodingKeys: String, CodingKey { case id, name, articles }
}

/// `dto/Response/Wiki/FaqResponse.cs` `FaqListArticleResponse`.
public struct FaqListArticleResponse: Codable, Sendable, Hashable {
    public var id: String?
    public var title: String?
    public var slug: String?
    public var summary: String?

    public init(id: String?, title: String?, slug: String? = nil, summary: String? = nil) {
        self.id = id
        self.title = title
        self.slug = slug
        self.summary = summary
    }
}

/// The object `ResourceChatController.Preview` returns (`GET api/resource-directory/chat/{id}`):
/// only published resources the caller may see.
public struct ResourceChatPreviewResponse: Codable, Sendable, Hashable {
    public var id: String?
    public var title: String?
    public var providerName: String?
    public var city: String?

    public init(id: String? = nil, title: String?, providerName: String? = nil, city: String? = nil) {
        self.id = id
        self.title = title
        self.providerName = providerName
        self.city = city
    }
}
