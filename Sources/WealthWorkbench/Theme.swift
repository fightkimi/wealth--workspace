import SwiftUI

enum WorkbenchTheme {
    // AUREL / Mole-inspired warm graphite system.
    static let canvas = Color(hex: 0x13140F)
    static let chrome = Color(hex: 0x211D13)
    static let sidebar = chrome
    static let surface = Color(hex: 0x27251C)
    static let raised = Color(hex: 0x343026)
    static let panel = Color(hex: 0x1A1914)
    static let border = Color(hex: 0x9A8D70, alpha: 0.16)
    static let strongBorder = Color(hex: 0xB8AA88, alpha: 0.27)
    static let text = Color(hex: 0xF1EFE8)
    static let secondary = Color(hex: 0xBCB8A9)
    static let muted = Color(hex: 0x858175)
    static let accent = Color(hex: 0xD7B66F)
    static let accentSoft = Color(hex: 0x967844)
    // 中国市场看盘习惯：红涨、绿跌。
    static let positive = Color(hex: 0xE56B67)
    static let negative = Color(hex: 0x59B98A)
    static let warning = Color(hex: 0xD69C50)
    static let information = Color(hex: 0x6092B7)
}

enum WorkbenchLayout {
    static let pagePadding: CGFloat = 22
    static let sectionSpacing: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 8
    static let controlRadius: CGFloat = 8
    static let actionHeight: CGFloat = 34
    static let topBarHeight: CGFloat = 68
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

extension View {
    func workbenchCard(radius: CGFloat = WorkbenchLayout.cardRadius) -> some View {
        self
            .background(
                LinearGradient(
                    colors: [WorkbenchTheme.raised.opacity(0.82), WorkbenchTheme.surface.opacity(0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(WorkbenchTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 7, x: 0, y: 4)
    }
}

struct WorkbenchBackdrop: View {
    var body: some View {
        ZStack {
            WorkbenchTheme.canvas
            RadialGradient(
                colors: [
                    Color(hex: 0x72511B, alpha: 0.26),
                    Color(hex: 0x3C3219, alpha: 0.14),
                    .clear
                ],
                center: UnitPoint(x: 0.18, y: -0.04),
                startRadius: 20,
                endRadius: 960
            )
            LinearGradient(
                colors: [
                    Color(hex: 0x554019, alpha: 0.18),
                    Color(hex: 0x29271A, alpha: 0.10),
                    .clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.58)
            )
        }
        .ignoresSafeArea()
    }
}

struct AurelMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(WorkbenchTheme.text)
                Circle()
                    .stroke(WorkbenchTheme.accent.opacity(0.52), lineWidth: max(0.8, side * 0.026))
                Canvas { context, size in
                    let unit = min(size.width, size.height)
                    let origin = CGPoint(x: (size.width - unit) / 2, y: (size.height - unit) / 2)
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: origin.x + unit * x, y: origin.y + unit * y)
                    }

                    var monogram = Path()
                    monogram.move(to: point(0.27, 0.72))
                    monogram.addLine(to: point(0.49, 0.25))
                    monogram.addLine(to: point(0.74, 0.72))
                    context.stroke(
                        monogram,
                        with: .color(WorkbenchTheme.chrome),
                        style: StrokeStyle(lineWidth: unit * 0.085, lineCap: .round, lineJoin: .round)
                    )

                    var capitalArc = Path()
                    capitalArc.move(to: point(0.35, 0.59))
                    capitalArc.addLine(to: point(0.47, 0.59))
                    capitalArc.addLine(to: point(0.55, 0.49))
                    capitalArc.addLine(to: point(0.65, 0.56))
                    context.stroke(
                        capitalArc,
                        with: .color(WorkbenchTheme.accentSoft),
                        style: StrokeStyle(lineWidth: unit * 0.07, lineCap: .round, lineJoin: .round)
                    )

                    context.fill(
                        Path(ellipseIn: CGRect(x: point(0.69, 0.51).x, y: point(0.69, 0.51).y, width: unit * 0.075, height: unit * 0.075)),
                        with: .color(WorkbenchTheme.chrome)
                    )
                }
                .padding(side * 0.12)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum DisplayFormat {
    static func money(_ value: Double?, currency: CurrencyCode, compact: Bool = false) -> String {
        guard let value, value.isFinite else { return "暂无数据" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = compact && abs(value) >= 100_000 ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency.symbol)\(value)"
    }

    static func number(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "暂无数据" }
        return value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func percent(_ value: Double?, signed: Bool = true) -> String {
        guard let value, value.isFinite else { return "暂无数据" }
        let sign = signed && value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))%"
    }

