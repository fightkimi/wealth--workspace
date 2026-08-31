import Foundation
import CoreFoundation
import Network

struct QuoteInstrument: Equatable {
    var key: String
    var name: String
    var market: Market
    var code: String
    var currency: CurrencyCode
    var tencentSymbol: String

    init(holding: Holding) {
        key = holding.quoteKey
        name = holding.name
        market = holding.market
        code = holding.normalizedCode
        currency = holding.currency
        tencentSymbol = holding.market.tencentSymbol(holding.code)
    }

    init(benchmark: Benchmark) {
        key = benchmark.key
        name = benchmark.name
        market = benchmark.market
        code = benchmark.code
        currency = benchmark.currency
        tencentSymbol = benchmark.tencentSymbol
    }
}

struct QuoteBatchResult {
    var quotes: [String: QuoteSnapshot]
    var failures: [String: QuoteFailure]
    var serverDate: Date?
    var source: String
}

enum QuoteServiceError: LocalizedError {
    case invalidResponse
    case http(Int)
    case provider(String)
    case noData
    case bridgeUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "行情服务返回了无法识别的内容"
        case .http(let code): return "行情服务 HTTP \(code)"
        case .provider(let message): return message
        case .noData: return "行情服务没有返回有效价格"
        case .bridgeUnavailable: return "Futu OpenD 连接组件不可用"
        }
    }
}

enum NetworkDateParser {
    static func serverDate(from response: URLResponse) -> Date? {
        guard let http = response as? HTTPURLResponse,
              let raw = http.value(forHTTPHeaderField: "Date") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: raw)
    }
}

enum TradingClock {
    static func publicClassification(market: Market, quoteTime: Date, now: Date) -> (TradingSession, PriceType) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        guard calendar.isDate(quoteTime, inSameDayAs: now) else { return (.recentClose, .recentClose) }
        let weekday = calendar.component(.weekday, from: now)
        if weekday == 1 || weekday == 7 { return (.recentClose, .recentClose) }

