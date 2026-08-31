import SwiftUI
import AppKit

struct PortfolioReviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkbenchLayout.sectionSpacing) {
                SectionHeader(eyebrow: "RISK & ALLOCATION", title: "仓位复盘", detail: "用真实持仓与可用行情计算")
                if store.data.holdings.isEmpty {
                    EmptyState(icon: "chart.pie", title: "暂无可复盘的仓位", message: "录入持仓后，这里会展示集中度、板块暴露、盈亏分布和数据质量。")
                } else {
                    qualityStrip
                    HStack(alignment: .top, spacing: 14) {
                        allocationCard
                        concentrationCard
                    }
                    profitCard
                }
            }
            .padding(WorkbenchLayout.pagePadding)
        }
        .background(Color.clear)
    }

    private var qualityStrip: some View {
        let metrics = store.holdingMetrics()
        let quoted = metrics.filter { $0.quote != nil }.count
        let estimated = metrics.filter { $0.holding.isEstimated }.count
        let weighted = metrics.filter { $0.weight != nil }.count
        return HStack(spacing: 0) {
            ReviewStat(label: "行情覆盖", value: "\(quoted)/\(metrics.count)", tint: quoted == metrics.count ? WorkbenchTheme.negative : WorkbenchTheme.warning)
            Divider().frame(height: 42).overlay(WorkbenchTheme.border)
            ReviewStat(label: "估算持仓", value: "\(estimated)", tint: estimated == 0 ? WorkbenchTheme.negative : WorkbenchTheme.warning)
            Divider().frame(height: 42).overlay(WorkbenchTheme.border)
            ReviewStat(label: "可换算权重", value: "\(weighted)/\(metrics.count)", tint: weighted == metrics.count ? WorkbenchTheme.negative : WorkbenchTheme.warning)
            Divider().frame(height: 42).overlay(WorkbenchTheme.border)
            ReviewStat(label: "基准币种", value: store.data.settings.baseCurrency.rawValue, tint: WorkbenchTheme.accent)
        }
        .padding(.vertical, 14)
        .workbenchCard()
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("板块配置")
                .font(.custom("PingFangSC-Semibold", size: 19).weight(.semibold))
                .foregroundStyle(WorkbenchTheme.text)
            let allocations = sectorAllocations
            if allocations.isEmpty {
                Text("行情或汇率不足，暂不能计算板块权重")
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundStyle(WorkbenchTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(allocations, id: \.name) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name)
                                .foregroundStyle(WorkbenchTheme.secondary)
                            Spacer()
                            Text(DisplayFormat.percent(item.value, signed: false))
                                .foregroundStyle(WorkbenchTheme.text)
                                .monospacedDigit()
                        }
                        .font(.custom("PingFangSC-Medium", size: 12))
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(WorkbenchTheme.raised)
                                Capsule().fill(item.color).frame(width: geometry.size.width * min(item.value / 100, 1))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .workbenchCard()
    }

    private var concentrationCard: some View {
        let metrics = store.holdingMetrics().sorted { ($0.weight ?? -1) > ($1.weight ?? -1) }
        return VStack(alignment: .leading, spacing: 16) {
            Text("集中度观察")
                .font(.custom("PingFangSC-Semibold", size: 19).weight(.semibold))
                .foregroundStyle(WorkbenchTheme.text)
            if metrics.allSatisfy({ $0.weight == nil }) {
                Text("行情或汇率不足，暂不能计算集中度")
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundStyle(WorkbenchTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(Array(metrics.prefix(5).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 11) {
                        Text(String(format: "%02d", index + 1))
                            .font(.custom("PingFangSC-Semibold", size: 10))
                            .foregroundStyle(WorkbenchTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.holding.name)
                                .foregroundStyle(WorkbenchTheme.text)
                            Text(item.holding.sector.isEmpty ? "未分类" : item.holding.sector)
                                .font(.custom("PingFangSC-Regular", size: 10))
                                .foregroundStyle(WorkbenchTheme.muted)
                        }
                        Spacer()
                        Text(DisplayFormat.percent(item.weight, signed: false))
                            .foregroundStyle((item.weight ?? 0) >= 30 ? WorkbenchTheme.warning : WorkbenchTheme.secondary)
                            .monospacedDigit()
                    }
                    .font(.custom("PingFangSC-Medium", size: 12))
                }
                let topThree = metrics.prefix(3).compactMap(\.weight).reduce(0, +)
                HStack {
                    Text("前三大持仓")
                    Spacer()
                    Text(DisplayFormat.percent(topThree, signed: false))
                }
                .font(.custom("PingFangSC-Semibold", size: 12))
                .foregroundStyle(topThree >= 60 ? WorkbenchTheme.warning : WorkbenchTheme.secondary)
                .padding(.top, 5)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .workbenchCard()
    }

    private var profitCard: some View {
        let metrics = store.holdingMetrics().sorted { ($0.totalReturn ?? -.infinity) > ($1.totalReturn ?? -.infinity) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("收益分布")
                    .font(.custom("PingFangSC-Semibold", size: 19).weight(.semibold))
                    .foregroundStyle(WorkbenchTheme.text)
                Spacer()
                Text("按单标的总收益率")
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(WorkbenchTheme.muted)
            }
            ForEach(metrics) { item in
                HStack(spacing: 12) {
                    Text(item.holding.name)
                        .font(.custom("PingFangSC-Medium", size: 12))
                        .foregroundStyle(WorkbenchTheme.secondary)
                        .frame(width: 150, alignment: .leading)
                    GeometryReader { geometry in
                        let value = item.totalReturn ?? 0
                        ZStack {
                            Rectangle().fill(WorkbenchTheme.border).frame(height: 1)
                            HStack(spacing: 0) {
                                if value < 0 {
                                    Spacer(minLength: 0)
                                    Rectangle().fill(WorkbenchTheme.negative).frame(width: min(abs(value) / 100, 1) * geometry.size.width / 2, height: 7)
                                } else {
                                    Color.clear.frame(width: geometry.size.width / 2)
                                    Rectangle().fill(WorkbenchTheme.positive).frame(width: min(value / 100, 1) * geometry.size.width / 2, height: 7)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(height: 10)
                    ChangeText(value: item.totalReturn, text: DisplayFormat.percent(item.totalReturn))
                        .font(.custom("PingFangSC-Semibold", size: 11))
                        .frame(width: 78, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .workbenchCard()
    }

    private var sectorAllocations: [(name: String, value: Double, color: Color)] {
        let palette = [WorkbenchTheme.accent, Color(hex: 0x5F9D7C), Color(hex: 0xB7794D), Color(hex: 0x5F86A8), Color(hex: 0x9B6258)]
        var values: [String: Double] = [:]
        for item in store.holdingMetrics() {
            guard let weight = item.weight else { continue }
            values[item.holding.sector.isEmpty ? "未分类" : item.holding.sector, default: 0] += weight
        }
        return values.sorted { $0.value > $1.value }.enumerated().map { index, item in
            (item.key, item.value, palette[index % palette.count])
        }
    }
}

private struct ReviewStat: View {
    let label: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("PingFangSC-Semibold", size: 18))
                .foregroundStyle(tint)
            Text(label)
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundStyle(WorkbenchTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FinancialNewsView: View {
    @ObservedObject var news: NewsStore
    @State private var selectedArticle: NewsItem?

    var body: some View {
        Group {
            if let selectedArticle {
                NewsReaderView(item: selectedArticle) {
                    self.selectedArticle = nil
                }
                .id(selectedArticle.id)
            } else {
                newsFeed
            }
        }
        .background(Color.clear)
        .task { if news.items.isEmpty { await news.refresh() } }
    }

    private var newsFeed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkbenchLayout.sectionSpacing) {
                HStack(alignment: .top, spacing: 20) {
                    SectionHeader(
                        eyebrow: "MARKET INTELLIGENCE",
                        title: "财经资讯",
                        detail: news.isShowingCachedData ? "已先展示本地缓存，后台更新后自动替换" : "资讯已预载，可在应用内直接阅读"
                    )
                    Spacer()
                    if news.isShowingCachedData, let cachedAt = news.cacheTimestamp {
                        StatusPill(text: "缓存 · \(Self.cacheFormatter.string(from: cachedAt))", tint: WorkbenchTheme.warning)
                    }
                    Button { Task { await news.refresh() } } label: {
                        Label(news.isLoading ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                    }
                    .workbenchActionButton(.secondary)
                    .disabled(news.isLoading)
                }
                if let advisory = news.advisoryMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(WorkbenchTheme.warning)
                        Text(advisory)
                            .font(.custom("PingFangSC-Regular", size: 10))
                            .foregroundStyle(WorkbenchTheme.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(WorkbenchTheme.warning.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius).stroke(WorkbenchTheme.warning.opacity(0.18)))
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius))
                }
                if news.isLoading && news.items.isEmpty {
                    NewsLoadingState()
                } else if let message = news.errorMessage {
                    EmptyState(icon: "newspaper", title: "暂无资讯", message: message)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if let lead = news.items.first {
                            NewsStoryCard(item: lead, prominence: .lead) {
                                selectedArticle = lead
                            }
                        }
                        VStack(spacing: 0) {
                            NewsLedgerHeader()
                            ForEach(Array(news.items.dropFirst().enumerated()), id: \.element.id) { index, item in
                                NewsStoryCard(item: item, prominence: .standard) {
                                    selectedArticle = item
                                }
                                if index < news.items.dropFirst().count - 1 {
                                    Divider().overlay(WorkbenchTheme.border)
                                }
                            }
                        }
                        .workbenchCard()
                    }
                }
            }
            .padding(WorkbenchLayout.pagePadding)
        }
    }

    private static let cacheFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "HH:mm"
        return value
    }()
}

private struct NewsStoryCard: View {
    enum Prominence: Equatable { case lead, standard }

    let item: NewsItem
    let prominence: Prominence
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            Group {
                if prominence == .lead {
                    leadContent
                } else {
                    rowContent
                }
            }
        }
        .buttonStyle(NewsLinkButtonStyle())
        .onHover { isHovered = $0 }
        .help("在应用内阅读：\(item.displayTitle)")
    }

    private var leadContent: some View {
        HStack(alignment: .bottom, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                StatusPill(text: "头条", tint: WorkbenchTheme.accent)
                Text(item.displayTitle)
                    .font(.custom("PingFangSC-Semibold", size: 23))
                    .foregroundStyle(WorkbenchTheme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                NewsMetadata(item: item)
            }
            Spacer(minLength: 16)
            HStack(spacing: 7) {
                Text("应用内阅读")
                Image(systemName: "arrow.right")
            }
            .font(.custom("PingFangSC-Medium", size: 11))
            .foregroundStyle(WorkbenchTheme.accent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: WorkbenchLayout.cardRadius, style: .continuous))
        .workbenchCard()
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchLayout.cardRadius, style: .continuous)
                .stroke(isHovered ? WorkbenchTheme.accent.opacity(0.38) : Color.clear, lineWidth: 1)
        )
    }

    private var rowContent: some View {
        HStack(spacing: 18) {
            Text(item.displayTitle)
                .font(.custom("PingFangSC-Medium", size: 14))
                .foregroundStyle(WorkbenchTheme.text)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: 12)
            Text(item.source)
                .font(.custom("PingFangSC-Medium", size: 11))
                .foregroundStyle(WorkbenchTheme.secondary)
                .lineLimit(1)
                .frame(width: 138, alignment: .leading)
            Text(item.publishedAt.map(Self.timeFormatter.string) ?? "时间未知")
                .font(.custom("PingFangSC-Regular", size: 11))
                .foregroundStyle(WorkbenchTheme.muted)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovered ? WorkbenchTheme.accent : WorkbenchTheme.muted)
                .frame(width: 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(isHovered ? WorkbenchTheme.raised.opacity(0.72) : Color.clear)
        .contentShape(Rectangle())
    }

    private static let timeFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = .current
        value.dateFormat = "M月d日 HH:mm"
        return value
    }()
}

