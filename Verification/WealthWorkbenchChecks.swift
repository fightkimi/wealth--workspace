import Foundation

@main
struct WealthWorkbenchChecks {
    private static var passed = 0

    static func main() async throws {
        try checkExactAndEstimatedQuantity()
        try checkMarketNormalization()
        try checkTradingSessions()
        try checkPublicCloseCannotBecomePremarket()
        try await checkDuplicateQuoteRequests()
        try await checkTencentPassport()
        try await checkMalformedQuoteBecomesUnavailable()
        try checkPersistence()
        try checkAPIKeyFileRoundTrip()
        try checkExchangeConversion()
        try checkMarketHoldingsSummary()
        try checkWebReaderURLPolicy()
        try checkFutuCalendarDecoding()
        print("VERIFICATION PASSED: \(passed) checks")
    }

    private static func checkExactAndEstimatedQuantity() throws {
        let exact = Holding(market: .us, name: "Exact", code: "AAPL", sector: "科技", quantity: 20, averageCost: 100, investedCost: 2_500, currency: .usd)
        try expect(!exact.isEstimated && exact.effectiveQuantity == 20 && exact.costBasis == 2_500, "精确持仓应以数量计算")
        let estimated = Holding(market: .hk, name: "Estimated", code: "700", sector: "科技", quantity: nil, averageCost: 250, investedCost: 100_000, currency: .hkd)
        try expect(estimated.isEstimated && estimated.effectiveQuantity == 400, "无数量时应由投入成本反推并标记估算")
        pass("数量与估算规则")
    }

    private static func checkMarketNormalization() throws {
        try expect(Market.us.normalizedCode("us.aapl") == "AAPL", "美股代码标准化")
        try expect(Market.hk.normalizedCode("700") == "00700", "港股代码补齐")
        try expect(Market.cn.tencentSymbol("600519") == "sh600519", "上交所映射")
        try expect(Market.cn.tencentSymbol("000001") == "sz000001", "深交所映射")
        try expect(Market.hk.futuSymbol("700") == "HK.00700", "Futu 港股映射")
        pass("市场代码映射")
    }

    private static func checkTradingSessions() throws {
        let pre = try date("2026-08-31 08:15:00", zone: "America/New_York")
        let regular = try date("2026-08-31 10:00:00", zone: "America/New_York")
        let after = try date("2026-08-31 18:00:00", zone: "America/New_York")
        let overnight = try date("2026-08-31 22:00:00", zone: "America/New_York")
        try expect(TradingClock.twelveClassification(market: .us, quoteTime: pre, now: pre, isExtended: true).0 == .preMarket, "盘前分类")
        try expect(TradingClock.twelveClassification(market: .us, quoteTime: regular, now: regular, isExtended: false).0 == .regular, "常规时段分类")
        try expect(TradingClock.twelveClassification(market: .us, quoteTime: after, now: after, isExtended: true).0 == .afterHours, "盘后分类")
        try expect(TradingClock.twelveClassification(market: .us, quoteTime: overnight, now: overnight, isExtended: true).0 == .overnight, "夜盘分类")
        pass("美股四类交易时段")
    }

    private static func checkPublicCloseCannotBecomePremarket() throws {
        let quote = try date("2026-08-28 16:00:01", zone: "America/New_York")
        let now = try date("2026-08-31 08:30:00", zone: "America/New_York")
        let result = TradingClock.publicClassification(market: .us, quoteTime: quote, now: now)
        try expect(result.0 == .recentClose && result.1 == .recentClose, "上一交易日收盘不得冒充盘前价")
        pass("跨日收盘保护")
    }