        let nowMinutes = minutes(now, calendar: calendar)
        let quoteMinutes = minutes(quoteTime, calendar: calendar)
        switch market {
        case .us:
            if nowMinutes >= 570 && nowMinutes < 960 && quoteMinutes >= 570 && quoteMinutes <= 961 {
                return (.regular, .regular)
            }
            if nowMinutes >= 960 && quoteMinutes >= 950 { return (.todayClose, .todayClose) }
            return (.recentClose, .recentClose)
        case .hk:
            if nowMinutes >= 720 && nowMinutes < 780 { return (.middayBreak, .regular) }
            if (nowMinutes >= 570 && nowMinutes < 720) || (nowMinutes >= 780 && nowMinutes < 960) {
                return (.regular, .regular)
            }
            if nowMinutes >= 960 && quoteMinutes >= 950 { return (.todayClose, .todayClose) }
            return (.recentClose, .recentClose)
        case .cn:
            if nowMinutes >= 690 && nowMinutes < 780 { return (.middayBreak, .regular) }
            if (nowMinutes >= 570 && nowMinutes < 690) || (nowMinutes >= 780 && nowMinutes < 900) {
                return (.regular, .regular)
            }
            if nowMinutes >= 900 && quoteMinutes >= 890 { return (.todayClose, .todayClose) }
            return (.recentClose, .recentClose)
        }
    }

    static func twelveClassification(market: Market, quoteTime: Date, now: Date, isExtended: Bool) -> (TradingSession, PriceType) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        if isExtended && market == .us {
            let value = minutes(quoteTime, calendar: calendar)
            if value >= 240 && value < 570 { return (.preMarket, .preMarket) }
            if value >= 960 && value < 1200 { return (.afterHours, .afterHours) }
            if value >= 1200 || value < 240 { return (.overnight, .overnight) }
        }
        return publicClassification(market: market, quoteTime: quoteTime, now: now)
    }

    static func futuClassification(state: String, quoteTime: Date, now: Date, market: Market) -> (TradingSession, PriceType) {
        let normalized = state.uppercased()
        if normalized.contains("PRE_MARKET") { return (.preMarket, .preMarket) }
        if normalized.contains("AFTER_HOURS_BEGIN") { return (.afterHours, .afterHours) }
        if normalized == "OVERNIGHT" || normalized.contains("NIGHT_OPEN") { return (.overnight, .overnight) }
        if ["MORNING", "AFTERNOON", "OPEN", "FUTURE_DAY_OPEN"].contains(normalized) { return (.regular, .regular) }
        return publicClassification(market: market, quoteTime: quoteTime, now: now)
    }

    private static func minutes(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

final class TencentQuoteService {
    private let session: URLSession
    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ instruments: [QuoteInstrument], now: Date) async throws -> QuoteBatchResult {
        guard !instruments.isEmpty else {
            return QuoteBatchResult(quotes: [:], failures: [:], serverDate: nil, source: "腾讯公开备用行情")
        }
        var lookup: [String: QuoteInstrument] = [:]
        var requestedSymbols: [String] = []
        for instrument in instruments {
            let symbol = instrument.tencentSymbol.lowercased()
            guard lookup[symbol] == nil else { continue }
            lookup[symbol] = instrument
            requestedSymbols.append(instrument.tencentSymbol)
        }
        let symbols = requestedSymbols.joined(separator: ",")
        guard var components = URLComponents(string: "https://qt.gtimg.cn/") else { throw QuoteServiceError.invalidResponse }
        components.queryItems = [URLQueryItem(name: "q", value: symbols)]
        guard let url = components.url else { throw QuoteServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("WealthWorkbench/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QuoteServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw QuoteServiceError.http(http.statusCode) }
        guard let body = String(data: data, encoding: Self.gb18030) ?? String(data: data, encoding: .utf8) else {
            throw QuoteServiceError.invalidResponse
        }

        let fetchedAt = Date()
        let serverDate = NetworkDateParser.serverDate(from: response)
        let effectiveNow = serverDate ?? now
        var quotes: [String: QuoteSnapshot] = [:]
        var failures: [String: QuoteFailure] = [:]

        for line in body.components(separatedBy: ";") where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let variable = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            let symbol = variable.replacingOccurrences(of: "v_", with: "").lowercased()
            guard let instrument = lookup[symbol] else { continue }
            let payload = line[line.index(after: equals)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
            let fields = payload.components(separatedBy: "~")
            guard fields.count > 32,
                  let parsedPrice = Double(fields[3]), parsedPrice > 0,
                  let parsedPrevious = Double(fields[4]), parsedPrevious > 0,
                  let quoteTime = parseTencentTime(fields[30], market: instrument.market) else {
                failures[instrument.key] = QuoteFailure(
                    key: instrument.key,
                    message: "公开行情字段缺失或无法校验",
                    source: "腾讯公开备用行情",
                    fetchedAt: fetchedAt
                )
                continue
            }
            let price: Double = parsedPrice
            let previous: Double = parsedPrevious
            let classification = TradingClock.publicClassification(
                market: instrument.market,
                quoteTime: quoteTime,
                now: effectiveNow
            )
            let passport = PricePassport(
                market: instrument.market,
                currency: instrument.currency,
                priceType: classification.1,
                session: classification.0,
                comparisonBasis: "上一常规交易日收盘价",
                quoteTime: quoteTime,
                fetchedAt: fetchedAt,
                source: "腾讯公开备用行情",
                delayStatus: .possiblyDelayed,
                marketTimeZoneIdentifier: instrument.market.timeZone.identifier
            )
            quotes[instrument.key] = QuoteSnapshot(
                key: instrument.key,
                code: instrument.code,
                name: instrument.name,
                price: price,
                previousClose: previous,
                change: price - previous,
                percentChange: (price - previous) / previous * 100,
                passport: passport
            )
        }

        for instrument in instruments where quotes[instrument.key] == nil && failures[instrument.key] == nil {
            failures[instrument.key] = QuoteFailure(
                key: instrument.key,
                message: "公开行情未返回该标的",
                source: "腾讯公开备用行情",
                fetchedAt: fetchedAt
            )
        }
        return QuoteBatchResult(quotes: quotes, failures: failures, serverDate: serverDate, source: "腾讯公开备用行情")
    }

    private func parseTencentTime(_ raw: String, market: Market) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyyMMddHHmmss"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = market.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private struct TwelveResponse: Decodable {
    var symbol: String?
    var name: String?
    var currency: String?
    var datetime: String?
    var timestamp: Double?
    var close: String?
    var previousClose: String?
    var change: String?
    var percentChange: String?
    var isExtendedHours: Bool?
    var status: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case symbol, name, currency, datetime, timestamp, close, change, status, message
        case previousClose = "previous_close"
        case percentChange = "percent_change"
        case isExtendedHours = "is_extended_hours"
    }
}

final class TwelveDataQuoteService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ instruments: [QuoteInstrument], apiKey: String, now: Date) async -> QuoteBatchResult {
        var quotes: [String: QuoteSnapshot] = [:]
        var failures: [String: QuoteFailure] = [:]
        var serverDate: Date?

