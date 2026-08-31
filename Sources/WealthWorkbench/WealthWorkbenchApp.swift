import SwiftUI

@main
struct WealthWorkbenchApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("AUREL") {
            WorkbenchRootView()
                .environmentObject(store)
                .font(.custom("PingFangSC-Regular", size: 13))
                .tint(WorkbenchTheme.accent)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新行情") { Task { await store.refreshQuotes() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

struct WorkbenchRootView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var newsStore = NewsStore()
    @State private var selection: AppSection = .overview
    @State private var showingNotice = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requested: AppSection?
        if let marker = arguments.firstIndex(of: "--section"), arguments.indices.contains(marker + 1) {
            let key = arguments[marker + 1]
            requested = AppSection.allCases.first { section in
                section.rawValue == key || String(describing: section) == key
            }
        } else {
            requested = nil
        }
        _selection = State(initialValue: requested ?? .overview)
    }

    var body: some View {
        ZStack {
            WorkbenchBackdrop()

            VStack(spacing: 0) {
                WorkbenchTopBar(selection: $selection)
                    .environmentObject(store)
                detail
                    .id(selection)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: selection)
        .task {
            await store.refreshQuotes()
            while !Task.isCancelled {
                let seconds = max(30, store.data.settings.refreshIntervalSeconds)
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                await store.refreshQuotes()
            }
        }
        .task {
            await newsStore.refresh()
        }
        .onChange(of: store.notice) { value in showingNotice = value != nil }
        .alert("AUREL", isPresented: $showingNotice) {
            Button("知道了") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .overview: OverviewView { selection = .holdings }
        case .news: FinancialNewsView(news: newsStore)
        case .review: PortfolioReviewView()
        case .holdings: HoldingsView()
        case .calendar: EventCalendarView()
        case .settings: SettingsView()
        }
    }
}

private struct WorkbenchTopBar: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: AppSection

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                brand
                    .frame(width: 248, alignment: .leading)
                Spacer(minLength: 540)
                connectionStatus
                    .frame(width: 286, alignment: .trailing)
            }

            HStack(spacing: 3) {
                ForEach(AppSection.allCases) { section in
                    TopNavigationItem(
                        section: section,
                        isSelected: selection == section,
                        action: { selection = section }
                    )
                }
            }
            .padding(4)
            .background(WorkbenchTheme.panel.opacity(0.88))
            .overlay(Capsule().stroke(WorkbenchTheme.border, lineWidth: 1))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 18)
        .padding(.trailing, 18)
        .frame(height: WorkbenchLayout.topBarHeight)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(WorkbenchTheme.chrome.opacity(0.78))
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(WorkbenchTheme.border).frame(height: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            AurelMark()
                .frame(width: 34, height: 34)
                .shadow(color: WorkbenchTheme.accent.opacity(0.16), radius: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("AUREL")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(WorkbenchTheme.text)
                Text("PRIVATE CAPITAL DESK")
                    .font(.custom("PingFangSC-Semibold", size: 7))
                    .tracking(1.35)
                    .foregroundStyle(WorkbenchTheme.muted)
            }
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.quotes.isEmpty ? WorkbenchTheme.warning : WorkbenchTheme.negative)
                        .frame(width: 6, height: 6)
                    Text(store.isRefreshing ? "正在刷新" : store.providerStatus)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Image(systemName: store.timeHealth.isSkewed ? "clock.badge.exclamationmark" : "clock")
                    Text(Self.timeFormatter.string(from: store.timeHealth.correctedNow))
                        .monospacedDigit()
                }
                .foregroundStyle(store.timeHealth.isSkewed ? WorkbenchTheme.warning : WorkbenchTheme.muted)
            }
            .font(.custom("PingFangSC-Regular", size: 9))
            .foregroundStyle(WorkbenchTheme.secondary)

            Button {
                Task { await store.refreshQuotes() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(store.isRefreshing ? .degrees(180) : .zero)
            }
            .workbenchActionButton(.icon)
            .disabled(store.isRefreshing)
            .help("刷新行情 ⌘R")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return value
    }()
}

private struct TopNavigationItem: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(section.rawValue)
                    .font(.custom("PingFangSC-Medium", size: 11))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? WorkbenchTheme.canvas : WorkbenchTheme.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32, maxHeight: 32)
            .background(
                isSelected
                    ? WorkbenchTheme.text
                    : (isHovered ? WorkbenchTheme.raised : Color.clear)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
