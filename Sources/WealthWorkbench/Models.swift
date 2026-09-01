import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "今日总览"
    case holdings = "我的持仓"
    case news = "财经资讯"
    case review = "仓位复盘"
    case calendar = "事件日历"
    case settings = "通用设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .news: return "newspaper"
        case .review: return "chart.pie"
        case .holdings: return "briefcase"
        case .calendar: return "calendar"
        case .settings: return "gearshape"
        }
    }
}

enum Market: String, Codable, CaseIterable, Identifiable {
    case us = "美股"
    case hk = "港股"
    case cn = "A股"

    var id: String { rawValue }

    var defaultCurrency: CurrencyCode {
        switch self {
        case .us: return .usd
        case .hk: return .hkd
        case .cn: return .cny
        }
    }

    var timeZone: TimeZone {
        switch self {
        case .us: return TimeZone(identifier: "America/New_York")!
        case .hk: return TimeZone(identifier: "Asia/Hong_Kong")!
        case .cn: return TimeZone(identifier: "Asia/Shanghai")!
        }
    }

    func normalizedCode(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch self {
        case .us:
            return cleaned.replacingOccurrences(of: "US.", with: "")
        case .hk:
            let digits = cleaned.replacingOccurrences(of: "HK.", with: "")
            return digits.allSatisfy(\.isNumber) ? String(repeating: "0", count: max(0, 5 - digits.count)) + digits : digits
        case .cn:
            return cleaned
                .replacingOccurrences(of: "SH.", with: "")
                .replacingOccurrences(of: "SZ.", with: "")
        }
    }

    func tencentSymbol(_ raw: String) -> String {
        let code = normalizedCode(raw)
        switch self {
        case .us: return "us\(code)"
        case .hk: return "hk\(code)"
        case .cn: return (code.hasPrefix("6") || code.hasPrefix("9") ? "sh" : "sz") + code
        }
    }

    func futuSymbol(_ raw: String) -> String {
        let code = normalizedCode(raw)
        switch self {
        case .us: return "US.\(code)"
        case .hk: return "HK.\(code)"
        case .cn: return (code.hasPrefix("6") || code.hasPrefix("9") ? "SH." : "SZ.") + code
        }
    }
}

enum CurrencyCode: String, Codable, CaseIterable, Identifiable {
    case cny = "CNY"
    case usd = "USD"
    case hkd = "HKD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .usd: return "$"
        case .hkd: return "HK$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        }
    }
}

struct CashBalance: Codable, Identifiable, Equatable {
    var id = UUID()
    var currency: CurrencyCode
    var amount: Double
    var note: String = ""
}

struct Holding: Codable, Identifiable, Equatable {
    var id = UUID()
    var market: Market
    var name: String
    var code: String
    var sector: String
    var quantity: Double?
    var averageCost: Double
    var investedCost: Double?
    var currency: CurrencyCode
    var createdAt = Date()

    var normalizedCode: String { market.normalizedCode(code) }
    var quoteKey: String { "\(market.rawValue):\(normalizedCode)" }
    var isEstimated: Bool { quantity == nil }

    var effectiveQuantity: Double? {
        if let quantity, quantity > 0 { return quantity }
        guard let investedCost, investedCost > 0, averageCost > 0 else { return nil }
        return investedCost / averageCost
    }

    var costBasis: Double? {
        if let investedCost, investedCost > 0 { return investedCost }
        guard let quantity, quantity > 0, averageCost > 0 else { return nil }
        return quantity * averageCost
    }
}

struct PortfolioEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var title: String
    var note: String
    var category: String
}

enum MarketCalendarEventKind: String, Codable, CaseIterable {
    case economic = "宏观"
    case earnings = "财报"
}

struct MarketCalendarEvent: Identifiable, Equatable {
    var id: String
    var date: Date
    var hasExactTime: Bool
    var title: String
    var kind: MarketCalendarEventKind
    var country: String?
    var market: Market?
    var symbol: String?
    var importance: Int?
    var previous: String?
    var consensus: String?
    var actual: String?
    var detail: String?
    var source: String
    var fetchedAt: Date
}

struct MarketCalendarResult: Equatable {
    var events: [MarketCalendarEvent]
    var failures: [String]
    var serverDate: Date?
}

enum QuoteProvider: String, Codable, CaseIterable, Identifiable {
    case automatic = "自动（按优先级）"
    case futu = "Futu OpenD"
    case twelveData = "Twelve Data"
    case publicFallback = "腾讯公开备用行情"

    var id: String { rawValue }
}