        for instrument in instruments {
            do {
                guard var components = URLComponents(string: "https://api.twelvedata.com/quote") else {
                    throw QuoteServiceError.invalidResponse
                }
                components.queryItems = [
                    URLQueryItem(name: "symbol", value: instrument.code),
                    // Twelve Data requires prepost=true for extended-hours quotes.
                    // Source: https://support.twelvedata.com/en/articles/5195429-pre-post-market-data
                    URLQueryItem(name: "prepost", value: "true")
                ]
                guard let url = components.url else { throw QuoteServiceError.invalidResponse }
                var request = URLRequest(url: url)
                request.timeoutInterval = 12
                request.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw QuoteServiceError.invalidResponse }
                if serverDate == nil { serverDate = NetworkDateParser.serverDate(from: response) }
                guard (200..<300).contains(http.statusCode) else { throw QuoteServiceError.http(http.statusCode) }
                let decoded = try JSONDecoder().decode(TwelveResponse.self, from: data)
                if decoded.status == "error" { throw QuoteServiceError.provider(decoded.message ?? "Twelve Data 返回错误") }
                guard let closeRaw = decoded.close, let price = Double(closeRaw), price > 0,
                      let previousRaw = decoded.previousClose, let previous = Double(previousRaw), previous > 0 else {
                    throw QuoteServiceError.noData
                }
                let quoteTime: Date
                if let timestamp = decoded.timestamp, timestamp > 0 {
                    quoteTime = Date(timeIntervalSince1970: timestamp)
                } else if let datetime = decoded.datetime,
                          let parsed = parseDate(datetime, timeZone: instrument.market.timeZone) {
                    quoteTime = parsed
                } else {
                    throw QuoteServiceError.invalidResponse
                }
                let effectiveNow = serverDate ?? now
                let classification = TradingClock.twelveClassification(
                    market: instrument.market,
                    quoteTime: quoteTime,
                    now: effectiveNow,
                    isExtended: decoded.isExtendedHours ?? false
                )
                let fetchedAt = Date()
                let passport = PricePassport(
                    market: instrument.market,
                    currency: instrument.currency,
                    priceType: classification.1,
                    session: classification.0,
                    comparisonBasis: classification.0 == .preMarket ? "上一常规交易日收盘价" : "上一常规交易日收盘价",
                    quoteTime: quoteTime,
                    fetchedAt: fetchedAt,
                    source: "Twelve Data",
                    delayStatus: .entitlementDependent,
                    marketTimeZoneIdentifier: instrument.market.timeZone.identifier
                )
                quotes[instrument.key] = QuoteSnapshot(
                    key: instrument.key,
                    code: instrument.code,
                    name: decoded.name ?? instrument.name,
                    price: price,
                    previousClose: previous,
                    change: price - previous,
                    percentChange: (price - previous) / previous * 100,
                    passport: passport
                )
            } catch {
                failures[instrument.key] = QuoteFailure(
                    key: instrument.key,
                    message: error.localizedDescription,
                    source: "Twelve Data",
                    fetchedAt: Date()
                )
            }
        }
        return QuoteBatchResult(quotes: quotes, failures: failures, serverDate: serverDate, source: "Twelve Data")
    }

    private func parseDate(_ value: String, timeZone: TimeZone) -> Date? {
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

struct FutuBridgeOutput: Decodable {
    struct Item: Decodable {
        var code: String
        var name: String?
        var marketState: String
        var updateTime: String
        var lastPrice: Double?
        var previousClose: Double?
        var prePrice: Double?
        var afterPrice: Double?
        var overnightPrice: Double?

        enum CodingKeys: String, CodingKey {
            case code, name
            case marketState = "market_state"
            case updateTime = "update_time"
            case lastPrice = "last_price"
            case previousClose = "prev_close_price"
            case prePrice = "pre_price"
            case afterPrice = "after_price"
            case overnightPrice = "overnight_price"
        }
    }

    var ok: Bool
    var message: String?
    var serverTimestamp: Double?
    var quotes: [Item]?

    enum CodingKeys: String, CodingKey {
        case ok, message, quotes
        case serverTimestamp = "server_timestamp"
    }
}

struct FutuCalendarBridgeOutput: Decodable {
    struct Item: Decodable {
        var id: String
        var type: String
        var title: String
        var timestamp: Double?
        var date: String?
        var country: String?
        var market: String?
        var symbol: String?
        var importance: Double?
        var previous: String?
        var consensus: String?
        var actual: String?
        var detail: String?
        var source: String
    }

    var ok: Bool
    var message: String?
    var serverTimestamp: Double?
    var events: [Item]?
    var failures: [String]?

    enum CodingKeys: String, CodingKey {
        case ok, message, events, failures
        case serverTimestamp = "server_timestamp"
    }
}

final class FutuQuoteService {
    private let bridgeURL: URL?

    init(bridgeURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("Tools/futu_bridge/futu_bridge")) {
        self.bridgeURL = bridgeURL
    }

    var isBridgeInstalled: Bool {
        guard let bridgeURL else { return false }
        return FileManager.default.isExecutableFile(atPath: bridgeURL.path)
    }

    func fetch(_ instruments: [QuoteInstrument], host: String, port: Int, now: Date) async throws -> QuoteBatchResult {
        guard let bridgeURL, FileManager.default.isExecutableFile(atPath: bridgeURL.path) else {
            throw QuoteServiceError.bridgeUnavailable
        }
        guard await isOpenDReachable(host: host, port: port) else {
            throw QuoteServiceError.provider("Futu OpenD 未在 \(host):\(port) 监听")
        }
        var instrumentByCode: [String: QuoteInstrument] = [:]
        var futuCodes: [String] = []
        for instrument in instruments {
            let code = instrument.market.futuSymbol(instrument.code)
            guard instrumentByCode[code] == nil else { continue }
            instrumentByCode[code] = instrument
            futuCodes.append(code)
        }
        let codeData = try JSONEncoder().encode(futuCodes)
        let codeJSON = String(data: codeData, encoding: .utf8) ?? "[]"
        let data = try await runBridge(bridgeURL, arguments: ["quote", "--host", host, "--port", String(port), "--codes", codeJSON])
        let output = try JSONDecoder().decode(FutuBridgeOutput.self, from: data)
        guard output.ok else { throw QuoteServiceError.provider(output.message ?? "Futu OpenD 返回错误") }

        let serverDate = output.serverTimestamp.map(Date.init(timeIntervalSince1970:))
        let effectiveNow = serverDate ?? now
        var quotes: [String: QuoteSnapshot] = [:]
        var failures: [String: QuoteFailure] = [:]
        for item in output.quotes ?? [] {
            guard let instrument = instrumentByCode[item.code] else { continue }
            guard let quoteTime = parseFutuTime(item.updateTime, market: instrument.market),
                  let previous = item.previousClose, previous > 0 else {
                failures[instrument.key] = QuoteFailure(key: instrument.key, message: "Futu 行情时间或昨收缺失", source: "Futu OpenD", fetchedAt: Date())
                continue
            }
            let classification = TradingClock.futuClassification(
                state: item.marketState,
                quoteTime: quoteTime,
                now: effectiveNow,
                market: instrument.market
            )
            let selectedPrice: Double?
            // Futu exposes pre, regular, after-hours and overnight prices as
            // distinct snapshot fields; selection is driven by market_state.
            // Source: https://openapi.futunn.com/futu-api-doc/en/quote/get-market-snapshot.html
            switch classification.0 {
            case .preMarket: selectedPrice = item.prePrice
            case .afterHours: selectedPrice = item.afterPrice
            case .overnight: selectedPrice = item.overnightPrice
            default: selectedPrice = item.lastPrice
            }
            guard let price = selectedPrice, price > 0 else {
                failures[instrument.key] = QuoteFailure(
                    key: instrument.key,
                    message: "\(classification.0.rawValue)没有可验证价格",
                    source: "Futu OpenD",
                    fetchedAt: Date()
                )
                continue
            }
            let passport = PricePassport(
                market: instrument.market,
                currency: instrument.currency,
                priceType: classification.1,
                session: classification.0,
                comparisonBasis: "上一常规交易日收盘价",
                quoteTime: quoteTime,
                fetchedAt: Date(),
                source: "Futu OpenD",
                delayStatus: .entitlementDependent,
                marketTimeZoneIdentifier: instrument.market.timeZone.identifier
            )
            quotes[instrument.key] = QuoteSnapshot(
                key: instrument.key,
                code: instrument.code,
                name: item.name ?? instrument.name,
                price: price,
                previousClose: previous,
                change: price - previous,
                percentChange: (price - previous) / previous * 100,
                passport: passport
            )
        }
        for instrument in instruments where quotes[instrument.key] == nil && failures[instrument.key] == nil {
            failures[instrument.key] = QuoteFailure(key: instrument.key, message: "Futu 未返回该标的", source: "Futu OpenD", fetchedAt: Date())
        }
        return QuoteBatchResult(quotes: quotes, failures: failures, serverDate: serverDate, source: "Futu OpenD")
    }

    func fetchCalendar(
        holdings: [Holding],
        host: String,
        port: Int,
        beginDate: Date,
        endDate: Date
    ) async throws -> MarketCalendarResult {
        guard let bridgeURL, FileManager.default.isExecutableFile(atPath: bridgeURL.path) else {
            throw QuoteServiceError.bridgeUnavailable
        }
        guard await isOpenDReachable(host: host, port: port) else {
            throw QuoteServiceError.provider("Futu OpenD 未在 \(host):\(port) 监听")
        }
        let codes = Array(Set(holdings.map { $0.market.futuSymbol($0.code) })).sorted()
        let codeData = try JSONEncoder().encode(codes)
        let codeJSON = String(data: codeData, encoding: .utf8) ?? "[]"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        let data = try await runBridge(
            bridgeURL,
            arguments: [
                "calendar", "--host", host, "--port", String(port),
                "--begin-date", formatter.string(from: beginDate),
                "--end-date", formatter.string(from: endDate),
                "--codes", codeJSON,
            ],
            timeoutSeconds: 22
        )
        return try decodeCalendarBridge(data, fetchedAt: Date())
    }

    func decodeCalendarBridge(_ data: Data, fetchedAt: Date) throws -> MarketCalendarResult {
        let output = try JSONDecoder().decode(FutuCalendarBridgeOutput.self, from: data)
        guard output.ok else {
            throw QuoteServiceError.provider(output.message ?? "Futu 日历返回错误")
        }
        let events = (output.events ?? []).compactMap { item -> MarketCalendarEvent? in
            let kind: MarketCalendarEventKind
            switch item.type {
            case "economic": kind = .economic
            case "earnings": kind = .earnings
            default: return nil
            }
            let exactTimestamp = item.timestamp.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            let date = exactTimestamp ?? item.date.flatMap { parseCalendarDate($0, marketCode: item.market) }
            guard let date else { return nil }
            return MarketCalendarEvent(
                id: item.id,
                date: date,
                hasExactTime: exactTimestamp != nil,
                title: item.title,
                kind: kind,
                country: item.country,
                market: market(fromFutuCode: item.market),
                symbol: item.symbol,
                importance: item.importance.map { Int($0.rounded()) },
                previous: item.previous,
                consensus: item.consensus,
                actual: item.actual,
                detail: item.detail,
                source: item.source,
                fetchedAt: fetchedAt
            )
        }
        .sorted { $0.date < $1.date }
        return MarketCalendarResult(
            events: events,
            failures: output.failures ?? [],
            serverDate: output.serverTimestamp.map(Date.init(timeIntervalSince1970:))
        )
    }

    private func isOpenDReachable(host: String, port: Int) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.wealthworkbench.opend-probe")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            let gate = ConnectionProbeGate(continuation: continuation, connection: connection)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.finish(true)
                case .failed, .cancelled: gate.finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(800)) { gate.finish(false) }
        }
    }

    private func runBridge(_ url: URL, arguments: [String], timeoutSeconds: Int = 12) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                let signal = DispatchSemaphore(value: 0)
                let collector = BridgePipeCollector()
                process.executableURL = url
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = errors
                output.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else {
                        signal.signal()
                        return
                    }
                    if collector.appendOutput(chunk) { signal.signal() }
                }
                errors.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if !chunk.isEmpty { collector.appendError(chunk) }
                }
                process.terminationHandler = { _ in signal.signal() }
                do {
                    try process.run()
                    let waitResult = signal.wait(timeout: .now() + .seconds(timeoutSeconds))
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil

                    if let data = collector.firstOutputLine ?? (!process.isRunning ? collector.outputSnapshot : nil), !data.isEmpty {
                        if process.isRunning { process.terminate() }
                        continuation.resume(returning: data)
                        return
                    }

                    if process.isRunning { process.terminate() }
                    if waitResult == .timedOut {
                        continuation.resume(throwing: QuoteServiceError.provider("连接 Futu OpenD 超时"))
                        return
                    }

                    let preferred = collector.errorSnapshot.isEmpty ? collector.outputSnapshot : collector.errorSnapshot
                    let message = String(data: preferred, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let safeMessage = (message?.isEmpty == false ? message : nil) ?? "Futu 连接组件执行失败"
                    continuation.resume(throwing: QuoteServiceError.provider(safeMessage))
                } catch {
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func parseFutuTime(_ value: String, market: Market) -> Date? {
        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = market.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private func parseCalendarDate(_ value: String, marketCode: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = market(fromFutuCode: marketCode)?.timeZone ?? TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "\(value) 12:00:00")
    }

    private func market(fromFutuCode value: String?) -> Market? {
        switch value {
        case "US": return .us
        case "HK": return .hk
        case "SH", "SZ": return .cn
        default: return nil
        }
    }
}

private final class BridgePipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var errors = Data()

    @discardableResult
    func appendOutput(_ data: Data) -> Bool {
        lock.lock()
        output.append(data)
        let hasLine = output.contains(0x0A)
        lock.unlock()
        return hasLine
    }

    func appendError(_ data: Data) {
        lock.lock()
        errors.append(data)
        lock.unlock()
    }

    var firstOutputLine: Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let newline = output.firstIndex(of: 0x0A) else { return nil }
        return Data(output[..<newline])
    }

    var outputSnapshot: Data {
        lock.lock()
        defer { lock.unlock() }
        return output
    }

    var errorSnapshot: Data {
        lock.lock()
        defer { lock.unlock() }
        return errors
    }
}