private struct NewsLedgerHeader: View {
    var body: some View {
        HStack(spacing: 18) {
            Text("标题")
            Spacer(minLength: 12)
            Text("来源").frame(width: 138, alignment: .leading)
            Text("发布时间").frame(width: 108, alignment: .leading)
            Color.clear.frame(width: 18)
        }
        .font(.custom("PingFangSC-Medium", size: 10))
        .tracking(0.8)
        .foregroundStyle(WorkbenchTheme.muted)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(WorkbenchTheme.panel.opacity(0.72))
        .overlay(alignment: .bottom) { Divider().overlay(WorkbenchTheme.border) }
    }
}

private struct NewsMetadata: View {
    let item: NewsItem

    var body: some View {
        HStack(spacing: 8) {
            Label(item.source, systemImage: "building.columns")
                .lineLimit(1)
            if let publishedAt = item.publishedAt {
                Text("·")
                Text(Self.formatter.string(from: publishedAt))
                    .lineLimit(1)
            }
        }
        .font(.custom("PingFangSC-Regular", size: 11))
        .foregroundStyle(WorkbenchTheme.muted)
    }

    private static let formatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = .current
        value.dateFormat = "M月d日 HH:mm"
        return value
    }()
}

private struct NewsLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
    }
}

private struct NewsLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            placeholder(height: 126)
                .workbenchCard()
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    placeholder(height: 62)
                    if index < 5 { Divider().overlay(WorkbenchTheme.border) }
                }
            }
            .workbenchCard()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在抓取最新资讯")
    }

    private func placeholder(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(WorkbenchTheme.raised).frame(width: 160, height: 10)
            RoundedRectangle(cornerRadius: 3).fill(WorkbenchTheme.raised).frame(maxWidth: 520, minHeight: 17, maxHeight: 17)
            RoundedRectangle(cornerRadius: 3).fill(WorkbenchTheme.raised).frame(maxWidth: 360, minHeight: 17, maxHeight: 17)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(WorkbenchTheme.surface.opacity(0.58))
    }
}