enum AssistantProvider: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case spaceXAI = "SpaceXAI"

    var id: String { rawValue }

    var model: String {
        switch self {
        case .openAI: return "gpt-5.6-sol"
        case .spaceXAI: return "grok-4.6"
        }
    }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .spaceXAI: return "SpaceXAI"
        }
    }

    var keyLabel: String {
        switch self {
        case .openAI: return "OpenAI API Key"
        case .spaceXAI: return "xAI API Key"
        }
    }

    var environmentVariable: String {
        switch self {
        case .openAI: return "OPENAI_API_KEY"
        case .spaceXAI: return "XAI_API_KEY"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var baseCurrency: CurrencyCode = .cny
    var provider: QuoteProvider = .automatic
    var futuHost: String = "127.0.0.1"
    var futuPort: Int = 11111
    var allowPublicFallback: Bool = true
    var refreshIntervalSeconds: Int = 60
    var assistantProvider: AssistantProvider = .openAI

    init(
        baseCurrency: CurrencyCode = .cny,
        provider: QuoteProvider = .automatic,
        futuHost: String = "127.0.0.1",
        futuPort: Int = 11111,
        allowPublicFallback: Bool = true,
        refreshIntervalSeconds: Int = 60,
        assistantProvider: AssistantProvider = .openAI
    ) {
        self.baseCurrency = baseCurrency
        self.provider = provider
        self.futuHost = futuHost
        self.futuPort = futuPort
        self.allowPublicFallback = allowPublicFallback
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.assistantProvider = assistantProvider
    }

    private enum CodingKeys: String, CodingKey {
        case baseCurrency
        case provider
        case futuHost
        case futuPort
        case allowPublicFallback
        case refreshIntervalSeconds
        case assistantProvider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseCurrency = try container.decodeIfPresent(CurrencyCode.self, forKey: .baseCurrency) ?? .cny
        provider = try container.decodeIfPresent(QuoteProvider.self, forKey: .provider) ?? .automatic
        futuHost = try container.decodeIfPresent(String.self, forKey: .futuHost) ?? "127.0.0.1"
        futuPort = try container.decodeIfPresent(Int.self, forKey: .futuPort) ?? 11111
        allowPublicFallback = try container.decodeIfPresent(Bool.self, forKey: .allowPublicFallback) ?? true
        refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 60
        // Before provider selection existed, AUREL only supported SpaceXAI.
        assistantProvider = try container.decodeIfPresent(AssistantProvider.self, forKey: .assistantProvider) ?? .spaceXAI
    }
}

struct PortfolioData: Codable, Equatable {
    var schemaVersion = 1
    var cash: [CashBalance] = []
    var holdings: [Holding] = []
    var events: [PortfolioEvent] = []
    var settings = AppSettings()
}

enum TradingSession: String, Codable {
    case preMarket = "盘前"
    case regular = "常规交易"
    case middayBreak = "午间休市"
    case afterHours = "盘后"
    case overnight = "夜盘"
    case todayClose = "今日收盘"
    case recentClose = "最近收盘"
    case waiting = "等待开市"
    case closed = "休市"
    case unavailable = "暂无数据"
}

enum PriceType: String, Codable {
    case preMarket = "盘前价"
    case regular = "盘中价"
    case afterHours = "盘后价"
    case overnight = "夜盘价"
    case todayClose = "今日收盘价"
    case recentClose = "最近收盘价"
    case unavailable = "暂无数据"
}

enum DelayStatus: String, Codable {
    case realtime = "实时"
    case possiblyDelayed = "可能延迟"
    case entitlementDependent = "以行情权限为准"
    case unavailable = "不可用"
}

struct PricePassport: Codable, Equatable {
    var market: Market
    var currency: CurrencyCode
    var priceType: PriceType
    var session: TradingSession
    var comparisonBasis: String
    var quoteTime: Date
    var fetchedAt: Date
    var source: String
    var delayStatus: DelayStatus
    var marketTimeZoneIdentifier: String
}

struct QuoteSnapshot: Codable, Identifiable, Equatable {
    var id: String { key }
    var key: String
    var code: String
    var name: String
    var price: Double
    var previousClose: Double
    var change: Double
    var percentChange: Double
    var passport: PricePassport

    var isValid: Bool {
        price.isFinite && price > 0 && previousClose.isFinite && previousClose > 0
    }
}

struct QuoteFailure: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var message: String
    var source: String
    var fetchedAt: Date
}

struct Benchmark: Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var market: Market
    var code: String
    var currency: CurrencyCode
    var tencentSymbol: String

    static let defaults: [Benchmark] = [
        .init(key: "指数:SP500", name: "标普 500", market: .us, code: ".INX", currency: .usd, tencentSymbol: "usINX"),
        .init(key: "指数:NASDAQ", name: "纳斯达克", market: .us, code: ".IXIC", currency: .usd, tencentSymbol: "usIXIC"),
        .init(key: "指数:HSTECH", name: "恒生科技", market: .hk, code: "HSTECH", currency: .hkd, tencentSymbol: "hkHSTECH"),
        .init(key: "指数:SSE", name: "上证指数", market: .cn, code: "000001", currency: .cny, tencentSymbol: "sh000001")
    ]
}

struct HoldingMetrics: Identifiable {
    var id: UUID { holding.id }
    var holding: Holding
    var quote: QuoteSnapshot?
    var marketValue: Double?
    var dailyProfit: Double?
    var totalProfit: Double?
    var totalReturn: Double?
    var weight: Double?
}

struct HoldingsSummary {
    var marketValue: Double?
    var dailyProfit: Double?
    var totalProfit: Double?
    var totalReturn: Double?
    var currency: CurrencyCode
    var positionCount: Int
    var estimatedCount: Int
    var missingQuoteCount: Int
    var isPartial: Bool
}

struct PortfolioSummary {
    var totalAssets: Double?
    var securitiesAssets: Double?
    var cashAssets: Double?
    var dailyProfit: Double?
    var totalProfit: Double?
    var totalReturn: Double?
    var currency: CurrencyCode
    var isPartial: Bool
}

struct TimeHealth: Equatable {
    var serverDate: Date?
    var offset: TimeInterval = 0
    var checkedAt: Date?

    var isSkewed: Bool { abs(offset) >= 60 }
    var correctedNow: Date { Date().addingTimeInterval(offset) }
}

extension Double {
    var finiteOrNil: Double? { isFinite ? self : nil }
}
