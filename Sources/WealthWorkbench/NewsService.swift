import Foundation

struct NewsItem: Codable, Identifiable, Equatable {
    var id: String { link.absoluteString }
    var title: String
    var source: String
    var publishedAt: Date?
    var link: URL
}

struct NewsCacheSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var items: [NewsItem]
}

protocol NewsCachePersisting {
    func load() throws -> NewsCacheSnapshot?
    func save(_ snapshot: NewsCacheSnapshot) throws
}

struct NewsCacheFileStore: NewsCachePersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = support
                .appendingPathComponent("WealthWorkbench", isDirectory: true)
                .appendingPathComponent("Cache", isDirectory: true)
                .appendingPathComponent("news.json")
        }
    }

    func load() throws -> NewsCacheSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NewsCacheSnapshot.self, from: data)
    }

    func save(_ snapshot: NewsCacheSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
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
    @Published var advisoryMessage: String?
    @Published var isShowingCachedData = false
    @Published var cacheTimestamp: Date?

    private let session: URLSession
    private let cacheStore: NewsCachePersisting
    private let now: () -> Date
    private let maximumCacheAge: TimeInterval

    init(
        session: URLSession = .shared,
        cacheStore: NewsCachePersisting = NewsCacheFileStore(),
        maximumCacheAge: TimeInterval = 12 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.cacheStore = cacheStore
        self.maximumCacheAge = maximumCacheAge
        self.now = now
        if let cached = try? cacheStore.load(),
           !cached.items.isEmpty,
           now().timeIntervalSince(cached.fetchedAt) >= 0,
           now().timeIntervalSince(cached.fetchedAt) <= maximumCacheAge {
            items = cached.items
            cacheTimestamp = cached.fetchedAt
            isShowingCachedData = true
        }
    }

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
            request.timeoutInterval = 7
            request.cachePolicy = .reloadRevalidatingCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw QuoteServiceError.invalidResponse
            }
            let parsed = await Task.detached(priority: .userInitiated) {
                RSSParser(data: data).parse()
            }.value
            guard !parsed.isEmpty else { throw QuoteServiceError.noData }
            items = Array(parsed.prefix(40))
            errorMessage = nil
            advisoryMessage = nil
            isShowingCachedData = false
            let fetchedAt = now()
            cacheTimestamp = fetchedAt
            try? cacheStore.save(NewsCacheSnapshot(fetchedAt: fetchedAt, items: items))
        } catch {
            if items.isEmpty {
                errorMessage = "资讯暂不可用，未展示模拟内容"
                advisoryMessage = nil
            } else {
                errorMessage = nil
                advisoryMessage = "最新资讯暂时无法更新，当前显示已标注时间的本地缓存"
                isShowingCachedData = true
            }
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