extension NewsItem {
    var displayTitle: String {
        var value = title
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - \(source)", " | \(source)"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

struct EventCalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingEditor = false
    @State private var editorSessionID = UUID()
    @State private var deletingEvent: PortfolioEvent?
    @State private var filter: CalendarFilter = .all

    private enum CalendarFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case economic = "宏观"
        case earnings = "财报"
        case personal = "我的事件"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WorkbenchLayout.sectionSpacing) {
                    HStack(alignment: .top, spacing: 20) {
                        SectionHeader(eyebrow: "CATALYSTS", title: "事件日历", detail: "本地关注、Futu OpenD 未来 7 日中高影响事件与持仓财报")
                        Spacer()
                        HStack(spacing: 8) {
                            Button { Task { await store.refreshMarketCalendar() } } label: {
                                Label(store.isRefreshingCalendar ? "刷新中" : "刷新日历", systemImage: "arrow.clockwise")
                            }
                            .workbenchActionButton(.secondary)
                            .disabled(store.isRefreshingCalendar)
                            Button(action: presentEditor) { Label("新增事件", systemImage: "plus") }
                                .workbenchActionButton(.primary)
                        }
                    }

                    CalendarSourceStrip(
                        futuConnected: store.marketCalendarUpdatedAt != nil && (!store.marketCalendarEvents.isEmpty || store.marketCalendarFailures.isEmpty),
                        updatedAt: store.marketCalendarUpdatedAt
                    )

                    HStack(spacing: 6) {
                        ForEach(CalendarFilter.allCases) { item in
                            Button(item.rawValue) { filter = item }
                                .font(.custom("PingFangSC-Medium", size: 11))
                                .foregroundStyle(filter == item ? WorkbenchTheme.canvas : WorkbenchTheme.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(filter == item ? WorkbenchTheme.accent : WorkbenchTheme.panel)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                        }
                        Spacer()
                        Text("\(filteredEntries.count) 个事件")
                            .font(.custom("PingFangSC-Regular", size: 11))
                            .foregroundStyle(WorkbenchTheme.muted)
                    }

                    if !store.marketCalendarFailures.isEmpty {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(WorkbenchTheme.warning)
                            Text(store.marketCalendarFailures.joined(separator: "；"))
                                .font(.custom("PingFangSC-Regular", size: 11))
                                .foregroundStyle(WorkbenchTheme.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(WorkbenchTheme.warning.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius).stroke(WorkbenchTheme.warning.opacity(0.20)))
                        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius))
                    }

