import Foundation

enum AppConfig {
    static let appName = "Dynam Remote"
    static let supportedSchemes: Set<String> = ["http", "https"]

    static func normalizedHostURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.contains("://") {
            withScheme = trimmed
        } else {
            withScheme = "http://\(trimmed)"
        }

        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              supportedSchemes.contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        components.scheme = scheme
        if components.path.isEmpty {
            components.path = "/"
        }

        return components.url
    }
}