    static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }
}

struct ChangeText: View {
    let value: Double?
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private var color: Color {
        guard let value else { return WorkbenchTheme.muted }
        if value > 0 { return WorkbenchTheme.positive }
        if value < 0 { return WorkbenchTheme.negative }
        return WorkbenchTheme.secondary
    }
}

struct StatusPill: View {
    let text: String
    var tint = WorkbenchTheme.secondary

    var body: some View {
        Text(text)
            .font(.custom("PingFangSC-Medium", size: 11))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.11))
            .overlay(Capsule().stroke(tint.opacity(0.14), lineWidth: 1))
            .clipShape(Capsule())
    }
}

enum WorkbenchActionKind: Equatable {
    case primary
    case secondary
    case destructive
    case icon
    case destructiveIcon

    fileprivate var isIconOnly: Bool {
        self == .icon || self == .destructiveIcon
    }
}

struct WorkbenchActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let kind: WorkbenchActionKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("PingFangSC-Medium", size: 12))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, kind.isIconOnly ? 0 : 12)
            .frame(
                minWidth: kind.isIconOnly ? WorkbenchLayout.actionHeight : 72,
                minHeight: WorkbenchLayout.actionHeight,
                maxHeight: WorkbenchLayout.actionHeight
            )
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.78 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return WorkbenchTheme.canvas
        case .destructive, .destructiveIcon: return WorkbenchTheme.positive
        case .secondary, .icon: return WorkbenchTheme.text
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return WorkbenchTheme.accent
        case .destructive, .destructiveIcon: return WorkbenchTheme.positive.opacity(0.10)
        case .secondary, .icon: return WorkbenchTheme.raised.opacity(0.92)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return WorkbenchTheme.accent.opacity(0.72)
        case .destructive, .destructiveIcon: return WorkbenchTheme.positive.opacity(0.30)
        case .secondary, .icon: return WorkbenchTheme.border
        }
    }
}

extension View {
    func workbenchActionButton(_ kind: WorkbenchActionKind = .secondary) -> some View {
        buttonStyle(WorkbenchActionButtonStyle(kind: kind))
    }

    func workbenchInputField(isFocused: Bool = false) -> some View {
        modifier(WorkbenchInputFieldModifier(isFocused: isFocused))
    }

    func workbenchTextArea(isFocused: Bool = false, minHeight: CGFloat = 84) -> some View {
        modifier(WorkbenchTextAreaModifier(isFocused: isFocused, minHeight: minHeight))
    }
}

private struct WorkbenchInputFieldModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.custom("PingFangSC-Regular", size: 12))
            .foregroundStyle(WorkbenchTheme.text)
            .padding(.horizontal, 11)
            .frame(minHeight: 38, maxHeight: 38)
            .background(WorkbenchTheme.raised)
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                    .stroke(
                        isFocused ? WorkbenchTheme.accent.opacity(0.9) : WorkbenchTheme.border,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
    }
}

private struct WorkbenchTextAreaModifier: ViewModifier {
    let isFocused: Bool
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.custom("PingFangSC-Regular", size: 12))
            .foregroundStyle(WorkbenchTheme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(WorkbenchTheme.raised)
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                    .stroke(
                        isFocused ? WorkbenchTheme.accent.opacity(0.9) : WorkbenchTheme.border,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
    }
}

struct WorkbenchFormField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.custom("PingFangSC-Medium", size: 11))
                .foregroundStyle(WorkbenchTheme.secondary)
            content
        }
    }
}

struct WorkbenchInlineNotice: View {
    let icon: String
    let title: String
    let detail: String
    var tint = WorkbenchTheme.warning

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("PingFangSC-Medium", size: 11))
                    .foregroundStyle(WorkbenchTheme.text)
                Text(detail)
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(WorkbenchTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
    }
}

struct WorkbenchDetailOverlay<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(Color.black.opacity(0.42))
                .contentShape(Rectangle())
            content
                .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkbenchTheme.canvas.opacity(0.24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("编辑窗口")
        .transition(.opacity)
        .zIndex(20)
    }
}

struct WorkbenchEditorCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x3A3529), WorkbenchTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchLayout.cardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.46), radius: 34, x: 0, y: 20)
    }
}

