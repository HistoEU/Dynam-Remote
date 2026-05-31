import SwiftUI

@main
struct DynamRemoteApp: App {
    @StateObject private var hostSessionStore = HostSessionStore(keychain: KeychainStore())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hostSessionStore)
        }
    }
}
