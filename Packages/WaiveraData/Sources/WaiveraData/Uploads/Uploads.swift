import Foundation

/// A file the task still needs (sprout_web `TaskAttachmentSection` "Required files"). One whose
/// template is a form is filled on the web; the rest take one uploaded file saved as `name`.
public struct RequiredFile: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var typeId: Int
    /// The form that fills it, when it is filled as a form instead of uploaded.
    public var formName: String?
    /// Someone asked to drop this requirement and the request is waiting.
    public var removalPending: Bool

    public init(id: Int, name: String, typeId: Int, formName: String? = nil, removalPending: Bool = false) {
        self.id = id
        self.name = name
        self.typeId = typeId
        self.formName = formName
        self.removalPending = removalPending
    }

    public var isForm: Bool { formName != nil }
}

/// A file template (sprout_api `TemplateFile`): an activity's file is saved under its name and type.
public struct FileTemplate: Sendable, Hashable {
    public var id: Int
    public var name: String
    public var typeId: Int
    public var categoryId: Int?

    public init(id: Int, name: String, typeId: Int, categoryId: Int?) {
        self.id = id
        self.name = name
        self.typeId = typeId
        self.categoryId = categoryId
    }
}

/// An employee file category; an extra file on an employee task is filed under one.
public struct DocumentCategory: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// What the person picked: a file from Files (a URL, possibly security-scoped), or the bytes of
/// a photo from the library or the camera.
public enum PickedFile: Sendable, Hashable {
    case url(URL)
    case data(Data, name: String?)
}

/// A file picked for Log activity, checked and copied, sent when the activity is logged.
public struct PreparedFile: Sendable, Hashable {
    public var path: String
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int64

    public init(path: String, name: String, mimeType: String, sizeBytes: Int64) {
        self.path = path
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }

    public var kind: FileKind { FileKind(name: name, mimeType: mimeType) }
}

/// Where an upload goes: a requirement it fills, or an extra file (with a category on employee tasks).
public struct UploadTarget: Sendable, Hashable, Codable {
    /// sprout_web sends type 1 for a file that fills no requirement.
    public static let plainTypeId = 1

    public var requirementId: Int?
    /// The requirement's name, which the server saves the file under.
    public var requirementName: String?
    public var typeId: Int
    public var categoryId: Int?

    public init(
        requirementId: Int? = nil,
        requirementName: String? = nil,
        typeId: Int = UploadTarget.plainTypeId,
        categoryId: Int? = nil
    ) {
        self.requirementId = requirementId
        self.requirementName = requirementName
        self.typeId = typeId
        self.categoryId = categoryId
    }
}

/// Why a file was not uploaded, worded by the app; never the server's own text.
public enum UploadProblem: String, Sendable, Hashable, Codable {
    case empty
    case tooLarge
    case unsupported
    case mismatch
    case pdfLocked
    case pdfUnreadable
    /// The requirement already has a file, or a file of that name is on the task.
    case alreadyFilled
    /// The task was finished or is waiting on a signature; the server takes no files.
    case taskLocked
    /// The person can no longer edit this task.
    case noAccess
    /// The picked file could not be read, or its copy was cleared.
    case unreadable
    case failed

    /// Trying again can work: the file itself was fine.
    public var canRetry: Bool { self == .failed }
}

/// A file refused before or by the server, with the app's reason.
public struct UploadRefused: Error, Sendable, Hashable {
    public var problem: UploadProblem
    /// The name the person picked, for the row that says why.
    public var pickedName: String?

    public init(_ problem: UploadProblem, pickedName: String? = nil) {
        self.problem = problem
        self.pickedName = pickedName
    }
}

public enum UploadState: String, Sendable, Hashable, Codable {
    case queued, uploading, failed, done
}

/// One file on its way to a task, as the task's Files list shows it until the server lists it.
public struct TaskUpload: Sendable, Hashable, Identifiable {
    public var id: String
    public var taskId: Int
    public var fileName: String
    public var kind: FileKind
    public var sizeBytes: Int64
    public var requirementId: Int?
    public var state: UploadState
    public var problem: UploadProblem?
    /// The name the server saved it under, once done.
    public var savedName: String?

    public init(
        id: String,
        taskId: Int,
        fileName: String,
        kind: FileKind,
        sizeBytes: Int64,
        requirementId: Int?,
        state: UploadState,
        problem: UploadProblem? = nil,
        savedName: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.fileName = fileName
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.requirementId = requirementId
        self.state = state
        self.problem = problem
        self.savedName = savedName
    }
}
