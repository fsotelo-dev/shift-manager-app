import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.16, green: 0.36, blue: 0.85)
    static let alert = Color(red: 0.86, green: 0.23, blue: 0.20)
    static let ok = Color(red: 0.13, green: 0.60, blue: 0.33)
    static let warn = Color(red: 0.93, green: 0.55, blue: 0.10)
}

/// Red banner shown at the top of every main screen while a time block (e.g. line lock) is active.
struct TimeBlockBanner: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            if let b = state.activeBlock(at: ctx.date) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title.uppercased()).font(.subheadline.weight(.bold))
                        Text([b.rangeLabel, b.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(Theme.alert, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
    }
}

struct StatusChip: View {
    let status: ReviewStatus?
    var body: some View {
        let (text, color): (String, Color) = switch status {
        case nil: ("To do", .gray)
        case .pending?: ("Waiting", Theme.warn)
        case .approved?: ("Approved", Theme.ok)
        case .redo?: ("Redo", Theme.alert)
        }
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Inline "type and press +" row used for checklists and notes.
struct AddRow: View {
    let placeholder: String
    let onAdd: (String) async -> Void
    @State private var text = ""

    var body: some View {
        HStack {
            TextField(placeholder, text: $text).onSubmit(add)
            Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                .buttonStyle(.borderless)
                .disabled(trimmed.isEmpty)
        }
    }
    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }
    private func add() {
        let t = trimmed
        guard !t.isEmpty else { return }
        text = ""
        Task { await onAdd(t) }
    }
}

struct ProgressHeader: View {
    let done: Int
    let total: Int
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(done)/\(total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Theme.ok)
        }
        .padding(.vertical, 4)
    }
}

/// Loads a closing photo from the store (cached).
struct SubmissionPhoto: View {
    @EnvironmentObject var state: AppState
    let submission: ClosingSubmission
    @State private var image: UIImage?
    @State private var fullScreen = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { fullScreen = true }
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1))
                    .frame(height: 220).overlay(ProgressView())
            }
        }
        .task(id: submission.submittedAt) {
            image = nil
            if let d = await state.photo(for: submission) { image = UIImage(data: d) }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                Button { fullScreen = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white)
                }.padding()
            }
        }
    }
}

/// Camera only on a real device (no camera roll) so photos are taken on the spot.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        #if targetEnvironment(simulator)
        p.sourceType = .photoLibrary
        #else
        p.sourceType = .camera
        #endif
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension UIImage {
    /// Shrinks to ~1600px and JPEG-compresses so uploads stay small.
    func jpegForUpload(maxDimension: CGFloat = 1600, quality: CGFloat = 0.6) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}
