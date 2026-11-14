import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var role: Role = .crew
    @State private var pin = ""
    @State private var wrongPIN = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checklist").font(.system(size: 44)).foregroundStyle(Theme.accent)
                        Text("Shift Manager").font(.title2.bold())
                        Text("Inventory, reminders and closing checks in one place.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)

                Section("Your name") { TextField("First name", text: $name).textContentType(.givenName) }

                Section("I am a…") {
                    Picker("Role", selection: $role) {
                        Text("Crew member").tag(Role.crew)
                        Text("Manager").tag(Role.manager)
                    }
                    .pickerStyle(.segmented)
                    if role == .manager {
                        SecureField("Manager PIN", text: $pin).keyboardType(.numberPad)
                        if wrongPIN { Text("Wrong PIN").font(.caption).foregroundStyle(Theme.alert) }
                    }
                }

                Button {
                    if role == .manager && pin != Config.managerPIN { wrongPIN = true; return }
                    state.userName = name.trimmingCharacters(in: .whitespaces)
                    state.role = role
                } label: {
                    Text("Continue")
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
            }
        }
    }
}
