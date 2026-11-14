import SwiftUI

struct ManagerHome: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            NavigationStack { TodayView().themedNavBar() }
                .tabItem { Label("Today", systemImage: "sun.max") }
            NavigationStack { InventoryView().themedNavBar() }
                .tabItem { Label("Inventory", systemImage: "shippingbox") }
            NavigationStack { ClosingManagerView().themedNavBar() }
                .tabItem { Label("Closing", systemImage: "camera.viewfinder") }
                .badge(state.submissions.filter { $0.status == .pending }.count)
            NavigationStack { NotesView().themedNavBar() }
                .tabItem { Label("Notes", systemImage: "note.text") }
            NavigationStack { SettingsView().themedNavBar() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section("Signed in") {
                LabeledContent("Name", value: state.userName)
                LabeledContent("Role", value: state.role == .manager ? "Manager" : "Crew")
            }
            Section("Sync") {
                LabeledContent("Mode", value: Config.useCloudKit ? "iCloud (shared)" : "This device only")
                Button("Refresh now") { Task { await state.refreshAll() } }
            }
            AppearanceSection()
            Section { Button("Switch user", role: .destructive) { state.signOut() } }
        }
        .navigationTitle("More")
    }
}
