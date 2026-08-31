import SwiftUI

struct HoldingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingHolding: Holding?
    @State private var showingEditor = false
    @State private var editorSessionID = UUID()
    @State private var deletingHolding: Holding?
    @State private var marketFilter: HoldingsMarketFilter = .all

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WorkbenchLayout.sectionSpacing) {
                    HStack(alignment: .top, spacing: 20) {
                        SectionHeader(eyebrow: "POSITIONS", title: "我的持仓", detail: "数量是市值计算依据")
                        Spacer()
                        if !store.data.holdings.isEmpty {
                            Button {
                                presentEditor(for: nil)
                            } label: {
                                Label("新增持仓", systemImage: "plus")
                            }
                            .workbenchActionButton(.primary)
                        }
                    }

                    if store.data.holdings.isEmpty {
                        EmptyState(
                            icon: "briefcase",
                            title: "没有持仓记录",
                            message: "请录入真实持仓。未填写数量时，将按投入成本和均价估算，并持续标注“估算持仓”。",
                            actionTitle: "新增持仓",
                            action: { presentEditor(for: nil) }
                        )
                    } else {
                        let visibleMetrics = filteredMetrics
                        HoldingsSummaryCard(
                            summary: store.holdingsSummary(for: marketFilter.market),
                            scopeTitle: marketFilter.title,
                            exchangeRates: store.exchangeRates,
                            requiresExchangeRate: visibleMetrics.contains {
                                $0.holding.currency != store.data.settings.baseCurrency
                            }
                        )
                        WorkbenchSegmentSelector(
                            selection: $marketFilter,
                            options: HoldingsMarketFilter.allCases,
                            accessibilityLabel: "持仓市场筛选",
                            label: { "\($0.title) \(holdingCount(for: $0))" }
                        )
                        if visibleMetrics.isEmpty {
                            VStack(spacing: 9) {
                                Image(systemName: "tray")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(WorkbenchTheme.accent)
                                Text("暂无\(marketFilter.title)持仓")
                                    .font(.custom("PingFangSC-Semibold", size: 16))
                                    .foregroundStyle(WorkbenchTheme.text)
                                Text("可点击右上角“新增持仓”录入该市场标的")
                                    .font(.custom("PingFangSC-Regular", size: 11))
                                    .foregroundStyle(WorkbenchTheme.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .workbenchCard()
                        }
                        VStack(spacing: 0) {
                            HoldingsTableHeader()
                            ForEach(Array(visibleMetrics.enumerated()), id: \.element.id) { index, metrics in
                                HoldingCard(
                                    metrics: metrics,
                                    failure: store.quoteFailures[metrics.holding.quoteKey],
                                    edit: { presentEditor(for: metrics.holding) },
                                    delete: { deletingHolding = metrics.holding }
                                )
                                if index < visibleMetrics.count - 1 {
                                    Divider().overlay(WorkbenchTheme.border)
                                }
                            }
                        }
                        .workbenchCard()
                    }
                }
                .padding(WorkbenchLayout.pagePadding)
            }

            if showingEditor {
                WorkbenchDetailOverlay {
                    HoldingEditor(
                        holding: editingHolding,
                        onCancel: dismissEditor,
                        onSave: { holding in
                            if editingHolding == nil {
                                store.addHolding(holding)
                            } else {
                                store.updateHolding(holding)
                            }
                            dismissEditor()
                        }
                    )
                    .id(editorSessionID)
                }
            }
        }
        .background(Color.clear)
        .animation(.easeOut(duration: 0.14), value: showingEditor)
        .alert("删除持仓？", isPresented: Binding(
            get: { deletingHolding != nil },
            set: { if !$0 { deletingHolding = nil } }
        )) {
            Button("取消", role: .cancel) { deletingHolding = nil }
            Button("删除", role: .destructive) {
                if let holding = deletingHolding { store.deleteHolding(holding) }
                deletingHolding = nil
            }
        } message: {
            Text("这会删除 \(deletingHolding?.name ?? "该标的") 的本地记录，无法撤销。")
        }
    }

    private func presentEditor(for holding: Holding?) {
        editingHolding = holding
        editorSessionID = UUID()
        showingEditor = true
    }

    private func dismissEditor() {
        showingEditor = false
        editingHolding = nil
    }

    private var filteredMetrics: [HoldingMetrics] {
        let metrics = store.holdingMetrics()
        guard let market = marketFilter.market else { return metrics }
        return metrics.filter { $0.holding.market == market }
    }

    private func holdingCount(for filter: HoldingsMarketFilter) -> Int {
        guard let market = filter.market else { return store.data.holdings.count }
        return store.data.holdings.filter { $0.market == market }.count
    }
}

private enum HoldingsMarketFilter: CaseIterable, Hashable {
    case all
    case cn
    case us
    case hk