                    if filteredEntries.isEmpty {
                        EmptyState(icon: "calendar.badge.plus", title: "当前筛选暂无事件", message: "可刷新 Futu 市场日历，或记录自己的财报、分红与复盘节点。", actionTitle: "新增事件", action: presentEditor)
                    } else {
                        ForEach(groupedEvents, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text(group.date)
                                        .font(.custom("PingFangSC-Semibold", size: 11))
                                        .tracking(1.2)
                                        .foregroundStyle(WorkbenchTheme.accent)
                                    Spacer()
                                    Text("\(group.events.count) 个事件")
                                        .font(.custom("PingFangSC-Regular", size: 10))
                                        .foregroundStyle(WorkbenchTheme.muted)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(WorkbenchTheme.panel.opacity(0.72))

                                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                    CalendarEventRow(entry: event) {
                                        if let local = event.localEvent { deletingEvent = local }
                                    }
                                    if index < group.events.count - 1 {
                                        Divider().overlay(WorkbenchTheme.border)
                                    }
                                }
                            }
                            .workbenchCard()
                        }
                    }
                }
                .padding(WorkbenchLayout.pagePadding)
            }

            if showingEditor {
                WorkbenchDetailOverlay {
                    EventEditor(
                        onCancel: { showingEditor = false },
                        onSave: { event in
                            store.addEvent(event)
                            showingEditor = false
                        }
                    )
                    .id(editorSessionID)
                }
            }
        }
        .background(Color.clear)
        .task {
            if store.marketCalendarUpdatedAt == nil {
                await store.refreshMarketCalendar()
            }
        }
        .animation(.easeOut(duration: 0.14), value: showingEditor)
        .alert("删除事件？", isPresented: Binding(get: { deletingEvent != nil }, set: { if !$0 { deletingEvent = nil } })) {
            Button("取消", role: .cancel) { deletingEvent = nil }
            Button("删除", role: .destructive) {
                if let event = deletingEvent { store.deleteEvent(event) }
                deletingEvent = nil
            }
        }
    }

    private var filteredEntries: [CalendarDisplayEntry] {
        let personal = store.data.events.map(CalendarDisplayEntry.init)
        let market = store.marketCalendarEvents.map(CalendarDisplayEntry.init)
        return (personal + market)
            .filter { entry in
                switch filter {
                case .all: return true
                case .economic: return entry.kind == .economic
                case .earnings: return entry.kind == .earnings
                case .personal: return entry.localEvent != nil
                }
            }
            .sorted { $0.date < $1.date }
    }

    private var groupedEvents: [(date: String, events: [CalendarDisplayEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        let groups = Dictionary(grouping: filteredEntries) { formatter.string(from: $0.date) }
        return groups.map { ($0.key, $0.value) }.sorted { ($0.1.first?.date ?? .distantPast) < ($1.1.first?.date ?? .distantPast) }
    }

    private func presentEditor() {
        editorSessionID = UUID()
        showingEditor = true
    }
}

private struct CalendarDisplayEntry: Identifiable {
    let id: String
    let date: Date
    let hasExactTime: Bool
    let title: String
    let kind: MarketCalendarEventKind?
    let category: String
    let source: String
    let detail: String
    let importance: Int?
    let previous: String?
    let consensus: String?
    let actual: String?
    let localEvent: PortfolioEvent?

    init(_ event: PortfolioEvent) {
        id = "local:\(event.id.uuidString)"
        date = event.date
        hasExactTime = true
        title = event.title
        kind = nil
        category = event.category
        source = "本地记录"
        detail = event.note
        importance = nil
        previous = nil
        consensus = nil
        actual = nil
        localEvent = event
    }

    init(_ event: MarketCalendarEvent) {
        id = event.id
        date = event.date
        hasExactTime = event.hasExactTime
        title = event.title
        kind = event.kind
        category = event.kind.rawValue
        source = event.source
        detail = [event.country, event.market?.rawValue, event.symbol, event.detail]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
        importance = event.importance
        previous = event.previous
        consensus = event.consensus
        actual = event.actual
        localEvent = nil
    }
}

private struct CalendarSourceStrip: View {
    let futuConnected: Bool
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(futuConnected ? WorkbenchTheme.negative : WorkbenchTheme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("事件数据源")
                    .font(.custom("PingFangSC-Semibold", size: 12))
                    .foregroundStyle(WorkbenchTheme.text)
                Text(updatedAt.map { "最近抓取 \(Self.formatter.string(from: $0))" } ?? "等待首次连接")
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(WorkbenchTheme.muted)
            }
            Spacer()
            StatusPill(text: futuConnected ? "Futu OpenD 已连接" : "Futu OpenD 暂不可用", tint: futuConnected ? WorkbenchTheme.negative : WorkbenchTheme.warning)
            StatusPill(text: "金十 · 需开放平台授权", tint: WorkbenchTheme.muted)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(WorkbenchTheme.panel.opacity(0.76))
        .overlay(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius).stroke(WorkbenchTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius))
        .help("金十官方免费引用服务已停止；未配置开放平台授权时不会抓取网页数据")
    }

    private static let formatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "M月d日 HH:mm"
        return value
    }()
}

