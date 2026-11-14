import SwiftUI
import UserNotifications

enum Config {
    /// Leave false to try the app on one device. Set true after creating the CloudKit container (see README).
    static let useCloudKit = false
    static let cloudKitContainer = "iCloud.com.yourcompany.workapp"
    /// Simple gate so crew can't open manager mode. Change before using in the store.
    static let managerPIN = "1234"
    /// Hour (24h) the store closes. Tasks added after this are marked "Added tonight".
    static let closingHour = 22
}

@main
struct WorkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState(
        store: Config.useCloudKit ? CloudKitStore(containerID: Config.cloudKitContainer) as DataStore : LocalStore())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if Config.useCloudKit { application.registerForRemoteNotifications() }
        return true
    }
    // Show banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("palette") private var palette = Palette.adobo.rawValue

    var body: some View {
        Group {
            switch state.role {
            case nil: OnboardingView()
            case .manager?: ManagerHome()
            case .crew?: CrewHome()
            }
        }
        .id(palette) // rebuild screens with the new colors
        .tint(Theme.accent)
        .preferredColorScheme(Appearance(rawValue: appearance)?.scheme) // nil = follow the phone
        .task(id: state.role) {
            guard state.role != nil else { return }
            await Notifier.requestAuth()
            await state.refreshAll()
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { state.lastError != nil }, set: { if !$0 { state.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(state.lastError ?? "") }
    }
}