    var title: String {
        switch self {
        case .all: return "全部"
        case .cn: return "A股"
        case .us: return "美股"
        case .hk: return "港股"
        }
    }

    var market: Market? {
        switch self {
        case .all: return nil
        case .cn: return .cn
        case .us: return .us
        case .hk: return .hk
        }
    }
}

private struct HoldingsSummaryCard: View {
    let summary: HoldingsSummary
    let scopeTitle: String
    let exchangeRates: ExchangeRateSnapshot?
    let requiresExchangeRate: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("持仓汇总")
                        .font(.custom("PingFangSC-Semibold", size: 18))
                        .foregroundStyle(WorkbenchTheme.text)
                    Text(conversionNote)
                        .font(.custom("PingFangSC-Regular", size: 10))
                        .foregroundStyle(summary.isPartial ? WorkbenchTheme.warning : WorkbenchTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(text: scopeTitle, tint: WorkbenchTheme.accent)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                HoldingsSummaryDatum(
                    label: "持仓市值",
                    value: DisplayFormat.money(summary.marketValue, currency: summary.currency, compact: true)
                )
                HoldingsSummaryDatum(
                    label: "当日盈亏",
                    value: DisplayFormat.money(summary.dailyProfit, currency: summary.currency, compact: true),
                    change: summary.dailyProfit
                )
                HoldingsSummaryDatum(
                    label: "总盈亏",
                    value: DisplayFormat.money(summary.totalProfit, currency: summary.currency, compact: true),
                    change: summary.totalProfit
                )
                HoldingsSummaryDatum(
                    label: "收益率",
                    value: DisplayFormat.percent(summary.totalReturn),
                    change: summary.totalReturn
                )
            }

            HStack(spacing: 9) {
                StatusPill(text: "\(summary.positionCount) 个标的", tint: WorkbenchTheme.secondary)
                StatusPill(text: "估算持仓 \(summary.estimatedCount)", tint: WorkbenchTheme.warning)
                StatusPill(text: "行情缺失 \(summary.missingQuoteCount)", tint: summary.missingQuoteCount == 0 ? WorkbenchTheme.negative : WorkbenchTheme.warning)
                Spacer()
            }
        }
        .padding(18)
        .workbenchCard()
    }

    private var conversionNote: String {
        if let exchangeRates {
            let date = DisplayFormat.shortDate(exchangeRates.date)
            let partial = summary.isPartial ? " · 部分行情或成本缺失" : ""
            return "按 \(summary.currency.rawValue) 折算 · \(exchangeRates.source) · \(date)\(partial)"
        }
        if requiresExchangeRate {
            return "跨币种汇率暂无数据，汇总项将显示“暂无数据”"
        }
        return "按 \(summary.currency.rawValue) 统计 · 当前筛选无需汇率换算"
    }
}

private struct HoldingsSummaryDatum: View {
    let label: String
    let value: String
    var change: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.custom("PingFangSC-Medium", size: 10))
                .foregroundStyle(WorkbenchTheme.muted)
            if change != nil {
                ChangeText(value: change, text: value)
                    .font(.custom("PingFangSC-Semibold", size: 19))
            } else {
                Text(value)
                    .font(.custom("PingFangSC-Semibold", size: 19))
                    .foregroundStyle(WorkbenchTheme.text)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(13)
        .background(WorkbenchTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous))
    }
}