private struct CalendarEventRow: View {
    let entry: CalendarDisplayEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.hasExactTime ? entry.date.formatted(.dateTime.hour().minute()) : "时间待定")
                    .font(.custom("PingFangSC-Semibold", size: 13))
                    .foregroundStyle(WorkbenchTheme.text)
                    .monospacedDigit()
                Text(entry.source)
                    .font(.custom("PingFangSC-Regular", size: 9))
                    .foregroundStyle(WorkbenchTheme.muted)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(entry.title)
                        .font(.custom("PingFangSC-Semibold", size: 14))
                        .foregroundStyle(WorkbenchTheme.text)
                        .lineLimit(2)
                    StatusPill(text: entry.category, tint: entry.kind == .economic ? WorkbenchTheme.information : WorkbenchTheme.accent)
                    if let importance = entry.importance, importance > 0 {
                        Text(String(repeating: "★", count: min(importance, 5)))
                            .font(.system(size: 9))
                            .foregroundStyle(WorkbenchTheme.warning)
                    }
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.custom("PingFangSC-Regular", size: 10))
                        .foregroundStyle(WorkbenchTheme.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)

            if entry.previous != nil || entry.consensus != nil || entry.actual != nil {
                HStack(spacing: 14) {
                    CalendarValue(label: "前值", value: entry.previous)
                    CalendarValue(label: "预期", value: entry.consensus)
                    CalendarValue(label: "公布", value: entry.actual)
                }
            }
            if entry.localEvent != nil {
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .workbenchActionButton(.destructiveIcon)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
}

private struct CalendarValue: View {
    let label: String
    let value: String?

    var body: some View {
        let displayValue = value.flatMap { $0.isEmpty ? nil : $0 }
        VStack(alignment: .trailing, spacing: 3) {
            Text(label)
                .font(.custom("PingFangSC-Regular", size: 9))
                .foregroundStyle(WorkbenchTheme.muted)
            Text(displayValue ?? "—")
                .font(.custom("PingFangSC-Medium", size: 11))
                .foregroundStyle(displayValue == nil ? WorkbenchTheme.muted : WorkbenchTheme.text)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: 58, alignment: .trailing)
    }
}

private struct EventEditor: View {
    @State private var title = ""
    @State private var date = Date()
    @State private var category = "财报"
    @State private var note = ""
    @FocusState private var focusedField: FocusedField?
    let onCancel: () -> Void
    let onSave: (PortfolioEvent) -> Void

    private enum FocusedField: Hashable {
        case title
        case note
    }

    private let categories = ["财报", "分红", "宏观", "公司事件", "复盘"]