    private static func checkDuplicateQuoteRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let body = "v_hk00700=\"100~Tencent~00700~600.00~590.00~595.00~1~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~~2026-08-31 15:59:00~10.00~1.69~\";"
        MockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            guard query == "hk00700" else { throw CheckError.failed("重复证券代码应只请求一次") }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let holding = Holding(market: .hk, name: "腾讯控股", code: "700", sector: "科技", quantity: 1, averageCost: 500, investedCost: 500, currency: .hkd)
        let instrument = QuoteInstrument(holding: holding)
        let result = try await TencentQuoteService(session: session).fetch([instrument, instrument], now: Date())
        try expect(result.quotes.count == 1 && result.quotes[instrument.key] != nil, "重复持仓应复用同一行情")
        pass("重复持仓行情去重")
    }

    private static func checkTencentPassport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let body = "v_usAAPL=\"200~Apple~AAPL.OQ~319.70~314.58~316.85~1~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~~2026-08-28 16:00:01~5.12~1.63~\";"
        MockURLProtocol.handler = { request in
            let headers = ["Date": "Mon, 31 Aug 2026 12:00:00 GMT"]
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, Data(body.utf8))
        }
        let instrument = QuoteInstrument(holding: Holding(market: .us, name: "Apple", code: "AAPL", sector: "科技", quantity: 1, averageCost: 300, investedCost: 300, currency: .usd))
        let result = try await TencentQuoteService(session: session).fetch([instrument], now: Date())
        guard let quote = result.quotes[instrument.key] else { throw CheckError.failed("有效公开行情没有被解析") }
        try expect(abs(quote.price - 319.70) < 0.0001, "现价解析")
        try expect(abs(quote.previousClose - 314.58) < 0.0001, "昨收解析")
        try expect(quote.passport.source == "腾讯公开备用行情" && quote.passport.delayStatus == .possiblyDelayed, "来源与延迟标识")
        try expect(quote.passport.market == .us && quote.passport.currency == .usd, "市场与币种标识")
        try expect(!quote.passport.comparisonBasis.isEmpty, "比较基准")
        pass("公开行情数据护照")
    }

    private static func checkMalformedQuoteBecomesUnavailable() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("v_usBAD=\"broken\";".utf8))
        }
        let instrument = QuoteInstrument(holding: Holding(market: .us, name: "Bad", code: "BAD", sector: "", quantity: 1, averageCost: 1, investedCost: 1, currency: .usd))
        let result = try await TencentQuoteService(session: session).fetch([instrument], now: Date())
        try expect(result.quotes[instrument.key] == nil && result.failures[instrument.key] != nil, "异常响应必须显示暂无数据")
        pass("失效接口降级")
    }

    private static func checkPersistence() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/verification/wealth-workbench-check-\(UUID().uuidString)")
        let store = PortfolioFileStore(fileURL: directory.appendingPathComponent("portfolio.json"))
        let value = PortfolioData(
            cash: [CashBalance(currency: .cny, amount: 12_345, note: "活期")],
            holdings: [Holding(id: UUID(), market: .cn, name: "测试", code: "600000", sector: "金融", quantity: 100, averageCost: 9, investedCost: 900, currency: .cny, createdAt: Date(timeIntervalSince1970: 1_700_000_000))],
            events: [],
            settings: AppSettings()
        )
        try store.save(value)
        try expect(try store.load() == value, "资产数据原子写入后应可还原")
        pass("本地持久化")
    }

    private static func checkExchangeConversion() throws {
        let snapshot = ExchangeRateSnapshot(base: .cny, date: Date(), rates: [.cny: 1, .usd: 0.14], source: "test", fetchedAt: Date())
        try expect(abs((snapshot.convert(140, from: .usd) ?? 0) - 1_000) < 0.0001, "外币换算")
        try expect(snapshot.convert(100, from: .cny) == 100, "基准币种直通")
        pass("汇率换算")
    }

    @MainActor
    private static func checkMarketHoldingsSummary() throws {
        let cn = Holding(market: .cn, name: "A股", code: "600000", sector: "金融", quantity: 10, averageCost: 10, investedCost: 100, currency: .cny)
        let us = Holding(market: .us, name: "美股", code: "TEST", sector: "科技", quantity: 2, averageCost: 50, investedCost: 100, currency: .usd)
        let data = PortfolioData(holdings: [cn, us], settings: AppSettings(baseCurrency: .cny))
        let store = AppStore(
            persistence: StaticPortfolioStore(value: data),
            apiKeyStore: EmptyAPIKeyStore()
        )
        store.exchangeRates = ExchangeRateSnapshot(
            base: .cny,
            date: Date(),
            rates: [.cny: 1, .usd: 0.2],
            source: "test",
            fetchedAt: Date()
        )
        store.quotes = [
            cn.quoteKey: quote(for: cn, price: 12, previousClose: 11),
            us.quoteKey: quote(for: us, price: 60, previousClose: 55)
        ]

        let all = store.holdingsSummary()
        try expect(all.positionCount == 2 && all.marketValue == 720, "全部持仓应按基准币种汇总")
        try expect(all.dailyProfit == 60 && all.totalProfit == 120, "跨市场盈亏应按汇率折算")

        let cnOnly = store.holdingsSummary(for: .cn)
        try expect(cnOnly.positionCount == 1 && cnOnly.marketValue == 120, "A股分类应只包含 A股持仓")
        let usOnly = store.holdingsSummary(for: .us)
        try expect(usOnly.positionCount == 1 && usOnly.marketValue == 600, "美股分类应只包含美股持仓并折算")
        try expect(store.holdingsSummary(for: .hk).positionCount == 0, "无港股时分类汇总应为空")
        pass("持仓汇总与市场分类")
    }

    private static func quote(for holding: Holding, price: Double, previousClose: Double) -> QuoteSnapshot {
        QuoteSnapshot(
            key: holding.quoteKey,
            code: holding.normalizedCode,
            name: holding.name,
            price: price,
            previousClose: previousClose,
            change: price - previousClose,
            percentChange: (price - previousClose) / previousClose * 100,
            passport: PricePassport(
                market: holding.market,
                currency: holding.currency,
                priceType: .regular,
                session: .regular,
                comparisonBasis: "test",
                quoteTime: Date(),
                fetchedAt: Date(),
                source: "test",
                delayStatus: .realtime,
                marketTimeZoneIdentifier: holding.market.timeZone.identifier
            )
        )
    }

    private static func checkAPIKeyFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wealth-api-key-check-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("twelve-data-api-key.txt")
        let store = APIKeyFileStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        try expect(try store.load() == nil, "不存在的本地凭证应返回空")
        try store.save("test-key-not-a-real-secret")
        try expect(try APIKeyFileStore(fileURL: fileURL).load() == "test-key-not-a-real-secret", "新实例应可读取已保存的本地凭证")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        try expect(permissions == 0o600, "凭证文件权限必须为 0600")

        try store.delete()
        try expect(try store.load() == nil, "移除 Key 只应删除指定凭证文件")
        pass("本地 API Key 持久化与权限")
    }

    private static func checkWebReaderURLPolicy() throws {
        try expect(WebReaderURLPolicy.allowedURL(URL(string: "https://example.com/news")) != nil, "HTTPS 资讯应允许内嵌加载")
        try expect(WebReaderURLPolicy.allowedURL(URL(string: "http://example.com/news")) == nil, "HTTP 资讯不得进入内嵌阅读器")
        try expect(WebReaderURLPolicy.allowedURL(URL(string: "file:///tmp/private.txt")) == nil, "本地文件协议必须拦截")
        try expect(WebReaderURLPolicy.allowedURL(URL(string: "javascript:alert(1)")) == nil, "可执行协议必须拦截")
        try expect(WebReaderURLPolicy.allowedURL(URL(string: "data:text/html,hello")) == nil, "内联数据协议必须拦截")
        pass("内嵌阅读器 URL 安全边界")
    }

    private static func checkFutuCalendarDecoding() throws {
        let payload = #"{"ok":true,"server_timestamp":1788165313,"failures":[],"events":[{"id":"economic:1","type":"economic","title":"中国制造业PMI","timestamp":1788139800,"date":null,"country":"中国","market":null,"symbol":null,"importance":3,"previous":"49.2","consensus":"49.6","actual":"49.8","detail":null,"source":"Futu OpenD"},{"id":"earnings:US.TEST","type":"earnings","title":"Test 财报发布","timestamp":null,"date":"2026-09-02","country":null,"market":"US","symbol":"US.TEST","importance":null,"previous":null,"consensus":"1.2","actual":null,"detail":"FY2026 Q2","source":"Futu OpenD"}]}"#
        let fetchedAt = Date(timeIntervalSince1970: 1_788_165_400)
        let result = try FutuQuoteService(bridgeURL: nil).decodeCalendarBridge(Data(payload.utf8), fetchedAt: fetchedAt)
        try expect(result.events.count == 2, "Futu 日历事件应完整解析")
        try expect(result.events[0].kind == .economic && result.events[0].importance == 3, "经济事件重要性应标准化")
        let earnings = try result.events.first(where: { $0.kind == .earnings }).unwrap("财报事件缺失")
        try expect(earnings.market == .us && earnings.symbol == "US.TEST", "财报事件应保留市场与证券代码")
        try expect(!earnings.hasExactTime, "仅有发布日期时不得伪装为精确发布时间")
        try expect(result.events.allSatisfy { $0.source == "Futu OpenD" && $0.fetchedAt == fetchedAt }, "日历来源与抓取时间应保留")
        pass("Futu 官方事件日历解析")
    }

    private static func date(_ value: String, zone: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let result = formatter.date(from: value) else { throw CheckError.failed("测试日期无法解析") }
        return result
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw CheckError.failed(message) }
    }

    private static func pass(_ name: String) {
        passed += 1
        print("PASS \(passed): \(name)")
    }
}

private struct StaticPortfolioStore: PortfolioPersisting {
    let value: PortfolioData
    var displayPath: String { "/tmp/verification-portfolio.json" }
    func load() throws -> PortfolioData { value }
    func save(_ value: PortfolioData) throws {}
}

private struct EmptyAPIKeyStore: APIKeyPersisting {
    var displayPath: String { "/tmp/verification-api-key.txt" }
    func load() throws -> String? { nil }
    func save(_ value: String) throws {}
    func delete() throws {}
}

private enum CheckError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): return "CHECK FAILED: \(message)" }
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw CheckError.failed(message) }
        return value
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
