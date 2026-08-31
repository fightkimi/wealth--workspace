import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    let navigateToHoldings: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    private let benchmarkColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkbenchLayout.sectionSpacing) {
                header
                if store.timeHealth.isSkewed { timeWarning }
                metricGrid
                benchmarkSection
                portfolioPulse
            }
            .padding(WorkbenchLayout.pagePadding)
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            SectionHeader(
                eyebrow: "TODAY · PORTFOLIO SNAPSHOT",
                title: "今日总览",
                detail: DisplayFormat.shortDate(store.timeHealth.correctedNow)
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 8) {
                    StatusPill(
                        text: store.isRefreshing ? "正在刷新" : store.providerStatus,
                        tint: store.isRefreshing ? WorkbenchTheme.warning : WorkbenchTheme.negative
                    )
                }
                if let last = store.lastRefreshAt {
                    Text("最近抓取 · \(DisplayFormat.dateTime(last))")
                        .font(.custom("PingFangSC-Regular", size: 10))
                        .foregroundStyle(WorkbenchTheme.muted)
                }
            }
        }
    }

    private var timeWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
            Text("检测到电脑时间偏差 \(Int(abs(store.timeHealth.offset))) 秒。界面已采用网络时间校正，系统时间本身未被修改。")
            Spacer()
        }
        .font(.custom("PingFangSC-Medium", size: 12))
        .foregroundStyle(WorkbenchTheme.warning)
        .padding(11)
        .background(WorkbenchTheme.warning.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous))
    }

    private var metricGrid: some View {
        let summary = store.summary()
        return LazyVGrid(columns: columns, spacing: 10) {
            MetricCard(label: "总资产", value: DisplayFormat.money(summary.totalAssets, currency: summary.currency, compact: true), note: summary.isPartial ? "行情或汇率不完整" : "按 \(summary.currency.rawValue) 折算", emphasis: true)
            MetricCard(label: "证券资产", value: DisplayFormat.money(summary.securitiesAssets, currency: summary.currency, compact: true), note: "按有效持仓数量计算")
            MetricCard(label: "现金", value: DisplayFormat.money(summary.cashAssets, currency: summary.currency, compact: true), note: store.exchangeRates.map { "ECB 参考汇率 \(DisplayFormat.shortDate($0.date))" } ?? "同币种直接计入")
            MetricCard(label: "当日盈亏", value: DisplayFormat.money(summary.dailyProfit, currency: summary.currency, compact: true), note: "对比上一常规收盘", change: summary.dailyProfit)
            MetricCard(label: "总盈亏", value: DisplayFormat.money(summary.totalProfit, currency: summary.currency, compact: true), note: "市值减投入成本", change: summary.totalProfit)
            MetricCard(label: "收益率", value: DisplayFormat.percent(summary.totalReturn), note: "不含现金", change: summary.totalReturn)
        }
    }

    private var benchmarkSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(eyebrow: "MARKET PULSE", title: "全球市场", detail: "红涨 · 绿跌")
            LazyVGrid(columns: benchmarkColumns, spacing: 10) {
                ForEach(Benchmark.defaults) { benchmark in
                    BenchmarkCard(benchmark: benchmark, quote: store.quotes[benchmark.key], failure: store.quoteFailures[benchmark.key])
                }
            }
        }
    }

    private var portfolioPulse: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(eyebrow: "PORTFOLIO", title: "持仓脉搏", detail: "\(store.data.holdings.count) 个标的")
            if store.data.holdings.isEmpty {
                EmptyState(
                    icon: "tray",
                    title: "尚未录入持仓",
                    message: "当前是空账户，不包含任何示例资产。录入数量后才能计算精确市值；仅录入投入成本时会明确标为“估算持仓”。",
                    actionTitle: "录入第一笔持仓",
                    action: navigateToHoldings
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.holdingMetrics().prefix(5).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 7) {
                                    Text(item.holding.name)
                                        .foregroundStyle(WorkbenchTheme.text)
                                    if item.holding.isEstimated { StatusPill(text: "估算持仓", tint: WorkbenchTheme.warning) }
                                }
                                Text("\(item.holding.market.rawValue) · \(item.holding.normalizedCode) · \(item.holding.sector)")
                                    .font(.custom("PingFangSC-Regular", size: 11))
                                    .foregroundStyle(WorkbenchTheme.muted)
                            }
                            Spacer()
                            Text(DisplayFormat.money(item.marketValue, currency: item.holding.currency))
                                .foregroundStyle(WorkbenchTheme.text)
                                .monospacedDigit()
                            ChangeText(value: item.dailyProfit, text: DisplayFormat.money(item.dailyProfit, currency: item.holding.currency))
                                .frame(width: 120, alignment: .trailing)
                        }
                        .font(.custom("PingFangSC-Medium", size: 13))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        if index < min(store.data.holdings.count, 5) - 1 { Divider().overlay(WorkbenchTheme.border) }
                    }
                }
                .workbenchCard()
            }
        }
    }
}

private struct MetricCard: View {
    let label: String
    let value: String
    let note: String
    var emphasis = false
    var change: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.custom("PingFangSC-Medium", size: 12))
                    .foregroundStyle(WorkbenchTheme.secondary)
                Spacer()
                if emphasis {
                    Image(systemName: "sparkles")
                        .foregroundStyle(WorkbenchTheme.accent)
                }
            }
            if change != nil {
                ChangeText(value: change, text: value)
                    .font(.custom("PingFangSC-Semibold", size: 20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(value)
                    .font(.custom("PingFangSC-Semibold", size: 20))
                    .foregroundStyle(emphasis ? WorkbenchTheme.accent : WorkbenchTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(note)
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundStyle(WorkbenchTheme.muted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .workbenchCard()
    }
}

private struct BenchmarkCard: View {
    let benchmark: Benchmark
    let quote: QuoteSnapshot?
    let failure: QuoteFailure?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(benchmark.name)
                        .font(.custom("PingFangSC-Semibold", size: 16).weight(.semibold))
                        .foregroundStyle(WorkbenchTheme.text)
                    Text(benchmark.code)
                        .font(.custom("PingFangSC-Regular", size: 10))
                        .foregroundStyle(WorkbenchTheme.muted)
                }
                Spacer()
                if let quote {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(DisplayFormat.number(quote.price))
                            .font(.custom("PingFangSC-Semibold", size: 19))
                            .foregroundStyle(WorkbenchTheme.text)
                            .monospacedDigit()
                        ChangeText(value: quote.percentChange, text: DisplayFormat.percent(quote.percentChange))
                            .font(.custom("PingFangSC-Semibold", size: 12))
                    }
                } else {
                    Text("暂无数据")
                        .foregroundStyle(WorkbenchTheme.muted)
                }
            }
            if let quote {
                PricePassportView(quote: quote)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(failure?.message ?? "行情尚未抓取")
                }
                .font(.custom("PingFangSC-Regular", size: 11))
                .foregroundStyle(WorkbenchTheme.warning)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workbenchCard()
    }
}
