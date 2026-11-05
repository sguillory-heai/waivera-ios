import Foundation

/// `TaskRequiresAttachmentResponse` from `GET api/tasks/requiredAttachments/{taskId}`: the files
/// still missing on a task. A requirement whose template has a `form` is filled as a form.
public struct RequiredAttachmentResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var templateFile: TemplateFileResponse?
    public var removalRequestPending: Bool?

    public init(id: Int?, templateFile: TemplateFileResponse? = nil, removalRequestPending: Bool? = nil) {
        self.id = id
        self.templateFile = templateFile
        self.removalRequestPending = removalRequestPending
    }
}

/// `Models/TemplateFile.cs`, the fields read here. An activity type that needs a file names one by id.
public struct TemplateFileResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var fileName: String?
    public var type: FileTypeResponse?
    public var form: FormRefResponse?
    /// The employee file category an upload for this template is filed under.
    public var employeeDocumentCategoryId: Int?

    public init(
        id: Int?,
        fileName: String? = nil,
        type: FileTypeResponse? = nil,
        form: FormRefResponse? = nil,
        employeeDocumentCategoryId: Int? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.type = type
        self.form = form
        self.employeeDocumentCategoryId = employeeDocumentCategoryId
    }
}

public struct FileTypeResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var type: String?

    public init(id: Int?, type: String? = nil) {
        self.id = id
        self.type = type
    }
}

public struct FormRefResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var name: String?

    public init(id: Int?, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

/// `POST api/file/upload`: the saved file and the name it was saved under ("Fax (2).pdf").
public struct TaskUploadResponse: Decodable, Sendable, Hashable {
    public var fileId: String?
    public var fileName: String?

    public init(fileId: String? = nil, fileName: String? = nil) {
        self.fileId = fileId
        self.fileName = fileName
    }

    enum CodingKeys: String, CodingKey { case fileId, fileName }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileId = container.lenient(LenientID.self, forKey: .fileId)?.value
        fileName = container.lenient(String.self, forKey: .fileName)
    }
}

/// `dto/Response/DocumentCategoryDto.cs`: an employee file category.
public struct DocumentCategoryResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var documentCategoryName: String?

    public init(id: Int?, documentCategoryName: String? = nil) {
        self.id = id
        self.documentCategoryName = documentCategoryName
    }
}

/// sprout_web `uploadFile`'s form for `POST api/file/upload`. OrganizationId, RegionId and
/// participantId are the web's fixed placeholders: the server reads the task's own
/// organization, but model binding still needs RegionId present.
public struct TaskUploadForm: Sendable, Equatable {
    static let placeholderOrganization = "1"
    static let placeholderRegion = "2"
    static let placeholderParticipant = "2"

    public var data: Data
    /// The file part's name: the picked file's name with its real extension.
    public var fileName: String
    /// What the server saves it as: the requirement's or template's name, else `fileName`.
    public var savedName: String
    public var taskId: Int
    public var typeId: Int
    public var requirementId: Int?
    public var categoryId: Int?
    public var mimeType: String

    public init(
        data: Data,
        fileName: String,
        savedName: String,
        taskId: Int,
        typeId: Int,
        requirementId: Int?,
        categoryId: Int?,
        mimeType: String
    ) {
        self.data = data
        self.fileName = fileName
        self.savedName = savedName
        self.taskId = taskId
        self.typeId = typeId
        self.requirementId = requirementId
        self.categoryId = categoryId
        self.mimeType = mimeType
    }

    var fields: [(String, String)] {
        var fields: [(String, String)] = [
            ("file.FileName", savedName),
            ("file.DurationInMinutes", "0"),
        ]
        if let requirementId { fields.append(("file.RequiredAttachmentId", String(requirementId))) }
        fields += [
            ("file.OrganizationId", Self.placeholderOrganization),
            ("file.RegionId", Self.placeholderRegion),
            ("file.participantId", Self.placeholderParticipant),
            ("file.TypeId", String(typeId)),
        ]
        if let categoryId { fields.append(("file.DocumentCategoryId", String(categoryId))) }
        fields += [
            ("file.TaskId", String(taskId)),
            ("file.MimeType", mimeType),
            ("file.Size", String(data.count)),
        ]
        return fields
    }

    func multipartBody(boundary: String) -> Data {
        Self.multipart(boundary: boundary, fileName: fileName, mimeType: mimeType, data: data, fields: fields)
    }

    /// The file under `file.File`, then each field, as sprout_web's `FormData` sends them.
    static func multipart(
        boundary: String,
        fileName: String,
        mimeType: String,
        data: Data,
        fields: [(String, String)]
    ) -> Data {
        var body = Data()
        func line(_ text: String) { body.append(Data((text + "\r\n").utf8)) }
        let safeName = headerSafe(fileName)
        line("--\(boundary)")
        line("Content-Disposition: form-data; name=\"file.File\"; filename=\"\(safeName)\"")
        line("Content-Type: \(mimeType)")
        line("")
        body.append(data)
        line("")
        for (name, value) in fields {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(name)\"")
            line("")
            line(headerSafe(value))
        }
        line("--\(boundary)--")
        return body
    }

    /// Quotes and line breaks would end the header or the field early.
    static func headerSafe(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

/// sprout_web `uploadComplianceEvidence` for `POST api/file/upload-compliance-evidence`: the
/// server takes everything else from the task.
public struct EvidenceUploadForm: Sendable, Equatable {
    public var data: Data
    public var fileName: String
    public var taskId: Int
    public var mimeType: String

    public init(data: Data, fileName: String, taskId: Int, mimeType: String) {
        self.data = data
        self.fileName = fileName
        self.taskId = taskId
        self.mimeType = mimeType
    }

    var fields: [(String, String)] {
        [("file.TaskId", String(taskId)), ("file.MimeType", mimeType), ("file.Size", String(data.count))]
    }

    func multipartBody(boundary: String) -> Data {
        TaskUploadForm.multipart(boundary: boundary, fileName: fileName, mimeType: mimeType, data: data, fields: fields)
    }
}
