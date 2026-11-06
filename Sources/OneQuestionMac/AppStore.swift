import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OneQuestionCore

@MainActor final class AppStore: ObservableObject {
    @Published var questions: [Question] = []
    @Published var attempts: [Attempt] = []
    @Published var selectedID: String?
    @Published var draft = ""
    @Published var currentAttemptID: String?
    @Published var selectedDeck = "全部题库"
    @Published var reviewOnly = false
    @Published var randomOrder = false
    @Published var pinned = false
    @Published var isEvaluating = false
    @Published var isImporting = false
    @Published var importProgress = ""
    @Published var isAnalyzingImport = false
    @Published var importAIProgress = ""
    @Published var importAIError: String?
    @Published var importDocument: ImportDocument?
    @Published var showImportPreview = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var settings = AISettings()
    private var database: Database?
    private var drafts: [String: String] = [:]
    private var draftTask: Task<Void, Never>?
    private var evaluationTask: Task<Void, Never>?
    private var evaluationID: UUID?
    private var importTask: Task<Void, Never>?
    private var importAnalysisTask: Task<Void, Never>?
    private var importAnalysisID: UUID?
    private var settingsObserver: NSObjectProtocol?
    private var sessionKeys: [String: String] = [:]
    private var unconfirmedCredentials = Set<String>()
    let dataDirectory: URL