struct WorkbenchSegmentSelector<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let accessibilityLabel: String
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.custom("PingFangSC-Medium", size: 12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(isSelected ? WorkbenchTheme.canvas : WorkbenchTheme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                        .background(isSelected ? WorkbenchTheme.text : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(WorkbenchTheme.panel.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                .stroke(WorkbenchTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct WorkbenchMenuPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let accessibilityLabel: String
    let label: (Option) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if selection == option {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(label(selection))
                    .font(.custom("PingFangSC-Medium", size: 12))
                    .foregroundColor(WorkbenchTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(WorkbenchTheme.accent)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .tint(WorkbenchTheme.text)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
        .background(WorkbenchTheme.raised)
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                .stroke(WorkbenchTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(label(selection))
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !eyebrow.isEmpty {
                Text(eyebrow)
                    .font(.custom("PingFangSC-Semibold", size: 9))
                    .tracking(1.8)
                    .foregroundStyle(WorkbenchTheme.accent)
            }
            Text(title)
                .font(.custom("PingFangSC-Semibold", size: 24).weight(.semibold))
                .foregroundStyle(WorkbenchTheme.text)
            if let detail {
                Text(detail)
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundStyle(WorkbenchTheme.secondary)
            }
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(WorkbenchTheme.accent)
                .frame(width: 44, height: 44)
                .background(WorkbenchTheme.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("PingFangSC-Semibold", size: 17).weight(.semibold))
                    .foregroundStyle(WorkbenchTheme.text)
                Text(message)
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundStyle(WorkbenchTheme.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .workbenchActionButton(.primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(18)
        .workbenchCard()
    }
}

struct PricePassportView: View {
    let quote: QuoteSnapshot
    var compact = false

    var body: some View {
        let passport = quote.passport
        let timezone = TimeZone(identifier: passport.marketTimeZoneIdentifier) ?? .current
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                StatusPill(text: passport.market.rawValue, tint: WorkbenchTheme.accent)
                StatusPill(text: passport.currency.rawValue)
                StatusPill(text: passport.priceType.rawValue, tint: passport.priceType == .preMarket ? WorkbenchTheme.warning : WorkbenchTheme.secondary)
                StatusPill(text: passport.session.rawValue, tint: sessionColor(passport.session))
                Spacer()
                StatusPill(text: passport.delayStatus.rawValue, tint: passport.delayStatus == .possiblyDelayed ? WorkbenchTheme.warning : WorkbenchTheme.secondary)
            }
            if compact {
                HStack(alignment: .top, spacing: 16) {
                    passportDatum("比较基准", passport.comparisonBasis, width: 150)
                    passportDatum("行情时间", DisplayFormat.dateTime(passport.quoteTime, timeZone: timezone), width: 185)
                    passportDatum("抓取时间", DisplayFormat.dateTime(passport.fetchedAt), width: 185)
                    passportDatum("数据来源", passport.source, width: 130)
                    Spacer(minLength: 0)
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                    GridRow {
                        passportLabel("比较基准")
                        passportValue(passport.comparisonBasis)
                    }
                    GridRow {
                        passportLabel("行情时间")
                        passportValue(DisplayFormat.dateTime(passport.quoteTime, timeZone: timezone))
                    }
                    GridRow {
                        passportLabel("抓取时间")
                        passportValue(DisplayFormat.dateTime(passport.fetchedAt))
                    }
                    GridRow {
                        passportLabel("数据来源")
                        passportValue(passport.source)
                    }
                }
            }
        }
        .padding(compact ? 10 : 12)
        .background(WorkbenchTheme.panel.opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous)
                .stroke(WorkbenchTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous))
    }

    private func passportDatum(_ label: String, _ value: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.custom("PingFangSC-Medium", size: 9))
                .foregroundStyle(WorkbenchTheme.muted)
            Text(value)
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundStyle(WorkbenchTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(width: width, alignment: .leading)
    }

    private func passportLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom("PingFangSC-Medium", size: 10))
            .foregroundStyle(WorkbenchTheme.muted)
            .frame(width: 52, alignment: .leading)
    }

    private func passportValue(_ text: String) -> some View {
        Text(text)
            .font(.custom("PingFangSC-Regular", size: 11))
            .foregroundStyle(WorkbenchTheme.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func sessionColor(_ session: TradingSession) -> Color {
        switch session {
        case .regular: return WorkbenchTheme.positive
        case .preMarket, .afterHours, .overnight: return WorkbenchTheme.warning
        case .unavailable: return WorkbenchTheme.muted
        default: return WorkbenchTheme.secondary
        }
    }
}