private struct HoldingCard: View {
    let metrics: HoldingMetrics
    let failure: QuoteFailure?
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(metrics.holding.name)
                            .font(.custom("PingFangSC-Semibold", size: 14))
                            .foregroundStyle(WorkbenchTheme.text)
                            .lineLimit(1)
                        if metrics.holding.isEstimated {
                            StatusPill(text: "估算", tint: WorkbenchTheme.warning)
                        }
                    }
                    Text("\(metrics.holding.normalizedCode) · \(metrics.holding.sector.isEmpty ? "未分类" : metrics.holding.sector)")
                        .lineLimit(1)
                    Text("数量 \(DisplayFormat.number(metrics.holding.effectiveQuantity, digits: 4))")
                        .lineLimit(1)
                }
                .font(.custom("PingFangSC-Regular", size: 9))
                .foregroundStyle(WorkbenchTheme.muted)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

                HoldingCell(value: DisplayFormat.money(metrics.marketValue, currency: metrics.holding.currency), width: 120)
                HoldingCell(value: DisplayFormat.money(metrics.dailyProfit, currency: metrics.holding.currency), change: metrics.dailyProfit, width: 115)
                HoldingCell(value: DisplayFormat.money(metrics.totalProfit, currency: metrics.holding.currency), change: metrics.totalProfit, width: 115)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(DisplayFormat.money(metrics.holding.averageCost, currency: metrics.holding.currency))
                    Text(metrics.quote.map { DisplayFormat.money($0.price, currency: metrics.holding.currency) } ?? "暂无数据")
                        .foregroundStyle(metrics.quote == nil ? WorkbenchTheme.muted : WorkbenchTheme.text)
                }
                .font(.custom("PingFangSC-Medium", size: 11))
                .monospacedDigit()
                .frame(minWidth: 115, maxWidth: .infinity, alignment: .trailing)

                HoldingCell(value: DisplayFormat.percent(metrics.quote?.percentChange), change: metrics.quote?.percentChange, width: 75)
                HoldingCell(value: DisplayFormat.percent(metrics.weight, signed: false), width: 65)

                VStack(alignment: .leading, spacing: 3) {
                    Text(metrics.holding.market.rawValue)
                        .foregroundStyle(WorkbenchTheme.text)
                    Text(metrics.quote?.passport.session.rawValue ?? "暂无数据")
                        .foregroundStyle(metrics.quote == nil ? WorkbenchTheme.warning : WorkbenchTheme.secondary)
                }
                .font(.custom("PingFangSC-Medium", size: 10))
                .frame(minWidth: 86, maxWidth: 120, alignment: .leading)

                Menu {
                    Button("修改", systemImage: "pencil", action: edit)
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: WorkbenchLayout.actionHeight)
                .workbenchActionButton(.icon)
            }
            if let quote = metrics.quote {
                PricePassportView(quote: quote, compact: true)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "shield.slash")
                    Text(failure?.message ?? "接口失效或字段不可验证，当前标的显示“暂无数据”，不会沿用旧价格。")
                }
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundStyle(WorkbenchTheme.warning)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchTheme.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct HoldingsTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            HoldingColumnLabel("名称 / 板块", width: 160, alignment: .leading)
            HoldingColumnLabel("持仓市值", width: 120)
            HoldingColumnLabel("当日盈亏", width: 115)
            HoldingColumnLabel("总盈亏", width: 115)
            HoldingColumnLabel("成本 / 现价", width: 135)
            HoldingColumnLabel("涨跌幅", width: 75)
            HoldingColumnLabel("权重", width: 65)
            HoldingColumnLabel("市场 / 状态", width: 96, alignment: .leading)
            Spacer(minLength: 0)
            Color.clear.frame(width: WorkbenchLayout.actionHeight)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(WorkbenchTheme.panel.opacity(0.72))
        .overlay(alignment: .bottom) { Divider().overlay(WorkbenchTheme.border) }
    }
}

private struct HoldingColumnLabel: View {
    let text: String
    let width: CGFloat
    let alignment: Alignment

    init(_ text: String, width: CGFloat, alignment: Alignment = .trailing) {
        self.text = text
        self.width = width
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(.custom("PingFangSC-Medium", size: 9))
            .foregroundStyle(WorkbenchTheme.muted)
            .frame(minWidth: width, maxWidth: .infinity, alignment: alignment)
    }
}

private struct HoldingCell: View {
    let value: String
    var change: Double? = nil
    let width: CGFloat

    var body: some View {
        Group {
            if let change {
                ChangeText(value: change, text: value)
            } else {
                Text(value).foregroundStyle(WorkbenchTheme.text)
            }
        }
        .font(.custom("PingFangSC-Semibold", size: 11))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(minWidth: width, maxWidth: .infinity, alignment: .trailing)
    }
}

struct HoldingEditor: View {
    private let original: Holding?
    private let onCancel: () -> Void
    private let onSave: (Holding) -> Void