    init() {
        if let custom = ProcessInfo.processInfo.environment["ONEQUESTION_DATA_DIR"] {
            dataDirectory = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OneQuestion", isDirectory: true)
        }
        do {
            let db = try Database(url: dataDirectory.appendingPathComponent("questions.sqlite3")); database = db
            if try db.get(Bool.self, for: "initialized") != true {
                try db.save(questions: Samples.questions); try db.set(true, for: "initialized")
            }
            questions = try db.questions(); attempts = try db.attempts()
            settings = try db.get(AISettings.self, for: "ai-settings") ?? AISettings()
            drafts = try db.get([String: String].self, for: "drafts") ?? [:]
            let restored = try db.get(String.self, for: "selected-question")
            selectedID = questions.contains(where: { $0.id == restored }) ? restored : questions.first?.id
            draft = selectedID.flatMap { drafts[$0] } ?? ""
        } catch { errorMessage = "本地数据初始化失败：\(error.localizedDescription)" }
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("OneQuestionAISettingsChanged"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reloadAISettings() }
            }
    }
    var decks: [String] { Array(Set(questions.map(\.deck))).sorted() }
    var reviewIDs: Set<String> {
        var seen = Set<String>(), result = Set<String>()
        for attempt in attempts where seen.insert(attempt.question.id).inserted {
            if attempt.needsReview { result.insert(attempt.question.id) }
        }
        return result
    }
    var filteredQuestions: [Question] {
        questions.filter { (selectedDeck == "全部题库" || $0.deck == selectedDeck) && (!reviewOnly || reviewIDs.contains($0.id)) }
    }
    var currentAttempt: Attempt? { attempts.first { $0.id == currentAttemptID } }
    var currentQuestion: Question? {
        if let attempt = currentAttempt, attempt.question.id == selectedID { return attempt.question }
        return questions.first { $0.id == selectedID }
    }
    var isSubmitted: Bool { currentAttempt != nil }
    var position: String {
        guard let index = filteredQuestions.firstIndex(where: { $0.id == selectedID }) else { return "0 / \(filteredQuestions.count)" }
        return "\(index + 1) / \(filteredQuestions.count)"
    }
    func choose(_ id: String?) {
        guard !isEvaluating else { return }
        persistDraftNow(); selectedID = id; currentAttemptID = nil; draft = id.flatMap { drafts[$0] } ?? ""
        if let id { do { try database?.set(id, for: "selected-question") } catch { errorMessage = error.localizedDescription } }
    }
    func updateFilter() {
        if !filteredQuestions.contains(where: { $0.id == selectedID }) { choose(filteredQuestions.first?.id) }
    }
    func next() {
        guard !isEvaluating else { return }
        let pool = filteredQuestions
        guard !pool.isEmpty else { choose(nil); return }
        if randomOrder, pool.count > 1 { choose(pool.filter { $0.id != selectedID }.randomElement()?.id) }
        else { let index = pool.firstIndex { $0.id == selectedID } ?? -1; choose(pool[(index + 1) % pool.count].id) }
    }
    func queueDraftSave() {
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            self?.persistDraftNow()
        }
    }
    func persistDraftNow() {
        draftTask?.cancel()
        guard let id = selectedID else { return }
        drafts[id] = draft
        do { try database?.set(drafts, for: "drafts") } catch { errorMessage = "草稿保存失败：\(error.localizedDescription)" }
    }
    func submit() {
        guard !isEvaluating, currentAttempt == nil, let question = currentQuestion, !draft.trimmed.isEmpty else { return }
        guard draft.count <= 50_000 else { errorMessage = "单次回答请控制在 50000 字以内。"; return }
        let attempt = Attempt(question: question, answer: draft)
        do {
            guard let database else { throw AppFailure("本地数据库不可用，无法保存回答。") }
            try database.save(attempt: attempt); attempts.insert(attempt, at: 0); currentAttemptID = attempt.id; persistDraftNow()
            if settings.enabled && question.canEvaluate { evaluateCurrent() }
        } catch { errorMessage = error.localizedDescription }
    }
    func evaluateCurrent() {
        guard !isEvaluating, let attempt = currentAttempt else { return }
        guard settings.enabled else { errorMessage = "请先在设置中启用并配置 AI 评价。"; return }
        do { _ = try settings.requestURL() } catch { errorMessage = error.localizedDescription; return }
        isEvaluating = true
        let taskID = UUID(); evaluationID = taskID
        let configuration = settings
        evaluationTask = Task { [weak self] in
            defer { if self?.evaluationID == taskID { self?.isEvaluating = false; self?.evaluationTask = nil } }
            do {
                guard let self else { return }
                let key = try await self.apiKey(for: configuration)
                try Task.checkCancellation()
                let result = try await AIClient.evaluate(question: attempt.question, answer: attempt.answer, settings: configuration, apiKey: key)
                guard !Task.isCancelled, self.evaluationID == taskID else { return }
                var updated = attempt; updated.evaluation = result; updated.selfRating = nil
                try self.database?.save(attempt: updated)
                if let i = self.attempts.firstIndex(where: { $0.id == attempt.id }) { self.attempts[i] = updated }
            } catch {
                guard let self, self.evaluationID == taskID else { return }
                if !Task.isCancelled { self.errorMessage = error.localizedDescription }
            }
        }
    }
    func cancelEvaluation() { evaluationTask?.cancel(); evaluationTask = nil; evaluationID = nil; isEvaluating = false }
    func rate(_ rating: String) {
        guard !isEvaluating, var attempt = currentAttempt else { return }
        attempt.selfRating = rating
        do {
            try database?.save(attempt: attempt)
            if let i = attempts.firstIndex(where: { $0.id == attempt.id }) { attempts[i] = attempt }
        } catch { errorMessage = error.localizedDescription }
    }
    func rewrite() { guard !isEvaluating else { return }; currentAttemptID = nil }
    func togglePin() {
        pinned.toggle()
        NSApp.windows.first(where: { $0.identifier?.rawValue == "practice-window" })?.level = pinned ? .floating : .normal
    }
    func saveSettings(_ value: AISettings, key: String, withoutKey: Bool) async throws -> (message: String, warning: Bool) {
        let prepared = try value.preparedForSaving(previous: settings, suppliedKey: key, withoutKey: withoutKey)
        guard let database else { throw AppFailure("本地数据库不可用。") }
        var warning: String?
        if !key.trimmed.isEmpty, !withoutKey, let account = prepared.credentialAccount {
            let supplied = key.trimmed
            sessionKeys[account] = supplied
            do {
                try await BackgroundOperation.run(timeoutMessage: "钥匙串在 8 秒内未确认保存。") {
                    try Keychain.create(supplied, account: account)
                }
                unconfirmedCredentials.remove(account)
            } catch {
                unconfirmedCredentials.insert(account); warning = error.localizedDescription
            }
        }
        try database.set(prepared, for: "ai-settings"); settings = prepared
        if let account = prepared.credentialAccount, unconfirmedCredentials.contains(account) {
            return ("设置已生效。\(warning ?? "密钥尚未确认写入钥匙串。")当前运行可使用该密钥，重启后可能需要重新填写。", true)
        }
        return ("设置已保存并生效。" + (withoutKey ? "此接口不发送 API 密钥。" : key.trimmed.isEmpty ? "已保留原密钥。" : "新密钥已存入钥匙串。"), false)
    }
    private func apiKey(for configuration: AISettings) async throws -> String {
        guard let account = configuration.credentialAccount else { return "" }
        if let cached = sessionKeys[account] { return cached }
        let key = try await BackgroundOperation.run(timeoutMessage: "钥匙串读取超时。请在 AI 设置中重新输入密钥并保存；应用不会覆盖已有题目。") {
            try Keychain.read(account: account)
        }
        guard !key.isEmpty else { throw AppFailure("未找到此接口的密钥，请在 AI 设置中重新输入并保存。") }
        sessionKeys[account] = key; return key
    }
    func reloadAISettings() {
        do {
            if let value = try database?.get(AISettings.self, for: "ai-settings"), value != settings {
                settings = value; notice = "AI 配置已更新：\(value.model)。"
            }
        } catch { errorMessage = "读取 AI 配置失败：\(error.localizedDescription)" }
    }
    func saveQuestion(_ question: Question) throws {
        guard !question.title.trimmed.isEmpty else { throw AppFailure("请填写题目。") }
        guard question.criteria.allSatisfy({ !$0.text.trimmed.isEmpty && (1...100).contains($0.weight) }) else { throw AppFailure("评分要点不能为空，权重为 1–100。") }
        guard !questions.contains(where: { $0.id != question.id && $0.fingerprint == question.fingerprint }) else { throw AppFailure("已存在同名题目，请编辑原题或调整题目名称。") }
        guard let database else { throw AppFailure("本地数据库不可用。") }
        try database.save(questions: [question]); questions = try database.questions()
        if selectedID == nil { choose(question.id) }
    }
    func deleteQuestion(_ question: Question) {
        guard !isEvaluating else { return }
        do {
            try database?.deleteQuestion(id: question.id); questions = try database?.questions() ?? []
            if selectedID == question.id { choose(filteredQuestions.first?.id) }
        } catch { errorMessage = error.localizedDescription }
    }
    func openImportPanel() {
        guard !isImporting else { return }
        let panel = NSOpenPanel(); panel.title = "导入面试题库"; panel.prompt = "预览题库"
        panel.allowedContentTypes = [.pdf, .json, .commaSeparatedText, UTType(filenameExtension: "xlsx") ?? .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url { Task { @MainActor in self?.loadImport(url) } }
        }
    }
    func loadImport(_ url: URL) {
        guard !isImporting else { return }
        cancelImportAnalysis(); importAIError = nil
        isImporting = true; importProgress = "正在读取题库…"
        let access = url.startAccessingSecurityScopedResource()
        importTask = Task { [weak self] in
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
                self?.isImporting = false; self?.importProgress = ""; self?.importTask = nil
            }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try QuestionImporter.load(url: url) { [weak self] message in
                        Task { @MainActor in self?.importProgress = message }
                    }
                }
                let document = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                self?.importDocument = document; self?.showImportPreview = true
            } catch is CancellationError { self?.notice = "已取消题库导入，现有题目保持不变。" }
            catch { self?.errorMessage = error.localizedDescription }
        }
    }
    func cancelImport() { importProgress = "正在取消导入…"; importTask?.cancel() }
    func analyzeImport() {
        guard !isAnalyzingImport, let document = importDocument else { return }
        do { _ = try settings.requestURL() }
        catch { importAIError = error.localizedDescription; return }
        let configuration = settings, taskID = UUID()
        importAnalysisID = taskID; isAnalyzingImport = true; importAIError = nil
        importAIProgress = "正在请模型区分问题与原文答案…"
        importAnalysisTask = Task { [weak self] in
            defer {
                if self?.importAnalysisID == taskID {
                    self?.isAnalyzingImport = false; self?.importAIProgress = ""; self?.importAnalysisTask = nil
                }
            }
            do {
                guard let self else { return }
                let key = try await self.apiKey(for: configuration)
                try Task.checkCancellation()
                let result = try await AIImportAnalyzer.analyze(document: document, settings: configuration, apiKey: key) { [weak self] message in
                    Task { @MainActor in
                        guard self?.importAnalysisID == taskID else { return }
                        self?.importAIProgress = message
                    }
                }
                try Task.checkCancellation()
                guard self.importAnalysisID == taskID, self.showImportPreview,
                      self.importDocument?.id == document.id else { return }
                self.importDocument = result
            } catch is CancellationError { }
            catch {
                if self?.importAnalysisID == taskID { self?.importAIError = error.localizedDescription }
            }
        }
    }
    func cancelImportAnalysis() {
        importAnalysisTask?.cancel(); importAnalysisTask = nil; importAnalysisID = nil
        isAnalyzingImport = false; importAIProgress = ""
    }
    func prepareQuestionRepair(_ question: Question) {
        guard !isAnalyzingImport, !isImporting, !isEvaluating else { return }
        importDocument = ImportDocument(name: question.deck, rows: [ImportRow(line: 1, question: question)],
            notice: "AI 整理结果会先预览；确认后更新当前题目并保留历史作答。", sourceText: question.title + "\n" + question.referenceAnswer,
            repairTarget: question)
        importAIError = nil; showImportPreview = true; analyzeImport()
    }
    func updateImportRow(_ rowID: UUID, question: Question) {
        guard var document = importDocument, let index = document.rows.firstIndex(where: { $0.id == rowID }) else { return }
        document.rows[index].question = question
        document.rows[index].warning = question.canEvaluate ? nil : "缺少参考答案，暂不支持自动评价"
        importDocument = document
    }
    func duplicate(for question: Question) -> Question? {
        questions.first(where: { $0.id == question.id }) ?? questions.first(where: { $0.fingerprint == question.fingerprint })
    }
    func commitImport(replaceExisting: Bool) {
        guard !isAnalyzingImport, let document = importDocument, let database else { return }
        do {
            var byID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
            var byTitle = Dictionary(questions.map { ($0.fingerprint, $0.id) }, uniquingKeysWith: { first, _ in first })
            var selected: [String: Question] = [:]; var added = 0, updated = 0, skipped = 0
            for row in document.rows {
                guard var q = row.question else { continue }
                let existing = byID[q.id]?.id ?? byTitle[q.fingerprint]
                if let existing {
                    if !replaceExisting { skipped += 1; continue }
                    q.id = existing; updated += 1
                } else { added += 1 }
                if let old = byID[q.id], byTitle[old.fingerprint] == q.id { byTitle.removeValue(forKey: old.fingerprint) }
                byID[q.id] = q; byTitle[q.fingerprint] = q.id; selected[q.id] = q
            }
            try database.save(questions: Array(selected.values)); questions = try database.questions()
            showImportPreview = false; importDocument = nil
            notice = "导入完成：新增 \(added) 题，更新 \(updated) 题，跳过 \(skipped) 道重复题。"
            if selectedID == nil { choose(filteredQuestions.first?.id) }
        } catch { errorMessage = error.localizedDescription }
    }
    func exportQuestions() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "面试题库.json"; panel.allowedContentTypes = [.json]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    try encoder.encode(self.questions).write(to: url, options: .atomic)
                    self.notice = "题库已导出。答题记录仍保留在本机数据库中。"
                } catch { self.errorMessage = error.localizedDescription }
            }
        }
    }
}
