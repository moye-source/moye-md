import AppKit
import WebKit

@MainActor
final class MarkdownPDFExporter: NSObject, WKNavigationDelegate {
    private let html: String
    private let baseURL: URL?
    private let outputURL: URL
    private let completion: (Result<URL, Error>) -> Void
    private let webView: WKWebView

    init(
        html: String,
        baseURL: URL?,
        outputURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.html = html
        self.baseURL = baseURL
        self.outputURL = outputURL
        self.completion = completion

        let configuration = WKWebViewConfiguration()
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 794, height: 1123),
            configuration: configuration
        )

        super.init()
        webView.navigationDelegate = self
    }

    func start() {
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak webView] in
            guard let self, let webView else {
                return
            }
            self.createPDF(from: webView)
        }
    }

    private func createPDF(from webView: WKWebView) {
        webView.evaluateJavaScript(
            "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
        ) { [weak self] value, error in
            guard let self else {
                return
            }

            if let error {
                completion(.failure(error))
                return
            }

            let contentHeight = value as? CGFloat ?? 1123
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(
                x: 0,
                y: 0,
                width: 794,
                height: max(1123, contentHeight + 80)
            )

            webView.createPDF(configuration: configuration) { [weak self] result in
                guard let self else {
                    return
                }

                switch result {
                case .success(let data):
                    do {
                        try data.write(to: outputURL, options: .atomic)
                        completion(.success(outputURL))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completion(.failure(error))
    }
}
