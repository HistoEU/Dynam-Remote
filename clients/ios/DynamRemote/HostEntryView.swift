import SwiftUI

struct HostEntryView: View {
    @EnvironmentObject private var hostSessionStore: HostSessionStore
    @FocusState private var hostFieldFocused: Bool

    let onOpen: (URL) -> Void

    var body: some View {
        Form {
            Section("Host") {
                TextField("http://192.168.1.20:4317", text: $hostSessionStore.hostURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($hostFieldFocused)
                    .submitLabel(.go)
                    .onSubmit(connect)

                Button(action: connect) {
                    Label("Open Controller", systemImage: "rectangle.connected.to.line.below")
                }

                if let savedHostURL = hostSessionStore.savedHostURL {
                    Button(role: .destructive) {
                        hostSessionStore.forgetSavedHost()
                    } label: {
                        Label("Forget Saved Host", systemImage: "trash")
                    }
                    .accessibilityHint("Clears the saved host URL from Keychain.")

                    Text(savedHostURL.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Connection") {
                Label(hostSessionStore.statusMessage, systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Use the local Wi-Fi or Tailscale URL from the host console. Pairing, approval, trusted devices, Stop, and revoke stay controlled by the host.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(AppConfig.appName)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    hostFieldFocused = false
                }
            }
        }
    }

    private func connect() {
        guard let url = hostSessionStore.saveHostURLFromText() else { return }
        onOpen(url)
    }
}

#Preview {
    NavigationStack {
        HostEntryView { _ in }
            .environmentObject(HostSessionStore(keychain: PreviewKeychainStore()))
    }
}

private final class PreviewKeychainStore: KeychainStoring {
    func saveString(_ value: String, account: String) throws {}
    func readString(account: String) throws -> String? { nil }
    func delete(account: String) throws {}
}
