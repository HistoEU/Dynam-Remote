import Foundation
import Combine
import UIKit

@MainActor
final class HostSessionStore: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case ready(URL)
        case invalid(String)
    }

    private static let hostURLAccount = "last-host-url"

    @Published var hostURLText: String = ""
    @Published private(set) var savedHostURL: URL?
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var statusMessage: String = "Enter the host URL shown by the Dynam Remote host."

    private let keychain: KeychainStoring

    init(keychain: KeychainStoring) {
        self.keychain = keychain
        loadSavedHost()
    }

    func saveHostURLFromText() -> URL? {
        guard let url = AppConfig.normalizedHostURL(from: hostURLText) else {
            state = .invalid("Enter an http or https host URL.")
            statusMessage = "Enter the local Wi-Fi or Tailscale URL shown by the host console."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }

        do {
            try keychain.saveString(url.absoluteString, account: Self.hostURLAccount)
            savedHostURL = url
            hostURLText = url.absoluteString
            state = .ready(url)
            statusMessage = "Host saved. Pair in the controller with the current PIN."
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return url
        } catch {
            state = .invalid("Could not save host URL.")
            statusMessage = "Keychain save failed. Check device restrictions and try again."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }
    }

    func forgetSavedHost() {
        try? keychain.delete(account: Self.hostURLAccount)
        savedHostURL = nil
        hostURLText = ""
        state = .idle
        statusMessage = "Saved host cleared. Enter the current host URL to pair again."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func loadSavedHost() {
        guard let value = try? keychain.readString(account: Self.hostURLAccount),
              let url = AppConfig.normalizedHostURL(from: value) else {
            return
        }

        savedHostURL = url
        hostURLText = url.absoluteString
        state = .ready(url)
        statusMessage = "Saved host loaded. Confirm it matches the current host console."
    }
}