    var body: some View {
        WorkbenchEditorCard {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("新增关注事件")
                            .font(.custom("PingFangSC-Semibold", size: 23).weight(.semibold))
                            .foregroundStyle(WorkbenchTheme.text)
                        Text("记录会保存在本机事件日历中")
                            .font(.custom("PingFangSC-Regular", size: 11))
                            .foregroundStyle(WorkbenchTheme.muted)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("取消", action: onCancel)
                            .workbenchActionButton(.secondary)
                            .keyboardShortcut(.cancelAction)
                        Button("保存") { save() }
                            .workbenchActionButton(.primary)
                            .keyboardShortcut(.defaultAction)
                            .disabled(trimmedTitle.isEmpty)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)

                Divider().overlay(WorkbenchTheme.border)

                VStack(alignment: .leading, spacing: 16) {
                    WorkbenchFormField("事件名称") {
                        TextField("例如：季度财报电话会", text: $title)
                            .focused($focusedField, equals: .title)
                            .workbenchInputField(isFocused: focusedField == .title)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        WorkbenchFormField("日期与时间") {
                            HStack {
                                DatePicker("日期与时间", selection: $date)
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 38, maxHeight: 38)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WorkbenchTheme.raised)
                            .overlay(
                                RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                                    .stroke(WorkbenchTheme.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
                        }
                        WorkbenchFormField("类型") {
                            WorkbenchMenuPicker(
                                selection: $category,
                                options: categories,
                                accessibilityLabel: "事件类型",
                                label: { $0 }
                            )
                        }
                        .frame(width: 180)
                    }

                    WorkbenchFormField("备注（可选）") {
                        TextField("补充会议链接、预期或复盘提示", text: $note, axis: .vertical)
                            .lineLimit(3...5)
                            .focused($focusedField, equals: .note)
                            .workbenchTextArea(isFocused: focusedField == .note, minHeight: 88)
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 580)
        .onAppear { focusedField = .title }
        .onExitCommand(perform: onCancel)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        onSave(
            PortfolioEvent(
                date: date,
                title: trimmedTitle,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category
            )
        )
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AppSettings()
    @State private var apiKey = ""
    @State private var showingCashEditor = false
    @State private var cashEditorSessionID = UUID()
    @State private var deletingCash: CashBalance?
    @FocusState private var focusedInput: FocusedInput?

    private enum FocusedInput: Hashable {
        case futuHost
        case futuPort
        case apiKey
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WorkbenchLayout.sectionSpacing) {
                    SectionHeader(eyebrow: "CONFIGURATION", title: "通用设置", detail: "API Key 保存在应用专属本地文件，不使用钥匙串")
                    sourceCard
                    HStack(alignment: .top, spacing: 12) {
                        cashCard
                        dataCard
                    }
                }
                .padding(WorkbenchLayout.pagePadding)
            }

            if showingCashEditor {
                WorkbenchDetailOverlay {
                    CashEditor(
                        onCancel: { showingCashEditor = false },
                        onSave: { cash in
                            store.addCash(cash)
                            showingCashEditor = false
                        }
                    )
                    .id(cashEditorSessionID)
                }
            }
        }
        .background(Color.clear)
        .onAppear { draft = store.data.settings }
        .animation(.easeOut(duration: 0.14), value: showingCashEditor)
        .alert("删除现金记录？", isPresented: Binding(get: { deletingCash != nil }, set: { if !$0 { deletingCash = nil } })) {
            Button("取消", role: .cancel) { deletingCash = nil }
            Button("删除", role: .destructive) {
                if let value = deletingCash { store.deleteCash(value) }
                deletingCash = nil
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("行情与偏好")
                        .font(.custom("PingFangSC-Semibold", size: 19))
                        .foregroundStyle(WorkbenchTheme.text)
                    Text("选择行情链路，并配置组合的显示口径")
                        .font(.custom("PingFangSC-Regular", size: 11))
                        .foregroundStyle(WorkbenchTheme.muted)
                }
                Spacer()
                StatusPill(text: store.providerStatus, tint: WorkbenchTheme.accent)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    settingsGroupTitle("首选行情源", icon: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Text(providerDetail)
                        .font(.custom("PingFangSC-Regular", size: 10))
                        .foregroundStyle(WorkbenchTheme.muted)
                        .lineLimit(1)
                }
                WorkbenchSegmentSelector(
                    selection: $draft.provider,
                    options: QuoteProvider.allCases,
                    accessibilityLabel: "首选行情源",
                    label: { $0.rawValue }
                )
                if let advisory = store.providerAdvisory {
                    WorkbenchInlineNotice(
                        icon: "arrow.triangle.2.circlepath",
                        title: "行情链路状态",
                        detail: advisory
                    )
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    settingsGroupTitle("Futu OpenD", icon: "desktopcomputer")
                    Spacer()
                    StatusPill(
                        text: store.futuBridgeInstalled ? "连接组件已安装" : "连接组件缺失",
                        tint: store.futuBridgeInstalled ? WorkbenchTheme.negative : WorkbenchTheme.warning
                    )
                }

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        settingsLabel("OpenD 地址")
                        TextField("例如 127.0.0.1", text: $draft.futuHost)
                            .focused($focusedInput, equals: .futuHost)
                            .workbenchInputField(isFocused: focusedInput == .futuHost)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        settingsLabel("端口")
                        TextField("例如 11111", value: $draft.futuPort, format: .number.grouping(.never))
                            .focused($focusedInput, equals: .futuPort)
                            .workbenchInputField(isFocused: focusedInput == .futuPort)
                    }
                    .frame(width: 150)
                }

                Divider().overlay(WorkbenchTheme.border)

