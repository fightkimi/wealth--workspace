import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var data: PortfolioData
    @Published var quotes: [String: QuoteSnapshot] = [:]
    @Published var quoteFailures: [String: QuoteFailure] = [:]
    @Published var exchangeRates: ExchangeRateSnapshot?
    @Published var timeHealth = TimeHealth()
    @Published var isRefreshing = false
    @Published var lastRefreshAt: Date?
    @Published var providerStatus = "等待首次刷新"
    @Published var providerAdvisory: String?
    @Published var notice: String?
    @Published var twelveDataKeyPresent = false
    @Published var marketCalendarEvents: [MarketCalendarEvent] = []
    @Published var marketCalendarFailures: [String] = []
    @Published var isRefreshingCalendar = false
    @Published var marketCalendarUpdatedAt: Date?

    private let persistence: PortfolioPersisting
    private let apiKeyStore: APIKeyPersisting
    private var twelveDataAPIKey: String?
    private let tencent: TencentQuoteService
    private let twelve: TwelveDataQuoteService
    private let futu: FutuQuoteService
    private let exchangeRateService: ExchangeRateService

    init(
        persistence: PortfolioPersisting = PortfolioFileStore(),
        apiKeyStore: APIKeyPersisting = APIKeyFileStore(),
        tencent: TencentQuoteService = TencentQuoteService(),
        twelve: TwelveDataQuoteService = TwelveDataQuoteService(),
        futu: FutuQuoteService = FutuQuoteService(),
        exchangeRateService: ExchangeRateService = ExchangeRateService()
    ) {
        self.persistence = persistence
        self.apiKeyStore = apiKeyStore
        self.tencent = tencent
        self.twelve = twelve
        self.futu = futu
        self.exchangeRateService = exchangeRateService
        do {
            self.data = try persistence.load()
        } catch {
            self.data = PortfolioData()
            self.notice = "本地资产数据读取失败：\(error.localizedDescription)"
        }
        do {
            self.twelveDataAPIKey = try apiKeyStore.load()
            self.twelveDataKeyPresent = self.twelveDataAPIKey?.isEmpty == false
        } catch {
            self.notice = "本地 API Key 文件读取失败：\(error.localizedDescription)"
        }
    }

    var dataFilePath: String { persistence.displayPath }
    var apiKeyFilePath: String { apiKeyStore.displayPath }
    var futuBridgeInstalled: Bool { futu.isBridgeInstalled }

    func persist() {
        do {
            try persistence.save(data)
        } catch {
            notice = "保存失败：\(error.localizedDescription)"
        }
    }

    func addHolding(_ holding: Holding) {
        data.holdings.append(holding)
        persist()
        Task { await refreshQuotes() }
    }

    func updateHolding(_ holding: Holding) {
        guard let index = data.holdings.firstIndex(where: { $0.id == holding.id }) else { return }
        let oldKey = data.holdings[index].quoteKey
        data.holdings[index] = holding
        quotes.removeValue(forKey: oldKey)
        persist()
        Task { await refreshQuotes() }
    }

    func deleteHolding(_ holding: Holding) {
        data.holdings.removeAll { $0.id == holding.id }
        quotes.removeValue(forKey: holding.quoteKey)
        quoteFailures.removeValue(forKey: holding.quoteKey)
        persist()
    }

    func addCash(_ balance: CashBalance) {
        data.cash.append(balance)
        persist()
    }

    func deleteCash(_ balance: CashBalance) {
        data.cash.removeAll { $0.id == balance.id }
        persist()
    }

    func addEvent(_ event: PortfolioEvent) {
        data.events.append(event)
        data.events.sort { $0.date < $1.date }
        persist()
    }

    func deleteEvent(_ event: PortfolioEvent) {
        data.events.removeAll { $0.id == event.id }
        persist()
    }

    func refreshMarketCalendar() async {
        guard !isRefreshingCalendar else { return }
        isRefreshingCalendar = true
        defer { isRefreshingCalendar = false }
        marketCalendarFailures = []

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: timeHealth.correctedNow)
        guard let end = calendar.date(byAdding: .day, value: 6, to: start) else { return }
        do {
            let result = try await futu.fetchCalendar(
                holdings: data.holdings,
                host: data.settings.futuHost,
                port: data.settings.futuPort,
                beginDate: start,
                endDate: end
            )
            marketCalendarEvents = result.events.filter { event in
                event.kind == .earnings || (event.importance ?? 0) >= 2
            }
            marketCalendarFailures = result.failures
            marketCalendarUpdatedAt = Date()
            applyNetworkTime(result.serverDate)
        } catch {
            marketCalendarEvents = []
            marketCalendarFailures = [error.localizedDescription]
            marketCalendarUpdatedAt = Date()
        }
    }

    func saveSettings(_ settings: AppSettings) {
        let baseChanged = data.settings.baseCurrency != settings.baseCurrency
        data.settings = settings
        persist()
        if baseChanged { exchangeRates = nil }
        Task { await refreshQuotes() }
    }

    func saveTwelveDataKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try apiKeyStore.delete()
                twelveDataAPIKey = nil
                twelveDataKeyPresent = false
                notice = "Twelve Data API Key 已从本地文件移除"
            } else {
                try apiKeyStore.save(trimmed)
                twelveDataAPIKey = trimmed
                twelveDataKeyPresent = true
                notice = "Twelve Data API Key 已保存到应用专属本地文件"
            }
        } catch {
            notice = "API Key 本地保存失败：\(error.localizedDescription)"
        }
    }

    func refreshQuotes() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        quotes = [:]
        quoteFailures = [:]
        providerStatus = "正在校验行情…"
        providerAdvisory = nil

        async let fxTask: Void = refreshExchangeRates()
        let holdingInstruments = data.holdings.map(QuoteInstrument.init)
        let benchmarkInstruments = Benchmark.defaults.map(QuoteInstrument.init)
        var providerResult: QuoteBatchResult?
        var providerErrors: [String] = []

        if holdingInstruments.isEmpty {
            providerStatus = "空账户 · 未请求持仓行情"
        } else {
        switch data.settings.provider {
        case .futu:
            do {
                providerResult = try await futu.fetch(
                    holdingInstruments,
                    host: data.settings.futuHost,
                    port: data.settings.futuPort,
                    now: timeHealth.correctedNow
                )
            } catch {
                providerErrors.append("Futu：\(error.localizedDescription)")
            }
        case .twelveData:
            if let key = twelveDataAPIKey, !key.isEmpty {
                providerResult = await twelve.fetch(holdingInstruments, apiKey: key, now: timeHealth.correctedNow)
            } else {
                providerErrors.append("Twelve Data：未配置 API Key")
            }
        case .publicFallback:
            do {
                providerResult = try await tencent.fetch(holdingInstruments, now: timeHealth.correctedNow)
            } catch {
                providerErrors.append("公开行情：\(error.localizedDescription)")
            }
        case .automatic:
            if futu.isBridgeInstalled {
                do {
                    providerResult = try await futu.fetch(
                        holdingInstruments,
                        host: data.settings.futuHost,
                        port: data.settings.futuPort,
                        now: timeHealth.correctedNow
                    )
                } catch {
                    providerErrors.append("Futu 未连接")
                }
            }
            if providerResult == nil,
               let key = twelveDataAPIKey,
               !key.isEmpty {
                let result = await twelve.fetch(holdingInstruments, apiKey: key, now: timeHealth.correctedNow)
                if !result.quotes.isEmpty || holdingInstruments.isEmpty {
                    providerResult = result
                } else {
                    providerErrors.append("Twelve Data 未返回有效行情")
                }
            }
            if providerResult == nil, data.settings.allowPublicFallback {
                do {
                    providerResult = try await tencent.fetch(holdingInstruments, now: timeHealth.correctedNow)
                } catch {
                    providerErrors.append("公开行情不可用")
                }
            }
        }
        }

        if let providerResult {
            quotes.merge(providerResult.quotes) { _, new in new }
            quoteFailures.merge(providerResult.failures) { _, new in new }
            applyNetworkTime(providerResult.serverDate)
            providerStatus = providerResult.source
        } else if !holdingInstruments.isEmpty {
            let now = Date()
            for item in holdingInstruments {
                quoteFailures[item.key] = QuoteFailure(
                    key: item.key,
                    message: providerErrors.joined(separator: "；").nonEmpty ?? "所有已配置行情源均不可用",
                    source: "暂无数据",
                    fetchedAt: now
                )
            }
            providerStatus = "暂无可用持仓行情"
        }

        do {
            let benchmarks = try await tencent.fetch(benchmarkInstruments, now: timeHealth.correctedNow)
            quotes.merge(benchmarks.quotes) { _, new in new }
            quoteFailures.merge(benchmarks.failures) { _, new in new }
            applyNetworkTime(benchmarks.serverDate)
        } catch {
            let now = Date()
            for item in benchmarkInstruments {
                quoteFailures[item.key] = QuoteFailure(key: item.key, message: error.localizedDescription, source: "腾讯公开备用行情", fetchedAt: now)
            }
        }

        await fxTask
        lastRefreshAt = Date()
        if !providerErrors.isEmpty && data.settings.provider == .automatic {
            let detail = providerErrors.joined(separator: "；")
            if providerResult == nil {
                providerAdvisory = "自动行情链路暂不可用：\(detail)"
            } else {
                providerAdvisory = "已切换至\(providerStatus)：\(detail)"
            }
        }
    }

    private func refreshExchangeRates() async {
        do {
            let (snapshot, serverDate) = try await exchangeRateService.fetch(base: data.settings.baseCurrency)
            exchangeRates = snapshot
            applyNetworkTime(serverDate)
        } catch {
            exchangeRates = nil
        }
    }

    private func applyNetworkTime(_ serverDate: Date?) {
        guard let serverDate else { return }
        let offset = serverDate.timeIntervalSince(Date())
        timeHealth = TimeHealth(serverDate: serverDate, offset: offset, checkedAt: Date())
    }

    func holdingMetrics() -> [HoldingMetrics] {
        var values: [HoldingMetrics] = data.holdings.map { holding in
            let quote = quotes[holding.quoteKey]
            let quantity = holding.effectiveQuantity
            let marketValue = quantity.flatMap { quantity in quote.map { quantity * $0.price } }
            let daily = quantity.flatMap { quantity in quote.map { quantity * ($0.price - $0.previousClose) } }
            let total = marketValue.flatMap { marketValue in holding.costBasis.map { marketValue - $0 } }
            let totalReturn = total.flatMap { total in holding.costBasis.flatMap { $0 > 0 ? total / $0 * 100 : nil } }
            return HoldingMetrics(
                holding: holding,
                quote: quote,
                marketValue: marketValue,
                dailyProfit: daily,
                totalProfit: total,
                totalReturn: totalReturn,
                weight: nil
            )
        }
        let converted = values.compactMap { item -> Double? in
            guard let value = item.marketValue else { return nil }
            return convert(value, from: item.holding.currency)
        }
        let total = converted.reduce(0, +)
        for index in values.indices {
            if let value = values[index].marketValue,
               let baseValue = convert(value, from: values[index].holding.currency), total > 0 {
                values[index].weight = baseValue / total * 100
            }
        }
        return values
    }

    func holdingsSummary(for market: Market? = nil) -> HoldingsSummary {
        let metrics = holdingMetrics().filter { market == nil || $0.holding.market == market }
        guard !metrics.isEmpty else {
            return HoldingsSummary(
                marketValue: 0,
                dailyProfit: 0,
                totalProfit: 0,
                totalReturn: 0,
                currency: data.settings.baseCurrency,
                positionCount: 0,
                estimatedCount: 0,
                missingQuoteCount: 0,
                isPartial: false
            )
        }

        var marketValues: [Double] = []
        var dailyValues: [Double] = []
        var profitValues: [Double] = []
        var costValues: [Double] = []
        var partial = false

        for item in metrics {
            if let value = item.marketValue,
               let converted = convert(value, from: item.holding.currency) {
                marketValues.append(converted)
            } else { partial = true }

            if let value = item.dailyProfit,
               let converted = convert(value, from: item.holding.currency) {
                dailyValues.append(converted)
            } else { partial = true }

            if let value = item.totalProfit,
               let converted = convert(value, from: item.holding.currency) {
                profitValues.append(converted)
            } else { partial = true }

            if let value = item.holding.costBasis,
               let converted = convert(value, from: item.holding.currency) {
                costValues.append(converted)
            } else { partial = true }
        }

        let count = metrics.count
        let marketValue = marketValues.count == count ? marketValues.reduce(0, +) : nil
        let dailyProfit = dailyValues.count == count ? dailyValues.reduce(0, +) : nil
        let totalProfit = profitValues.count == count ? profitValues.reduce(0, +) : nil
        let totalCost = costValues.count == count ? costValues.reduce(0, +) : nil
        let totalReturn = totalProfit.flatMap { profit in
            totalCost.flatMap { cost in cost > 0 ? profit / cost * 100 : nil }
        }

        return HoldingsSummary(
            marketValue: marketValue,
            dailyProfit: dailyProfit,
            totalProfit: totalProfit,
            totalReturn: totalReturn,
            currency: data.settings.baseCurrency,
            positionCount: count,
            estimatedCount: metrics.filter { $0.holding.isEstimated }.count,
            missingQuoteCount: metrics.filter { $0.quote == nil }.count,
            isPartial: partial
        )
    }

    func summary() -> PortfolioSummary {
        let metrics = holdingMetrics()
        var partial = false
        var securityValues: [Double] = []
        var dailyValues: [Double] = []
        var profitValues: [Double] = []
        var costValues: [Double] = []

        for item in metrics {
            guard let marketValue = item.marketValue,
                  let convertedValue = convert(marketValue, from: item.holding.currency) else {
                partial = true
                continue
            }
            securityValues.append(convertedValue)
            if let daily = item.dailyProfit, let converted = convert(daily, from: item.holding.currency) {
                dailyValues.append(converted)
            } else { partial = true }
            if let profit = item.totalProfit, let converted = convert(profit, from: item.holding.currency) {
                profitValues.append(converted)
            } else { partial = true }
            if let cost = item.holding.costBasis, let converted = convert(cost, from: item.holding.currency) {
                costValues.append(converted)
            }
        }

        var cashValues: [Double] = []
        for cash in data.cash {
            if let converted = convert(cash.amount, from: cash.currency) {
                cashValues.append(converted)
            } else {
                partial = true
            }
        }

        let securities: Double? = data.holdings.isEmpty ? 0 : (securityValues.count == data.holdings.count ? securityValues.reduce(0, +) : nil)
        let cash: Double? = data.cash.isEmpty ? 0 : (cashValues.count == data.cash.count ? cashValues.reduce(0, +) : nil)
        let total = securities.flatMap { securities in cash.map { securities + $0 } }
        let daily: Double? = data.holdings.isEmpty ? 0 : (dailyValues.count == data.holdings.count ? dailyValues.reduce(0, +) : nil)
        let profit: Double? = data.holdings.isEmpty ? 0 : (profitValues.count == data.holdings.count ? profitValues.reduce(0, +) : nil)
        let totalCost = costValues.reduce(0, +)
        let totalReturn = profit.flatMap { totalCost > 0 ? $0 / totalCost * 100 : (data.holdings.isEmpty ? 0 : nil) }

        return PortfolioSummary(
            totalAssets: total,
            securitiesAssets: securities,
            cashAssets: cash,
            dailyProfit: daily,
            totalProfit: profit,
            totalReturn: totalReturn,
            currency: data.settings.baseCurrency,
            isPartial: partial
        )
    }

    private func convert(_ amount: Double, from currency: CurrencyCode) -> Double? {
        if currency == data.settings.baseCurrency { return amount }
        return exchangeRates?.convert(amount, from: currency)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
