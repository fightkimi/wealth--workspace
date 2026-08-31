import Foundation

struct NewsItem: Identifiable, Equatable {
    var id: String { link.absoluteString }
    var title: String
    var source: String
    var publishedAt: Date?
    var link: URL
}

enum WebReaderURLPolicy {
    /// News links cross an untrusted-content boundary. Restricting top-level
    /// navigation here prevents local files and executable/custom schemes from
    /// being opened by webpage actions.
    static func allowedURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}

@MainActor
final class NewsStore: ObservableObject {
    @Published var items: [NewsItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard var components = URLComponents(string: "https://news.google.com/rss/search") else { return }
        components.queryItems = [
            URLQueryItem(name: "q", value: "全球市场 OR 美股 OR 港股 OR A股 财经"),
            URLQueryItem(name: "hl", value: "zh-CN"),
            URLQueryItem(name: "gl", value: "CN"),
            URLQueryItem(name: "ceid", value: "CN:zh-Hans")
        ]
        guard let url = components.url else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw QuoteServiceError.invalidResponse
            }
            let parser = RSSParser(data: data)
            let parsed = parser.parse()
            guard !parsed.isEmpty else { throw QuoteServiceError.noData }
            items = Array(parsed.prefix(40))
            errorMessage = nil
        } catch {
            items = []
            errorMessage = "资讯暂不可用，未展示缓存或模拟内容"
        }
    }
}

private final class RSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var results: [NewsItem] = []
    private var currentElement = ""
    private var title = ""
    private var link = ""
    private var pubDate = ""
    private var source = ""
    private var insideItem = false

    init(data: Data) { self.data = data }

    func parse() -> [NewsItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return results
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            title = ""
            link = ""
            pubDate = ""
            source = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title": title += string
        case "link": link += string
        case "pubDate": pubDate += string
        case "source": source += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            insideItem = false
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: cleanLink), !cleanTitle.isEmpty {
                results.append(NewsItem(
                    title: cleanTitle,
                    source: cleanSource.isEmpty ? "Google 新闻聚合" : cleanSource,
                    publishedAt: parseRSSDate(pubDate),
                    link: url
                ))
            }
        }
        currentElement = ""
    }

    private func parseRSSDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