                HStack(alignment: .center, spacing: 12) {
                    settingsGroupTitle("Twelve Data", icon: "key.horizontal")
                    Spacer()
                    StatusPill(
                        text: store.twelveDataKeyPresent ? "本地已保存" : "尚未配置 API Key",
                        tint: store.twelveDataKeyPresent ? WorkbenchTheme.negative : WorkbenchTheme.warning
                    )
                }

                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 7) {
                        settingsLabel("API Key")
                        ZStack(alignment: .leading) {
                            SecureField(
                                store.twelveDataKeyPresent && apiKey.isEmpty && focusedInput != .apiKey
                                    ? ""
                                    : (store.twelveDataKeyPresent ? "输入新 Key 以替换本地凭证" : "输入 API Key"),
                                text: $apiKey
                            )
                                .focused($focusedInput, equals: .apiKey)
                                .workbenchInputField(isFocused: focusedInput == .apiKey)
                                .accessibilityLabel("Twelve Data API Key")
                                .accessibilityValue(
                                    store.twelveDataKeyPresent && apiKey.isEmpty
                                        ? "已保存到应用专属本地文件"
                                        : (apiKey.isEmpty ? "尚未配置" : "已输入新凭证")
                                )

                            if store.twelveDataKeyPresent, apiKey.isEmpty, focusedInput != .apiKey {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(WorkbenchTheme.negative)
                                    Text("••••••••••••••••")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(WorkbenchTheme.text)
                                    Text("本地已保存 · 输入新 Key 可替换")
                                        .font(.custom("PingFangSC-Regular", size: 10))
                                        .foregroundStyle(WorkbenchTheme.muted)
                                }
                                .padding(.horizontal, 11)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                        }
                    }
                    Button(store.twelveDataKeyPresent ? "移除 Key" : "清空") {
                        apiKey = ""
                        focusedInput = nil
                        if store.twelveDataKeyPresent { store.saveTwelveDataKey("") }
                    }
                    .workbenchActionButton(store.twelveDataKeyPresent ? .destructive : .secondary)
                    Button("保存 Key") {
                        store.saveTwelveDataKey(apiKey)
                        apiKey = ""
                        focusedInput = nil
                    }
                    .workbenchActionButton(.secondary)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)
            .background(WorkbenchTheme.panel.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous)
                    .stroke(WorkbenchTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous))

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("行情源自动降级")
                        .font(.custom("PingFangSC-Medium", size: 12))
                        .foregroundStyle(WorkbenchTheme.text)
                    Text("上游不可用时继续尝试公开备用行情，公开价格始终标注“可能延迟”")
                        .font(.custom("PingFangSC-Regular", size: 10))
                        .foregroundStyle(WorkbenchTheme.muted)
                }
                Spacer()
                Toggle("行情源自动降级", isOn: $draft.allowPublicFallback)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(WorkbenchTheme.accent)
            }
            .padding(12)
            .background(WorkbenchTheme.raised)
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous)
                    .stroke(WorkbenchTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous))

            Divider().overlay(WorkbenchTheme.border)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    settingsLabel("基准币种")
                    WorkbenchMenuPicker(
                        selection: $draft.baseCurrency,
                        options: CurrencyCode.allCases,
                        accessibilityLabel: "基准币种",
                        label: { $0.rawValue }
                    )
                    .frame(width: 170)
                }
                VStack(alignment: .leading, spacing: 7) {
                    settingsLabel("自动刷新")
                    WorkbenchMenuPicker(
                        selection: $draft.refreshIntervalSeconds,
                        options: [30, 60, 120, 300],
                        accessibilityLabel: "自动刷新",
                        label: refreshLabel
                    )
                    .frame(width: 170)
                }
                Spacer()
                if draft != store.data.settings {
                    HStack(spacing: 7) {
                        Image(systemName: "pencil.line")
                        Text("有未保存修改")
                    }
                    .font(.custom("PingFangSC-Medium", size: 11))
                    .foregroundStyle(WorkbenchTheme.warning)
                    .padding(.horizontal, 10)
                    .frame(height: WorkbenchLayout.actionHeight)
                    .background(WorkbenchTheme.warning.opacity(0.08))
                    .clipShape(Capsule())
                }
                Button("保存并测试") { store.saveSettings(draft) }
                    .workbenchActionButton(.primary)
                    .disabled(draft == store.data.settings)
            }
            Text("自动优先级：Futu OpenD → Twelve Data → 腾讯公开备用行情。Twelve Data 扩展时段会显式请求盘前和盘后数据。")
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundStyle(WorkbenchTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .workbenchCard()
    }

    private var providerDetail: String {
        switch draft.provider {
        case .automatic: return "按授权 API、正规 API、公开备用行情依次尝试"
        case .futu: return "使用本机 Futu OpenD"
        case .twelveData: return "使用应用专属本地文件中的 API Key"
        case .publicFallback: return "公开行情，可能延迟"
        }
    }

    private func refreshLabel(_ seconds: Int) -> String {
        switch seconds {
        case 30: return "30 秒"
        case 60: return "60 秒"
        case 120: return "2 分钟"
        case 300: return "5 分钟"
        default: return "\(seconds) 秒"
        }
    }

    private func settingsGroupTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.custom("PingFangSC-Semibold", size: 13))
            .foregroundStyle(WorkbenchTheme.text)
            .labelStyle(.titleAndIcon)
    }

    private func settingsLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom("PingFangSC-Medium", size: 11))
            .foregroundStyle(WorkbenchTheme.secondary)
    }

    private var cashCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("现金")
                    .font(.custom("PingFangSC-Semibold", size: 19).weight(.semibold))
                    .foregroundStyle(WorkbenchTheme.text)
                Spacer()
                Button {
                    cashEditorSessionID = UUID()
                    showingCashEditor = true
                } label: { Label("新增现金", systemImage: "plus") }
                    .workbenchActionButton(.secondary)
            }
            if store.data.cash.isEmpty {
                Text("尚未录入现金。首页现金为 0，不包含示例资金。")
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundStyle(WorkbenchTheme.muted)
                    .padding(.vertical, 12)
            } else {
                ForEach(store.data.cash) { cash in
                    HStack {
                        StatusPill(text: cash.currency.rawValue, tint: WorkbenchTheme.accent)
                        Text(DisplayFormat.money(cash.amount, currency: cash.currency))
                            .font(.custom("PingFangSC-Semibold", size: 14))
                            .foregroundStyle(WorkbenchTheme.text)
                        Text(cash.note)
                            .font(.custom("PingFangSC-Regular", size: 11))
                            .foregroundStyle(WorkbenchTheme.muted)
                        Spacer()
                        Button(role: .destructive) { deletingCash = cash } label: { Image(systemName: "trash") }
                            .workbenchActionButton(.destructiveIcon)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .topLeading)
        .workbenchCard()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数据与时间")
                .font(.custom("PingFangSC-Semibold", size: 19).weight(.semibold))
                .foregroundStyle(WorkbenchTheme.text)
            SettingsDatum(label: "资产数据文件", value: store.dataFilePath)
            SettingsDatum(label: "API Key", value: store.twelveDataKeyPresent ? "已保存到本地文件（仅当前用户可读）" : "未配置")
            SettingsDatum(label: "API Key 文件", value: store.apiKeyFilePath)
            SettingsDatum(label: "网络时间", value: store.timeHealth.serverDate.map { DisplayFormat.dateTime($0) } ?? "尚未校验")
            SettingsDatum(label: "时间偏差", value: store.timeHealth.serverDate == nil ? "尚未校验" : "\(Int(store.timeHealth.offset)) 秒")
            SettingsDatum(label: "汇率来源", value: store.exchangeRates.map { "\($0.source) · \(DisplayFormat.shortDate($0.date))" } ?? "暂无数据")
            Text("软件只读行情，不连接交易、下单或资金划转接口。API Key 不读取、不写入钥匙串，本地文件权限为 0600。")
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundStyle(WorkbenchTheme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .topLeading)
        .workbenchCard()
    }
}

