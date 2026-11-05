import Foundation
import WaiveraAPI

enum UploadMapping {
    static func required(_ dto: RequiredAttachmentResponse) -> RequiredFile? {
        guard let id = dto.id, let template = dto.templateFile, let name = TaskMapping.trimmed(template.fileName)
        else { return nil }
        let formName = template.form.map { TaskMapping.trimmed($0.name) ?? name }
        return RequiredFile(
            id: id,
            name: name,
            typeId: template.type?.id ?? UploadTarget.plainTypeId,
            formName: formName,
            removalPending: dto.removalRequestPending ?? false
        )
    }

    static func template(_ dto: TemplateFileResponse) -> FileTemplate? {
        guard let id = dto.id, let name = TaskMapping.trimmed(dto.fileName) else { return nil }
        return FileTemplate(
            id: id,
            name: name,
            typeId: dto.type?.id ?? UploadTarget.plainTypeId,
            categoryId: dto.employeeDocumentCategoryId
        )
    }

    static func category(_ dto: DocumentCategoryResponse) -> DocumentCategory? {
        guard let id = dto.id, let name = TaskMapping.trimmed(dto.documentCategoryName) else { return nil }
        return DocumentCategory(id: id, name: name)
    }

    /// sprout_api `TaskFileUploadErrorCodes`, and the 409s for a locked task or a filled requirement.
    static func problem(_ error: any Error) -> UploadProblem {
        let code = (error as? CodedRefusal)?.code
        switch code {
        case "PDF_ENCRYPTED", "PDF_PASSWORD_REQUIRED": return .pdfLocked
        case "PDF_UNREADABLE", "PDF_NO_PAGES": return .pdfUnreadable
        case "FILE_EMPTY": return .empty
        case "FILE_TOO_LARGE": return .tooLarge
        case "FILE_TYPE_UNSUPPORTED": return .unsupported
        case "FILE_EXTENSION_MISMATCH": return .mismatch
        case "FILE_ALREADY_UPLOADED": return .alreadyFilled
        default: break
        }
        switch WaiveraError.from(error) {
        case .conflict: return .taskLocked
        case .notFound, .forbidden: return .noAccess
        case .server(statusCode: 413): return .tooLarge
        default: return .failed
        }
    }
}