    @State private var market: Market
    @State private var name: String
    @State private var code: String
    @State private var sector: String
    @State private var quantity: String
    @State private var averageCost: String
    @State private var investedCost: String
    @State private var currency: CurrencyCode
    @State private var showValidation = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case name
        case code
        case sector
        case quantity
        case averageCost
        case investedCost
    }

    init(holding: Holding?, onCancel: @escaping () -> Void, onSave: @escaping (Holding) -> Void) {
        self.original = holding
        self.onCancel = onCancel
        self.onSave = onSave
        _market = State(initialValue: holding?.market ?? .us)
        _name = State(initialValue: holding?.name ?? "")
        _code = State(initialValue: holding?.code ?? "")
        _sector = State(initialValue: holding?.sector ?? "")
        _quantity = State(initialValue: holding?.quantity.map { DisplayFormat.number($0, digits: 6) } ?? "")
        _averageCost = State(initialValue: holding.map { DisplayFormat.number($0.averageCost, digits: 6) } ?? "")
        _investedCost = State(initialValue: holding?.investedCost.map { DisplayFormat.number($0, digits: 2) } ?? "")
        _currency = State(initialValue: holding?.currency ?? .usd)
    }

    var body: some View {
        WorkbenchEditorCard {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(original == nil ? "新增持仓" : "修改持仓")
                            .font(.custom("PingFangSC-Semibold", size: 23).weight(.semibold))
                            .foregroundStyle(WorkbenchTheme.text)
                        Text("所有数据均保存在本机，保存后再刷新对应行情")
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
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)

                Divider().overlay(WorkbenchTheme.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("标的信息")
                            .font(.custom("PingFangSC-Semibold", size: 13))
                            .foregroundStyle(WorkbenchTheme.text)

                        WorkbenchFormField("市场") {
                            WorkbenchSegmentSelector(
                                selection: $market,
                                options: Market.allCases,
                                accessibilityLabel: "市场",
                                label: { $0.rawValue }
                            )
                            .onChange(of: market) { newValue in
                                currency = newValue.defaultCurrency
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            WorkbenchFormField("名称") {
                                TextField("例如：苹果", text: $name)
                                    .focused($focusedField, equals: .name)
                                    .workbenchInputField(isFocused: focusedField == .name)
                            }
                            WorkbenchFormField("证券代码") {
                                TextField("例如：AAPL / 00700 / 600519", text: $code)
                                    .focused($focusedField, equals: .code)
                                    .workbenchInputField(isFocused: focusedField == .code)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            WorkbenchFormField("板块") {
                                TextField("例如：科技 / 消费 / 医疗", text: $sector)
                                    .focused($focusedField, equals: .sector)
                                    .workbenchInputField(isFocused: focusedField == .sector)
                            }
                            WorkbenchFormField("币种") {
                                WorkbenchMenuPicker(
                                    selection: $currency,
                                    options: CurrencyCode.allCases,
                                    accessibilityLabel: "币种",
                                    label: { $0.rawValue }
                                )
                            }
                        }

                        Divider().overlay(WorkbenchTheme.border)

                        Text("成本与数量")
                            .font(.custom("PingFangSC-Semibold", size: 13))
                            .foregroundStyle(WorkbenchTheme.text)

                        HStack(alignment: .top, spacing: 12) {
                            WorkbenchFormField("数量（首选）") {
                                TextField("留空则估算", text: $quantity)
                                    .focused($focusedField, equals: .quantity)
                                    .workbenchInputField(isFocused: focusedField == .quantity)
                            }
                            WorkbenchFormField("均价") {
                                TextField("必填", text: $averageCost)
                                    .focused($focusedField, equals: .averageCost)
                                    .workbenchInputField(isFocused: focusedField == .averageCost)
                            }
                            WorkbenchFormField("投入成本") {
                                TextField("无数量时必填", text: $investedCost)
                                    .focused($focusedField, equals: .investedCost)
                                    .workbenchInputField(isFocused: focusedField == .investedCost)
                            }
                        }

                        if quantityValue == nil {
                            WorkbenchInlineNotice(
                                icon: "exclamationmark.triangle",
                                title: "当前将按估算持仓保存",
                                detail: "系统会用投入成本除以均价反推数量，并持续显示“估算持仓”。"
                            )
                        } else {
                            WorkbenchInlineNotice(
                                icon: "checkmark.shield",
                                title: "数量将作为计算依据",
                                detail: "持仓市值与盈亏将优先使用你录入的数量。",
                                tint: WorkbenchTheme.negative
                            )
                        }

                        if showValidation && !isValid {
                            WorkbenchInlineNotice(
                                icon: "exclamationmark.circle",
                                title: "暂时无法保存",
                                detail: validationMessage,
                                tint: WorkbenchTheme.positive
                            )
                        }
                    }
                    .padding(22)
                }
                .frame(maxHeight: 500)
            }
        }
        .frame(width: 660)
        .onExitCommand(perform: onCancel)
    }

    private var quantityValue: Double? {
        guard let value = Double(quantity.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private var averageCostValue: Double? {
        guard let value = Double(averageCost.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private var investedCostValue: Double? {
        guard let value = Double(investedCost.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        averageCostValue != nil &&
        (quantityValue != nil || investedCostValue != nil)
    }

    private var validationMessage: String {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写名称" }
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写证券代码" }
        if averageCostValue == nil { return "均价必须是大于 0 的数字" }
        return "请填写有效数量，或在无数量时填写大于 0 的投入成本"
    }

    private func save() {
        showValidation = true
        guard isValid, let averageCostValue else { return }
        let holding = Holding(
            id: original?.id ?? UUID(),
            market: market,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            code: market.normalizedCode(code),
            sector: sector.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: quantityValue,
            averageCost: averageCostValue,
            investedCost: investedCostValue,
            currency: currency,
            createdAt: original?.createdAt ?? Date()
        )
        onSave(holding)
    }
}