private struct SettingsDatum: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(WorkbenchTheme.muted).frame(width: 100, alignment: .leading)
            Text(value).foregroundStyle(WorkbenchTheme.secondary).textSelection(.enabled)
            Spacer()
        }
        .font(.custom("PingFangSC-Regular", size: 11))
    }
}

private struct CashEditor: View {
    @State private var currency: CurrencyCode = .cny
    @State private var amount = ""
    @State private var note = ""
    @FocusState private var focusedField: FocusedField?
    let onCancel: () -> Void
    let onSave: (CashBalance) -> Void

    private enum FocusedField: Hashable {
        case amount
        case note
    }

    var body: some View {
        WorkbenchEditorCard {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("新增现金")
                            .font(.custom("PingFangSC-Semibold", size: 23).weight(.semibold))
                            .foregroundStyle(WorkbenchTheme.text)
                        Text("记录仅保存在本机资产文件中")
                            .font(.custom("PingFangSC-Regular", size: 11))
                            .foregroundStyle(WorkbenchTheme.muted)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("取消", action: onCancel)
                            .workbenchActionButton(.secondary)
                            .keyboardShortcut(.cancelAction)
                        Button("保存", action: save)
                            .workbenchActionButton(.primary)
                            .keyboardShortcut(.defaultAction)
                            .disabled(amountValue == nil)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)

                Divider().overlay(WorkbenchTheme.border)

                VStack(alignment: .leading, spacing: 16) {
                    WorkbenchFormField("币种") {
                        WorkbenchMenuPicker(
                            selection: $currency,
                            options: CurrencyCode.allCases,
                            accessibilityLabel: "现金币种",
                            label: { $0.rawValue }
                        )
                    }
                    HStack(alignment: .top, spacing: 12) {
                        WorkbenchFormField("金额") {
                            TextField("例如：100000", text: $amount)
                                .focused($focusedField, equals: .amount)
                                .workbenchInputField(isFocused: focusedField == .amount)
                        }
                        WorkbenchFormField("备注（可选）") {
                            TextField("例如：活期账户", text: $note)
                                .focused($focusedField, equals: .note)
                                .workbenchInputField(isFocused: focusedField == .note)
                        }
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 520)
        .onAppear { focusedField = .amount }
        .onExitCommand(perform: onCancel)
    }

    private var amountValue: Double? {
        guard let value = Double(amount.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
        return value
    }

    private func save() {
        guard let amountValue else { return }
        onSave(
            CashBalance(
                currency: currency,
                amount: amountValue,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }
}
