import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Light / Dark / follow the phone. Stored in UserDefaults under "appearance".
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

/// Color palette. Stored in UserDefaults under "palette".
enum Palette: String, CaseIterable, Identifiable {
    case adobo, classic
    var id: String { rawValue }
    var name: String { self == .adobo ? "Adobo (warm red)" : "Classic blue" }
}

enum Theme {
    static var palette: Palette { Palette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .adobo }
    static var accent: Color { palette == .adobo ? Color(hex: 0xA81612) : Color(hex: 0x295BD9) }
    /// Brand gradient used for the nav bar, primary buttons and progress bars.
    static var gradient: LinearGradient {
        let colors = palette == .adobo ? [Color(hex: 0xB5261E), Color(hex: 0x451400)]
                                       : [Color(hex: 0x3B6FF0), Color(hex: 0x1E3A8A)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let alert = Color(red: 0.86, green: 0.23, blue: 0.20)
    static let ok = Color(red: 0.13, green: 0.60, blue: 0.33)
    static let warn = Color(red: 0.93, green: 0.55, blue: 0.10)
}

extension View {
    /// Gradient navigation bar with white title and buttons.
    func themedNavBar() -> some View {
        toolbarBackground(Theme.gradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Theme picker shown in More (managers) and the profile menu (crew).
struct AppearanceSection: View {
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("palette") private var palette = Palette.adobo.rawValue

    var body: some View {
        Section {
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Picker("Colors", selection: $palette) {
                ForEach(Palette.allCases) { Text($0.name).tag($0.rawValue) }
            }
            RoundedRectangle(cornerRadius: 10).fill(Theme.gradient).frame(height: 44)
                .overlay(Text("Preview").font(.headline).foregroundStyle(.white))
                .id(palette)
        } header: { Text("Appearance") } footer: {
            Text("“System” follows your iPhone's Light/Dark setting.")
        }
    }
}

struct AppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form { AppearanceSection() }
                .navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
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
            ProgressView(value: Double(done), total: Double(max(total, 1))).tint(Theme.accent)
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