private final class ConnectionProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var continuation: CheckedContinuation<Bool, Never>?
    private let connection: NWConnection

    init(continuation: CheckedContinuation<Bool, Never>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ value: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        connection.cancel()
        pending?.resume(returning: value)
    }
}

struct ExchangeRateSnapshot: Equatable {
    var base: CurrencyCode
    var date: Date
    var rates: [CurrencyCode: Double]
    var source: String
    var fetchedAt: Date

    func convert(_ amount: Double, from currency: CurrencyCode) -> Double? {
        if currency == base { return amount }
        guard let rate = rates[currency], rate > 0 else { return nil }
        return amount / rate
    }
}

private struct FrankfurterRateRow: Decodable {
    var date: String
    var base: String
    var quote: String
    var rate: Double
}

final class ExchangeRateService {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetch(base: CurrencyCode) async throws -> (ExchangeRateSnapshot, Date?) {
        let targets = CurrencyCode.allCases.filter { $0 != base }.map(\.rawValue).joined(separator: ",")
        guard var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates") else {
            throw QuoteServiceError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "base", value: base.rawValue),
            URLQueryItem(name: "quotes", value: targets),
            URLQueryItem(name: "providers", value: "ECB")
        ]
        guard let url = components.url else { throw QuoteServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QuoteServiceError.invalidResponse
        }
        let rows = try JSONDecoder().decode([FrankfurterRateRow].self, from: data)
        guard let first = rows.first else { throw QuoteServiceError.noData }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: first.date) else { throw QuoteServiceError.invalidResponse }
        var rates: [CurrencyCode: Double] = [base: 1]
        for row in rows {
            if let code = CurrencyCode(rawValue: row.quote), row.rate > 0 { rates[code] = row.rate }
        }
        return (
            ExchangeRateSnapshot(base: base, date: date, rates: rates, source: "ECB 参考汇率 / Frankfurter", fetchedAt: Date()),
            NetworkDateParser.serverDate(from: response)
        )
    }
}
