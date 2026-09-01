import Foundation

@main
struct WealthWorkbenchChecks {
    private static var passed = 0

    static func main() async throws {
        try checkNavigationOrder()
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
        try await checkNewsCacheFallback()
        try checkInvestmentSkillCatalog()
        try checkInvestmentSkillRouter()
        try checkDeskSnapshotOmitsMissingQuotes()
        try checkSpaceXAIRequestAndStreamParser()
        try checkSpaceXAIKeyFileRoundTrip()
        try checkAssistantProviderCompatibility()
        try checkOpenAIRequestAndStreamParser()
        try checkOpenAICredentialFileRoundTrip()
        try await checkCredentialsRestoreAfterRelaunch()
        try checkAssistantPlacementPersistence()
        try checkAssistantResponseTableParsing()
        print("VERIFICATION PASSED: \(passed) checks")
    }

    private static func checkNavigationOrder() throws {
        try expect(
            AppSection.allCases == [.overview, .holdings, .news, .review, .calendar, .settings],
            "顶部导航应先显示今日总览，再显示我的持仓"
        )
        try expect(AppSection.overview.rawValue == "今日总览", "今日总览标签必须保持完整")
        pass("顶部导航顺序与标签")
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

    @MainActor
    private static func checkNewsCacheFallback() async throws {
        let now = Date(timeIntervalSince1970: 1_788_165_400)
        let item = NewsItem(
            title: "缓存资讯",
            source: "测试来源",
            publishedAt: now.addingTimeInterval(-300),
            link: URL(string: "https://example.com/news")!
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = NewsStore(
            session: session,
            cacheStore: StaticNewsCacheStore(snapshot: NewsCacheSnapshot(fetchedAt: now.addingTimeInterval(-60), items: [item])),
            now: { now }
        )
        try expect(store.items == [item] && store.isShowingCachedData, "资讯页应即时载入新鲜本地缓存")
        await store.refresh()
        try expect(store.items == [item], "网络失败时不得清空已显示的资讯缓存")
        try expect(store.advisoryMessage != nil && store.errorMessage == nil, "缓存回退必须明确标注而不是伪装为实时资讯")
        pass("资讯预载与缓存回退")
    }

    private static func checkInvestmentSkillCatalog() throws {
        let ids = InvestmentSkillCatalog.skills.map(\.id)
        try expect(
            ids == [
                .portfolioReview, .portfolioRisk, .positionSizing, .preDecision,
                .positionReview, .investmentChecklist, .qualityScreen, .financialHealth,
                .valuation, .peterLynch, .bearCase, .bottleneck,
                .earningsReview, .earningsPreview, .newsPulse, .macroEvent, .thesisTracker
            ],
            "助手应内置公开投研框架蒸馏后的完整技能目录"
        )
        try expect(InvestmentSkillCatalog.skills.count == 17, "公开技能应收成 17 个可调用模块")
        let compiled = InvestmentSkillCatalog.compile(skillIDs: [.auto, .portfolioReview, .portfolioReview])
        try expect(compiled.contains("AUREL Desk") && compiled.contains("组合审视"), "系统提示应包含宪章与启用技能")
        try expect(compiled.contains("暂无数据") && compiled.contains("不得把收盘价说成盘前"), "宪章必须保留行情纪律")
        try expect(!compiled.contains("## 技能：自动"), "自动路由不应作为技能正文写入")
        pass("投资助手技能目录")
    }

    private static func checkInvestmentSkillRouter() throws {
        try expect(
            InvestmentSkillRouter.resolve(query: "审视当前组合", selected: .auto, hasHoldings: true) == [.portfolioReview],
            "组合问题应路由到组合审视"
        )
        try expect(
            InvestmentSkillRouter.resolve(query: "为什么跌这么多", selected: .auto, hasHoldings: true) == [.newsPulse],
            "异动问题应路由到新闻脉搏"
        )
        try expect(
            InvestmentSkillRouter.resolve(query: "随便问问", selected: .investmentChecklist, hasHoldings: true) == [.investmentChecklist],
            "手动选择的技能应覆盖自动路由"
        )
        try expect(
            InvestmentSkillRouter.resolve(query: "你好", selected: .auto, hasHoldings: false) == [.investmentChecklist],
            "空账户默认走买入清单"
        )
        try expect(
            InvestmentSkillRouter.resolve(query: "给最大持仓写一份空方红队", selected: .auto, hasHoldings: true).first == .bearCase,
            "空方问题应优先路由到空方红队"
        )
        try expect(
            InvestmentSkillRouter.resolve(query: "这只股票该买多少", selected: .auto, hasHoldings: true).first == .positionSizing,
            "规模问题应优先路由到仓位规模而不是买入清单"
        )
        try expect(
            !InvestmentSkillRouter.resolve(query: "这只股票该买多少", selected: .auto, hasHoldings: true).contains(.investmentChecklist),
            "「该买多少」不得误入买入清单"
        )
        try expect(
            InvestmentSkillRouter.resolve(query: "Piotroski 和 ROIC 怎么样", selected: .auto, hasHoldings: true) == [.financialHealth],
            "财务质量问题应路由到财务体检"
        )
        pass("投资助手技能路由")
    }

    private static func checkDeskSnapshotOmitsMissingQuotes() throws {
        let estimated = Holding(market: .us, name: "Test Co", code: "TEST", sector: "科技", quantity: nil, averageCost: 10, investedCost: 100, currency: .usd)
        let metrics = HoldingMetrics(
            holding: estimated,
            quote: nil,
            marketValue: nil,
            dailyProfit: nil,
            totalProfit: nil,
            totalReturn: nil,
            weight: nil
        )
        let snapshot = DeskSnapshotBuilder.make(
            now: Date(timeIntervalSince1970: 1_788_165_400),
            settings: AppSettings(baseCurrency: .cny),
            summary: PortfolioSummary(totalAssets: nil, securitiesAssets: nil, cashAssets: 0, dailyProfit: nil, totalProfit: nil, totalReturn: nil, currency: .cny, isPartial: true),
            holdings: [metrics],
            failures: [
                estimated.quoteKey: QuoteFailure(key: estimated.quoteKey, message: "接口失败", source: "测试来源", fetchedAt: Date(timeIntervalSince1970: 1_788_165_400))
            ],
            cash: [],
            events: [
                MarketCalendarEvent(
                    id: "earnings:US.TEST",
                    date: Date(timeIntervalSince1970: 1_788_249_600),
                    hasExactTime: false,
                    title: "Test 财报",
                    kind: .earnings,
                    country: nil,
                    market: .us,
                    symbol: "US.TEST",
                    importance: nil,
                    previous: nil,
                    consensus: nil,
                    actual: nil,
                    detail: nil,
                    source: "Futu OpenD",
                    fetchedAt: Date(timeIntervalSince1970: 1_788_165_400)
                )
            ],
            news: [],
            benchmarks: [],
            providerStatus: "暂无可用持仓行情",
            lastRefreshAt: nil,
            timeHealth: TimeHealth(),
            exchangeRates: nil,
            calendarUpdatedAt: nil,
            calendarFailures: []
        )
        try expect(snapshot.contains("暂无数据"), "缺行情时快照必须写暂无数据")
        try expect(snapshot.contains("估算持仓"), "无数量持仓必须标明估算")
        try expect(snapshot.contains("时间待定"), "仅有日期的财报不得伪装精确时间")
        try expect(!snapshot.contains("Bearer") && !DeskSnapshotBuilder.containsCredentialLeak(snapshot), "快照不得泄漏 API Key")
        pass("投资助手持仓快照纪律")
    }

    private static func checkSpaceXAIRequestAndStreamParser() throws {
        let request = try SpaceXAIRequestBuilder.makeURLRequest(
            apiKey: "test-key-not-a-real-secret",
            messages: [SpaceXAIMessage(role: "user", content: "hello")],
            stream: true
        )
        try expect(request.url?.absoluteString == "https://api.x.ai/v1/chat/completions", "助手应请求 SpaceXAI Chat Completions")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-not-a-real-secret", "请求应使用 Bearer 本地凭证")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        try expect(body?["model"] as? String == "grok-4.6", "默认模型应为 grok-4.6")
        try expect(try SpaceXAISSEParser.contentDelta(from: #"data: {"choices":[{"delta":{"content":"你好"}}]}"#) == "你好", "SSE 增量应解析文本")
        try expect(try SpaceXAISSEParser.contentDelta(from: "data: [DONE]") == nil, "SSE 结束标记不应产出文本")
        do {
            _ = try SpaceXAIRequestBuilder.makeURLRequest(apiKey: "   ", messages: [])
            throw CheckError.failed("空 API Key 必须拒绝发请求")
        } catch SpaceXAIClientError.missingAPIKey {
            // expected
        }
        pass("SpaceXAI 请求与流式解析")
    }

    private static func checkSpaceXAIKeyFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wealth-xai-key-check-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("xai-api-key.txt")
        let store = APIKeyFileStore(filename: "xai-api-key.txt", fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save("test-xai-key-not-a-real-secret")
        try expect(try APIKeyFileStore(filename: "xai-api-key.txt", fileURL: fileURL).load() == "test-xai-key-not-a-real-secret", "SpaceXAI Key 应可从本地文件还原")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        try expect(permissions == 0o600, "SpaceXAI 凭证文件权限必须为 0600")
        pass("SpaceXAI API Key 本地权限")
    }

    private static func checkAssistantProviderCompatibility() throws {
        try expect(AppSettings().assistantProvider == .openAI, "新安装默认应提供 OpenAI GPT-5.6-sol")
        try expect(AssistantProvider.openAI.model == "gpt-5.6-sol", "OpenAI 助手模型应锁定为 gpt-5.6-sol")
        let legacy = Data(#"{"baseCurrency":"CNY","provider":"自动（按优先级）","futuHost":"127.0.0.1","futuPort":11111,"allowPublicFallback":true,"refreshIntervalSeconds":60}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        try expect(decoded.assistantProvider == .spaceXAI, "旧配置迁移时应继续使用原来的 SpaceXAI")
        pass("助手服务选择与旧配置迁移")
    }

    private static func checkOpenAIRequestAndStreamParser() throws {
        let request = try OpenAIRequestBuilder.makeURLRequest(
            apiKey: "test-openai-key-not-a-real-secret",
            endpoint: "https://gateway.example.com/v1/responses",
            messages: [AssistantMessage(role: "user", content: "hello")],
            stream: true
        )
        try expect(request.url?.absoluteString == "https://gateway.example.com/v1/responses", "OpenAI 助手应使用本机配置的 Responses 访问地址")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-openai-key-not-a-real-secret", "OpenAI 请求应使用 Bearer 本地凭证")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        try expect(body?["model"] as? String == "gpt-5.6-sol", "OpenAI 默认模型应为 gpt-5.6-sol")
        try expect(body?["store"] as? Bool == false, "投资助手响应不应由 API 持久化")
        try expect((body?["reasoning"] as? [String: Any])?["effort"] as? String == "medium", "OpenAI 应使用 medium 推理强度")
        try expect((body?["text"] as? [String: Any])?["verbosity"] as? String == "medium", "OpenAI 应使用 medium 输出详略")
        try expect(try OpenAISSEParser.contentDelta(from: #"data: {"type":"response.output_text.delta","delta":"你好"}"#) == "你好", "Responses SSE 增量应解析文本")
        try expect(try OpenAISSEParser.contentDelta(from: #"data: {"type":"response.completed","response":{}}"#) == nil, "Responses 完成事件不应重复输出文本")
        do {
            _ = try OpenAIRequestBuilder.makeURLRequest(apiKey: "   ", messages: [])
            throw CheckError.failed("OpenAI 空 API Key 必须拒绝发请求")
        } catch OpenAIClientError.missingAPIKey {
            // expected
        }
        do {
            _ = try OpenAIRequestBuilder.makeURLRequest(
                apiKey: "test-openai-key-not-a-real-secret",
                endpoint: "file:///tmp/responses",
                messages: []
            )
            throw CheckError.failed("OpenAI 访问地址必须拒绝本地文件协议")
        } catch OpenAIClientError.invalidEndpoint {
            // expected
        }
        pass("OpenAI Responses 请求与流式解析")
    }

    private static func checkOpenAICredentialFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wealth-openai-credential-check-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("openai-credentials.json")
        let store = OpenAICredentialFileStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let credential = OpenAICredential(
            apiKey: "test-openai-key-not-a-real-secret",
            endpoint: "https://gateway.example.com/v1/responses"
        )
        try store.save(credential)
        try expect(try OpenAICredentialFileStore(fileURL: fileURL).load() == credential, "OpenAI 访问地址与 Key 应成对从本地文件还原")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        try expect(permissions == 0o600, "OpenAI 本地配置文件权限必须为 0600")
        pass("OpenAI 地址与 Key 成对持久化")
    }

    @MainActor
    private static func checkCredentialsRestoreAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wealth-credential-relaunch-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let twelve = APIKeyFileStore(fileURL: directory.appendingPathComponent("twelve.txt"))
        let xai = APIKeyFileStore(filename: "xai.txt", fileURL: directory.appendingPathComponent("xai.txt"))
        let openAI = OpenAICredentialFileStore(fileURL: directory.appendingPathComponent("openai.json"))
        try twelve.save("test-twelve-key")
        try xai.save("test-xai-key")
        try openAI.save(OpenAICredential(apiKey: "test-openai-key", endpoint: "https://gateway.example.com/v1/responses"))

        let relaunched = AppStore(
            persistence: StaticPortfolioStore(value: PortfolioData()),
            apiKeyStore: twelve,
            spaceXAIKeyStore: xai,
            openAICredentialStore: openAI
        )
        try expect(relaunched.twelveDataKeyPresent, "Twelve Data Key 应在重新启动后自动恢复")
        try expect(relaunched.spaceXAIKeyPresent, "SpaceXAI Key 应在重新启动后自动恢复")
        try expect(relaunched.openAIKeyPresent, "OpenAI Key 应在重新启动后自动恢复")
        try expect(relaunched.openAIEndpoint == "https://gateway.example.com/v1/responses", "OpenAI 访问地址应在重新启动后自动恢复")
        pass("应用重启后自动恢复全部本地凭证")
    }

    private static func checkAssistantPlacementPersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wealth-assistant-placement-check-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("assistant-placement.json")
        let store = AssistantPlacementFileStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let placement = AssistantPlacement(x: -320, y: -140)
        try store.save(placement)
        try expect(try AssistantPlacementFileStore(fileURL: fileURL).load() == placement, "悬浮助手拖动位置应在重新启动后还原")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        try expect(permissions == 0o600, "悬浮助手位置文件权限必须为 0600")
        pass("悬浮助手位置持久化")
    }

    private static func checkAssistantResponseTableParsing() throws {
        let markdown = """
        ## 组合概览
        | 标的 | 权重 | 判断 |
        | --- | ---: | --- |
        | AAPL | 38% | 偏高 |
        | 腾讯 | 22% | 正常 |

        - 最大风险：集中度
        """
        let blocks = AssistantResponseParser.parse(markdown)
        try expect(blocks.contains(.heading("组合概览")), "回复标题应独立渲染")
        try expect(blocks.contains(.table(headers: ["标的", "权重", "判断"], rows: [["AAPL", "38%", "偏高"], ["腾讯", "22%", "正常"]])), "Markdown 表格应转换为结构化表格")
        try expect(blocks.contains(.bullets(["最大风险：集中度"])), "回复要点应独立渲染")
        pass("助手结构化表格解析")
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

private struct StaticNewsCacheStore: NewsCachePersisting {
    let snapshot: NewsCacheSnapshot?
    func load() throws -> NewsCacheSnapshot? { snapshot }
    func save(_ snapshot: NewsCacheSnapshot) throws {}
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
