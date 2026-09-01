import SwiftUI

enum AssistantDragMotion {
    static let activationDistance: CGFloat = 4
    static let coordinateSpaceName = "aurel-assistant-overlay"

    static func proposedOffset(base: CGSize, translation: CGSize) -> CGSize {
        CGSize(
            width: base.width + translation.width,
            height: base.height + translation.height
        )
    }

    static func isDrag(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= activationDistance
    }
}

struct AssistantDragSession {
    private(set) var origin: CGSize?
    private(set) var preview: CGSize?

    mutating func update(
        base: CGSize,
        translation: CGSize,
        clamp: (CGSize) -> CGSize
    ) {
        if origin == nil { origin = base }
        preview = clamp(
            AssistantDragMotion.proposedOffset(
                base: origin ?? base,
                translation: translation
            )
        )
    }

    mutating func finish(
        base: CGSize,
        translation: CGSize,
        clamp: (CGSize) -> CGSize
    ) -> CGSize {
        let destination = clamp(
            AssistantDragMotion.proposedOffset(
                base: origin ?? base,
                translation: translation
            )
        )
        origin = nil
        preview = nil
        return destination
    }
}

struct DeskAssistantOverlay: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var news: NewsStore
    @ObservedObject var desk: DeskAssistantStore
    let onOpenSettings: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                Color.clear.allowsHitTesting(false)
                if desk.isExpanded {
                    DeskAssistantPanel(
                        news: news,
                        desk: desk,
                        clampOffset: { clamp($0, in: proxy.size, element: CGSize(width: 460, height: 620)) },
                        onOpenSettings: onOpenSettings
                    )
                    .frame(width: 460, height: 620)
                } else {
                    DeskAssistantFab(
                        desk: desk,
                        clampOffset: { clamp($0, in: proxy.size, element: CGSize(width: 154, height: 46)) },
                        action: { desk.isExpanded = true }
                    )
                }
            }
            .padding(.trailing, 18)
            .padding(.bottom, 18)
            .coordinateSpace(name: AssistantDragMotion.coordinateSpaceName)
        }
    }

    private func clamp(_ proposed: CGSize, in container: CGSize, element: CGSize) -> CGSize {
        let horizontalTravel = max(0, container.width - element.width - 36)
        let verticalTravel = max(0, container.height - element.height - 36)
        return CGSize(
            width: min(0, max(-horizontalTravel, proposed.width)),
            height: min(0, max(-verticalTravel, proposed.height))
        )
    }
}

private struct DeskAssistantFab: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var desk: DeskAssistantStore
    let clampOffset: (CGSize) -> CGSize
    let action: () -> Void
    @State private var hovered = false
    @State private var dragSession = AssistantDragSession()

    private var isDragging: Bool {
        dragSession.preview != nil
    }

    private var displayOffset: CGSize {
        dragSession.preview ?? clampOffset(desk.panelOffset)
    }

    private var dragGesture: some Gesture {
        // Keep high-frequency samples in local view state and commit once at the end.
        // The stable parent coordinate space prevents the moving view from shifting its own pointer origin.
        DragGesture(
            minimumDistance: AssistantDragMotion.activationDistance,
            coordinateSpace: .named(AssistantDragMotion.coordinateSpaceName)
        )
        .onChanged { value in
            dragSession.update(
                base: desk.panelOffset,
                translation: value.translation,
                clamp: clampOffset
            )
        }
        .onEnded { value in
            let destination = dragSession.finish(
                base: desk.panelOffset,
                translation: value.translation,
                clamp: clampOffset
            )
            desk.move(to: destination)
            desk.persistPlacement()
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            AurelMark()
                .frame(width: 27, height: 27)
                .shadow(color: WorkbenchTheme.accent.opacity(0.18), radius: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text("AUREL Desk")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.35)
                Text(store.assistantKeyAvailable ? store.assistantProvider.model : "等待配置")
                    .font(.custom("PingFangSC-Regular", size: 8))
                    .foregroundStyle(store.assistantKeyAvailable ? WorkbenchTheme.muted : WorkbenchTheme.warning)
            }
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WorkbenchTheme.accent)
        }
        .foregroundStyle(WorkbenchTheme.text)
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .frame(height: 46)
        .background(
            LinearGradient(
                colors: [WorkbenchTheme.raised, WorkbenchTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(Capsule().stroke(hovered && !isDragging ? WorkbenchTheme.accent.opacity(0.62) : WorkbenchTheme.strongBorder, lineWidth: 1))
        .clipShape(Capsule())
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.32), radius: 12, y: 7)
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .highPriorityGesture(dragGesture)
        .onHover { hovered = $0 }
        .help("点击打开 · 拖动移动 · ⌘L")
        .accessibilityLabel("打开 AUREL 投资助手")
        .accessibilityHint("可以拖动到窗口内的其他位置")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .allowsHitTesting(true)
        // Apply position last so the rendered capsule and the complete hit region move together.
        .offset(x: displayOffset.width, y: displayOffset.height)
    }
}

