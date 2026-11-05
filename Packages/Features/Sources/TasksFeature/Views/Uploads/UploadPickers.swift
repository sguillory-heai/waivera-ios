#if canImport(UIKit)
    import PhotosUI
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers
    import WaiveraData
    import WaiveraDesign

    /// Where a picked file comes from. Scanning is left out, as on Android.
    enum UploadSource: Hashable, CaseIterable {
        case camera, photos, files

        static var available: [UploadSource] {
            UIImagePickerController.isSourceTypeAvailable(.camera) ? allCases : [.photos, .files]
        }

        var systemImage: String {
            switch self {
            case .camera: "camera"
            case .photos: "photo.on.rectangle"
            case .files: "folder"
            }
        }

        var tone: TileTone {
            switch self {
            case .camera: .brand
            case .photos: .teal
            case .files: .amber
            }
        }

        func title(single: Bool) -> String {
            switch self {
            case .camera: TasksStrings.text("tasks.upload.camera")
            case .photos: TasksStrings.text(single ? "tasks.upload.photo" : "tasks.upload.photos")
            case .files: TasksStrings.text("tasks.upload.files")
            }
        }

        var detail: String {
            switch self {
            case .camera: TasksStrings.text("tasks.upload.cameraDetail")
            case .photos: TasksStrings.text("tasks.upload.photosDetail")
            case .files: TasksStrings.text("tasks.upload.filesDetail")
            }
        }
    }

    /// Opens the camera, the photo library or Files for `source`, and hands back what was picked.
    /// Backing out hands back nothing and leaves the sheet as it was.
    struct UploadPickers: ViewModifier {
        @Binding var source: UploadSource?
        let single: Bool
        let onPicked: ([PickedFile]) -> Void

        @State private var photoItems: [PhotosPickerItem] = []

        private static let fileTypes: [UTType] = [.pdf, .png, .jpeg, .gif, .heic, .image]

        func body(content: Content) -> some View {
            content
                .photosPicker(
                    isPresented: showing(.photos),
                    selection: $photoItems,
                    maxSelectionCount: single ? 1 : UploadChecks.maxFiles,
                    matching: .images
                )
                .task(id: photoItems) {
                    guard !photoItems.isEmpty else { return }
                    let items = photoItems
                    let files = await Self.load(items)
                    photoItems = []
                    if !files.isEmpty { onPicked(files) }
                }
                .fileImporter(
                    isPresented: showing(.files),
                    allowedContentTypes: Self.fileTypes,
                    allowsMultipleSelection: !single
                ) { result in
                    guard case .success(let urls) = result else { return }
                    onPicked(urls.prefix(single ? 1 : UploadChecks.maxFiles).map(PickedFile.url))
                }
                .fullScreenCover(isPresented: showing(.camera)) {
                    CameraPicker { data in
                        source = nil
                        if let data { onPicked([.data(data, name: "Photo.jpg")]) }
                    }
                    .ignoresSafeArea()
                }
        }

        private func showing(_ wanted: UploadSource) -> Binding<Bool> {
            Binding(get: { source == wanted }, set: { if !$0, source == wanted { source = nil } })
        }

        /// Reads each photo's bytes; HEIC and other formats are turned into JPGs when staged.
        private static func load(_ items: [PhotosPickerItem]) async -> [PickedFile] {
            var files: [PickedFile] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                files.append(.data(data, name: "Photo.\(ext)"))
            }
            return files
        }
    }

    extension View {
        func uploadPickers(
            _ source: Binding<UploadSource?>,
            single: Bool,
            onPicked: @escaping ([PickedFile]) -> Void
        ) -> some View {
            modifier(UploadPickers(source: source, single: single, onPicked: onPicked))
        }
    }

    /// The system camera; hands back a JPG of the photo, or nil when the person cancels.
    struct CameraPicker: UIViewControllerRepresentable {
        static let quality: CGFloat = 0.9

        let onDone: (Data?) -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

        @MainActor
        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let onDone: (Data?) -> Void

            init(onDone: @escaping (Data?) -> Void) { self.onDone = onDone }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                let image = info[.originalImage] as? UIImage
                onDone(image?.jpegData(compressionQuality: CameraPicker.quality))
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
        }
    }
#endif
