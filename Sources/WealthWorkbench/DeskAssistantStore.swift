import Foundation
import SwiftUI

struct DeskChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String
    var skillIDs: [InvestmentSkillID] = []
    var createdAt = Date()
    var isStreaming = false
}

@MainActor
final class DeskAssistantStore: ObservableObject {
    @Published var isExpanded = false
    @Published var selectedSkill: InvestmentSkillID = .auto
    @Published var messages: [DeskChatMessage] = []
    @Published var draft = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?
    @Published private(set) var panelOffset: CGSize = .zero

    var spaceXAIClient = SpaceXAIClient()
    var openAIClient = OpenAIClient()
    private var streamTask: Task<Void, Never>?
    private let placementStore: AssistantPlacementPersisting

    init(placementStore: AssistantPlacementPersisting = AssistantPlacementFileStore()) {
        self.placementStore = placementStore
        if let saved = try? placementStore.load() {
            panelOffset = CGSize(width: saved.x, height: saved.y)
        }
    }

    var hasConversation: Bool { !messages.isEmpty }

    func toggle() {
        isExpanded.toggle()
    }

    func move(to offset: CGSize) {
        panelOffset = offset
    }

    func persistPlacement() {
        try? placementStore.save(
            AssistantPlacement(x: panelOffset.width, y: panelOffset.height)
        )
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            messages[index].isStreaming = false
            if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[index].text = "已停止生成。"
            }
        }
    }

    func clear() {
        stop()
        messages = []
        errorMessage = nil
        draft = ""
    }

    func send(store: AppStore, news: NewsStore) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        let provider = store.assistantProvider
        guard let apiKey = store.resolvedAssistantKey(for: provider) else {
            switch provider {
            case .openAI: errorMessage = OpenAIClientError.missingAPIKey.errorDescription
            case .spaceXAI: errorMessage = SpaceXAIClientError.missingAPIKey.errorDescription
            }
            return
        }

        errorMessage = nil
        draft = ""
        let skillIDs = InvestmentSkillRouter.resolve(
            query: text,
            selected: selectedSkill,
            hasHoldings: !store.data.holdings.isEmpty
        )
        messages.append(DeskChatMessage(role: .user, text: text, skillIDs: skillIDs))
        let assistantID = UUID()
        messages.append(DeskChatMessage(id: assistantID, role: .assistant, text: "", skillIDs: skillIDs, isStreaming: true))
        isStreaming = true

        let snapshot = Self.snapshot(store: store, news: news)
        let system = InvestmentSkillCatalog.compile(skillIDs: skillIDs)
            + "\n\n## 当前本机快照\n"
            + snapshot
        let history = messages.dropLast().suffix(12).map { item in
            AssistantMessage(role: item.role == .user ? "user" : "assistant", content: item.text)
        }
        let payload = [AssistantMessage(role: "system", content: system)] + history

        streamTask = Task { [spaceXAIClient, openAIClient] in
            do {
                var assembled = ""
                let stream: AsyncThrowingStream<String, Error>
                switch provider {
                case .openAI:
                    stream = openAIClient.stream(
                        apiKey: apiKey,
                        endpoint: store.openAIEndpoint,
                        messages: payload
                    )
                case .spaceXAI:
                    stream = spaceXAIClient.stream(apiKey: apiKey, messages: payload)
                }
                for try await delta in stream {
                    if Task.isCancelled { break }
                    assembled += delta
                    if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                        messages[index].text = assembled
                    }
                }
                let emptyError: Error = provider == .openAI ? OpenAIClientError.emptyOutput : SpaceXAIClientError.emptyOutput
                finish(id: assistantID, text: assembled, error: assembled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? emptyError : nil)
            } catch is CancellationError {
                finish(id: assistantID, text: nil, error: nil)
            } catch {
                finish(id: assistantID, text: nil, error: error)
            }
        }
    }

    func applyPrompt(_ text: String, skill: InvestmentSkillID? = nil, store: AppStore, news: NewsStore) {
        if let skill {
            selectedSkill = skill
        }
        draft = text
        send(store: store, news: news)
    }

    static func snapshot(store: AppStore, news: NewsStore) -> String {
        DeskSnapshotBuilder.make(
            now: store.timeHealth.correctedNow,
            settings: store.data.settings,
            summary: store.summary(),
            holdings: store.holdingMetrics(),
            failures: store.quoteFailures,
            cash: store.data.cash,
            events: store.marketCalendarEvents,
            news: news.items,
            benchmarks: Benchmark.defaults.map { ($0, store.quotes[$0.key], store.quoteFailures[$0.key]) },
            providerStatus: store.providerStatus,
            lastRefreshAt: store.lastRefreshAt,
            timeHealth: store.timeHealth,
            exchangeRates: store.exchangeRates,
            calendarUpdatedAt: store.marketCalendarUpdatedAt,
            calendarFailures: store.marketCalendarFailures
        )
    }

    private func finish(id: UUID, text: String?, error: Error?) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].isStreaming = false
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[index].text = text
            } else if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[index].text = error == nil ? "已停止生成。" : "暂无数据"
            }
        }
        isStreaming = false
        streamTask = nil
        if let error, !(error is CancellationError) {
            errorMessage = error.localizedDescription
        }
    }
}
