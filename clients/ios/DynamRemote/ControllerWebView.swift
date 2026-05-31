import SwiftUI
import WebKit

final class WebControllerBridge: ObservableObject {
    fileprivate weak var webView: WKWebView?

    func requestStop(completion: (() -> Void)? = nil) {
        guard let webView else {
            completion?()
            return
        }

        let clickDisconnect = """
        (function() {
          var button = document.getElementById('disconnectBtn');
          if (button) {
            button.click();
            return true;
          }
          return false;
        })();
        """

        webView.evaluateJavaScript(clickDisconnect) { [weak self] _, _ in
            self?.webView?.stopLoading()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                completion?()
            }
        }
    }
}

struct ControllerWebView: UIViewRepresentable {
    let hostURL: URL
    @ObservedObject var bridge: WebControllerBridge

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        bridge.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        bridge.webView = webView
        if webView.url != hostURL {
            webView.load(URLRequest(url: hostURL))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
                return .cancel
            }
            return AppConfig.supportedSchemes.contains(scheme) ? .allow : .cancel
        }
    }
}
