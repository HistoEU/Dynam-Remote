import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var hostSessionStore: HostSessionStore
    @StateObject private var bridge = WebControllerBridge()
    @State private var activeHostURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let activeHostURL {
                    ControllerWebView(hostURL: activeHostURL, bridge: bridge)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Controller")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    closeController()
                                } label: {
                                    Label("Host", systemImage: "chevron.left")
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(role: .destructive) {
                                    stopController()
                                } label: {
                                    Label("Stop", systemImage: "stop.circle")
                                }
                            }
                        }
                } else {
                    HostEntryView { url in
                        activeHostURL = url
                    }
                }
            }
        }
        .onAppear {
            if activeHostURL == nil, let savedHostURL = hostSessionStore.savedHostURL {
                activeHostURL = savedHostURL
            }
        }
    }

    private func stopController() {
        bridge.requestStop {
            activeHostURL = nil
        }
    }

    private func closeController() {
        bridge.requestStop {
            activeHostURL = nil
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HostSessionStore(keychain: PreviewContentKeychainStore()))
}

private final class PreviewContentKeychainStore: KeychainStoring {
    func saveString(_ value: String, account: String) throws {}
    func readString(account: String) throws -> String? { "http://192.168.1.20:4317/" }
    func delete(account: String) throws {}
}