private struct DeskAssistantPanel: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var news: NewsStore
    @ObservedObject var desk: DeskAssistantStore
    let clampOffset: (CGSize) -> CGSize
    let onOpenSettings: () -> Void
    @State private var dragSession = AssistantDragSession()

    private var displayOffset: CGSize {
        dragSession.preview ?? clampOffset(desk.panelOffset)
    }

    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: AssistantDragMotion.activationDistance,
            coordinateSpace: .named(AssistantDragMotion.coordinateSpaceName)
        )
        .onChanged { value in
            dragSession.update(
                base: desk.panelOffset,
                translation: value.translation,
                clamp: clampOffset
            )
        }
        .onEnded { value in
            let destination = dragSession.finish(
                base: desk.panelOffset,
                translation: value.translation,
                clamp: clampOffset
            )
            desk.move(to: destination)
            desk.persistPlacement()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            skillStrip
            contextStatusBar
            Divider().overlay(WorkbenchTheme.border)
            conversation
            Divider().overlay(WorkbenchTheme.border)
            composer
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(WorkbenchTheme.strongBorder, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.clear, WorkbenchTheme.accent.opacity(0.7), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 240, height: 1)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.54), radius: 38, x: 0, y: 22)
        .allowsHitTesting(true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("投资助手")
        .offset(x: displayOffset.width, y: displayOffset.height)
    }

    private var panelBackground: some View {
        ZStack {
            WorkbenchTheme.panel
            LinearGradient(
                colors: [Color(hex: 0x3B3424, alpha: 0.72), .clear],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.72, y: 0.46)
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AurelMark()
                .frame(width: 30, height: 30)
                .shadow(color: WorkbenchTheme.accent.opacity(0.14), radius: 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("AUREL Desk")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .tracking(0.6)
                    Text("READ ONLY")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .tracking(0.65)
                        .foregroundStyle(WorkbenchTheme.accent)
                        .padding(.horizontal, 5)
                        .frame(height: 15)
                        .background(WorkbenchTheme.accent.opacity(0.09))
                        .overlay(Capsule().stroke(WorkbenchTheme.accent.opacity(0.20), lineWidth: 1))
                        .clipShape(Capsule())
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.assistantKeyAvailable ? WorkbenchTheme.negative : WorkbenchTheme.warning)
                        .frame(width: 5, height: 5)
                    Text(store.assistantKeyAvailable ? "\(store.assistantProvider.displayName) · \(store.assistantProvider.model)" : "\(store.assistantProvider.displayName) · 未配置 API Key")
                        .font(.custom("PingFangSC-Regular", size: 9))
                        .foregroundStyle(store.assistantKeyAvailable ? WorkbenchTheme.muted : WorkbenchTheme.warning)
                }
            }
            .foregroundStyle(WorkbenchTheme.text)
            Spacer(minLength: 8)
            Button { desk.clear() } label: { Image(systemName: "square.and.pencil") }
                .workbenchActionButton(.icon)
                .disabled(desk.isStreaming && !desk.hasConversation)
                .help("新对话")
                .accessibilityLabel("新对话")
            Button { desk.isExpanded = false } label: { Image(systemName: "chevron.down") }
                .workbenchActionButton(.icon)
                .help("收起")
                .accessibilityLabel("收起投资助手")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
    }

    private var skillStrip: some View {
        HStack(spacing: 7) {
            Button {
                desk.selectedSkill = .auto
            } label: {
                Label("智能路由", systemImage: "wand.and.stars")
                    .font(.custom("PingFangSC-Medium", size: 10))
                    .foregroundStyle(desk.selectedSkill == .auto ? WorkbenchTheme.canvas : WorkbenchTheme.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(desk.selectedSkill == .auto ? WorkbenchTheme.text : WorkbenchTheme.raised.opacity(0.72))
                    .overlay(Capsule().stroke(desk.selectedSkill == .auto ? WorkbenchTheme.text.opacity(0.7) : WorkbenchTheme.border, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("自动组合 1–3 个互补研究能力")

            Menu {
                ForEach(InvestmentSkillCatalog.selectable) { skill in
                    Button {
                        desk.selectedSkill = skill
                    } label: {
                        if desk.selectedSkill == skill {
                            Label(skill.title, systemImage: "checkmark")
                        } else {
                            Text(skill.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scope")
                    Text(desk.selectedSkill == .auto ? "指定技能" : desk.selectedSkill.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .font(.custom("PingFangSC-Medium", size: 10))
                .foregroundStyle(desk.selectedSkill == .auto ? WorkbenchTheme.secondary : WorkbenchTheme.accent)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(WorkbenchTheme.raised.opacity(0.72))
                .overlay(Capsule().stroke(desk.selectedSkill == .auto ? WorkbenchTheme.border : WorkbenchTheme.accent.opacity(0.34), lineWidth: 1))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .help(desk.selectedSkill == .auto ? "手动锁定一个研究技能" : desk.selectedSkill.promptHint)

            Spacer(minLength: 4)
            Text(desk.selectedSkill == .auto ? "自动组合最多 3 项" : "手动锁定")
                .font(.custom("PingFangSC-Regular", size: 9))
                .foregroundStyle(WorkbenchTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var contextStatusBar: some View {
        let receipt = desk.lastContextReceipt ?? DeskContextReceipt.make(
            holdings: store.holdingMetrics(),
            providerStatus: store.providerStatus,
            generatedAt: store.timeHealth.correctedNow,
            lastRefreshAt: store.lastRefreshAt
        )
        let tint = receipt.holdingCount == 0
            ? WorkbenchTheme.warning
            : (receipt.hasCompleteQuotes ? WorkbenchTheme.negative : WorkbenchTheme.warning)
        return HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(desk.lastContextReceipt == nil ? "持仓上下文可用" : "本轮已发送")
                .font(.custom("PingFangSC-Medium", size: 9))
                .foregroundStyle(tint)
            Text("\(receipt.holdingCount) 项持仓 · \(receipt.quotedHoldingCount) 项行情")
                .font(.custom("PingFangSC-Regular", size: 9))
                .foregroundStyle(WorkbenchTheme.secondary)
                .monospacedDigit()
            if receipt.estimatedHoldingCount > 0 {
                Text("· \(receipt.estimatedHoldingCount) 项估算")
                    .font(.custom("PingFangSC-Regular", size: 9))
                    .foregroundStyle(WorkbenchTheme.warning)
            }
            Spacer(minLength: 6)
            Text(receipt.providerStatus)
                .font(.custom("PingFangSC-Regular", size: 8))
                .foregroundStyle(WorkbenchTheme.muted)
                .lineLimit(1)
            if let refreshedAt = receipt.lastRefreshAt {
                Text(contextTime(refreshedAt))
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.muted)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(WorkbenchTheme.canvas.opacity(0.46))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("持仓上下文")
        .accessibilityValue("\(receipt.holdingCount) 项持仓，\(receipt.quotedHoldingCount) 项行情")
    }

    private func contextTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var conversation: some View {
        if !store.assistantKeyAvailable {
            setupCard
        } else if desk.messages.isEmpty {
            emptyCard
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(desk.messages) { message in
                            DeskBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: desk.messages.last?.text) { _ in
                    if let id = desk.messages.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(WorkbenchTheme.accent.opacity(0.10))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("连接你的 AI 服务")
                        .font(.custom("PingFangSC-Semibold", size: 16))
                        .foregroundStyle(WorkbenchTheme.text)
                    Text("选择服务后，在通用设置里保存对应 Key")
                        .font(.custom("PingFangSC-Regular", size: 10))
                        .foregroundStyle(WorkbenchTheme.muted)
                }
            }

            WorkbenchSegmentSelector(
                selection: assistantProviderBinding,
                options: AssistantProvider.allCases,
                accessibilityLabel: "AI 服务",
                label: { "\($0.displayName) · \($0.model)" }
            )

            Text("对话时会把当前持仓快照发送给 \(store.assistantProvider.displayName)。Key 写入应用专属本地文件，权限 0600，不使用钥匙串；AUREL 仍保持只读，不连接交易接口。")
                .font(.custom("PingFangSC-Regular", size: 11))
                .foregroundStyle(WorkbenchTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("前往通用设置") {
                desk.isExpanded = false
                onOpenSettings()
            }
            .workbenchActionButton(.primary)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var assistantProviderBinding: Binding<AssistantProvider> {
        Binding(
            get: { store.assistantProvider },
            set: { provider in
                desk.clear()
                store.setAssistantProvider(provider)
            }
        )
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("你的只读投资研究台")
                    .font(.custom("PingFangSC-Semibold", size: 17))
                    .foregroundStyle(WorkbenchTheme.text)
                Text("基于本机持仓、行情护照、事件与资讯线索。缺数就写暂无数据，不编造价格。")
                    .font(.custom("PingFangSC-Regular", size: 11))
                    .foregroundStyle(WorkbenchTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                capability("shield.checkered", "只读")
                capability("clock", "时段校验")
                capability("doc.text.magnifyingglass", "投研纪律")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("建议从这里开始")
                    .font(.custom("PingFangSC-Medium", size: 10))
                    .foregroundStyle(WorkbenchTheme.muted)
                promptButton("审视当前组合", skill: .portfolioReview)
                promptButton("最大持仓的财务质量和估值站得住吗？", skill: .financialHealth)
                promptButton("给最大持仓写一份空方红队", skill: .bearCase)
                promptButton("未来 7 日宏观和财报会怎么传到持仓？", skill: .macroEvent)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func capability(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WorkbenchTheme.accent)
            Text(title)
                .font(.custom("PingFangSC-Medium", size: 9))
                .foregroundStyle(WorkbenchTheme.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 25)
        .background(WorkbenchTheme.raised.opacity(0.62))
        .overlay(Capsule().stroke(WorkbenchTheme.border, lineWidth: 1))
        .clipShape(Capsule())
    }

    private func promptButton(_ title: String, skill: InvestmentSkillID) -> some View {
        Button {
            desk.applyPrompt(title, skill: skill, store: store, news: news)
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.custom("PingFangSC-Medium", size: 11))
                    .foregroundStyle(WorkbenchTheme.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.accent)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(WorkbenchTheme.raised.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WorkbenchTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = desk.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.custom("PingFangSC-Regular", size: 10))
                    .foregroundStyle(WorkbenchTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("问组合、某只持仓或一次财报…", text: $desk.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.custom("PingFangSC-Regular", size: 12))
                    .foregroundStyle(WorkbenchTheme.text)
                    .lineLimit(1...4)
                    .disabled(!store.assistantKeyAvailable || desk.isStreaming)
                    .onSubmit { desk.send(store: store, news: news) }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(WorkbenchTheme.raised.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous)
                            .stroke(WorkbenchTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.controlRadius, style: .continuous))
                if desk.isStreaming {
                    Button { desk.stop() } label: { Image(systemName: "stop.fill") }
                        .workbenchActionButton(.destructiveIcon)
                        .help("停止")
                } else {
                    Button { desk.send(store: store, news: news) } label: { Image(systemName: "arrow.up") }
                        .workbenchActionButton(.primary)
                        .disabled(desk.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.assistantKeyAvailable)
                        .help("发送")
                        .accessibilityLabel("发送")
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                Text("发送持仓快照至 \(store.assistantProvider.displayName) · AUREL 不执行交易")
            }
            .font(.custom("PingFangSC-Regular", size: 9))
            .foregroundStyle(WorkbenchTheme.muted)
        }
        .padding(12)
        .background(WorkbenchTheme.panel.opacity(0.82))
    }
}

private struct DeskBubble: View {
    let message: DeskChatMessage

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantCard
        }
    }

    private var userBubble: some View {
        Text(displayedText)
            .font(.custom("PingFangSC-Regular", size: 12))
            .foregroundStyle(WorkbenchTheme.canvas)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(WorkbenchTheme.text)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .frame(maxWidth: 330, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("我")
            .accessibilityValue(displayedText)
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !message.skillIDs.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "scope")
                        .font(.system(size: 9, weight: .semibold))
                    Text(message.skillIDs.map(\.title).joined(separator: " · "))
                }
                .font(.custom("PingFangSC-Medium", size: 9))
                .foregroundStyle(WorkbenchTheme.accent)
            }
            if message.isStreaming && message.text.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).tint(WorkbenchTheme.accent)
                    Text("正在分析本机快照…")
                        .font(.custom("PingFangSC-Regular", size: 11))
                        .foregroundStyle(WorkbenchTheme.secondary)
                }
            } else {
                AssistantResponseView(text: displayedText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchTheme.raised.opacity(0.48))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(WorkbenchTheme.accent.opacity(0.72))
                .frame(width: 2)
                .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(WorkbenchTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("助手")
        .accessibilityValue(displayedText)
    }

    private var displayedText: String {
        if message.isStreaming && message.text.isEmpty { return "正在分析…" }
        return message.text
    }
}

private struct AssistantResponseView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(AssistantResponseParser.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let value):
                    Text(value)
                        .font(.custom("PingFangSC-Semibold", size: 13))
                        .foregroundStyle(WorkbenchTheme.text)
                        .padding(.top, 2)
                case .paragraph(let value):
                    DeskMarkdownText(value)
                        .font(.custom("PingFangSC-Regular", size: 12))
                        .foregroundStyle(WorkbenchTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullets(let values):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Circle()
                                    .fill(WorkbenchTheme.accent)
                                    .frame(width: 4, height: 4)
                                DeskMarkdownText(value)
                                    .font(.custom("PingFangSC-Regular", size: 12))
                                    .foregroundStyle(WorkbenchTheme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .table(let headers, let rows):
                    DeskDataTable(headers: headers, rows: rows)
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct DeskMarkdownText: View {
    private let source: String
    private let attributed: AttributedString?

    init(_ source: String) {
        self.source = source
        self.attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
    }

    var body: some View {
        if let attributed {
            Text(attributed)
        } else {
            Text(source)
        }
    }
}

private struct DeskDataTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, value in
                        cell(value, header: true, alternate: false)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            cell(value, header: false, alternate: rowIndex.isMultiple(of: 2))
                        }
                    }
                }
            }
        }
        .background(WorkbenchTheme.panel.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WorkbenchTheme.strongBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("投研数据表")
    }

    private func cell(_ value: String, header: Bool, alternate: Bool) -> some View {
        Text(value)
            .font(.custom(header ? "PingFangSC-Semibold" : "PingFangSC-Regular", size: header ? 10 : 11))
            .foregroundStyle(header ? WorkbenchTheme.accent : WorkbenchTheme.text)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 78, maxWidth: 148, minHeight: header ? 30 : 34, alignment: .leading)
            .padding(.horizontal, 9)
            .background(
                header
                    ? WorkbenchTheme.accent.opacity(0.09)
                    : (alternate ? WorkbenchTheme.raised.opacity(0.42) : Color.clear)
            )
            .overlay(alignment: .trailing) {
                Rectangle().fill(WorkbenchTheme.border).frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(WorkbenchTheme.border).frame(height: 1)
            }
    }
}
