import AppKit
import WebKit

@MainActor
final class MarkdownImageExporter: NSObject, WKNavigationDelegate {
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
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
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
            self.createImage(from: webView)
        }
    }

    private func createImage(from webView: WKWebView) {
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

            let contentHeight = value as? CGFloat ?? 900
            webView.frame = CGRect(x: 0, y: 0, width: 1200, height: max(900, contentHeight + 80))

            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds

            webView.takeSnapshot(with: configuration) { [weak self] image, error in
                guard let self else {
                    return
                }

                if let error {
                    completion(.failure(error))
                    return
                }

                guard
                    let image,
                    let tiffData = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmap.representation(using: .png, properties: [:])
                else {
                    completion(.failure(ExporterError.snapshotFailed))
                    return
                }

                do {
                    try pngData.write(to: outputURL, options: .atomic)
                    completion(.success(outputURL))
                } catch {
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

    private enum ExporterError: LocalizedError {
        case snapshotFailed

        var errorDescription: String? {
            "Unable to create image snapshot."
        }
    }
}
