import SwiftUI
import AppKit
import OneQuestionCore

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var search = ""
    @State private var selected: String?
    @State private var editing: Question?
    @State private var deleting: Question?
    private var visible: [Question] {
        store.questions.filter { search.trimmed.isEmpty || [$0.title, $0.category, $0.deck, $0.tags.joined(separator: " ")].joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(visible) { question in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(question.title).lineLimit(2)
                        Text("\(question.deck) · \(question.category)").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).tag(question.id)
                }
            }.searchable(text: $search, prompt: "搜索题目、分类、标签")
            .navigationSplitViewColumnWidth(min: 260, ideal: 310)
        } detail: {
            if let q = store.questions.first(where: { $0.id == selected }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        Text(q.category + " · " + q.difficulty).foregroundStyle(.secondary)
                        if let source = q.source { Text("来源：" + source).font(.caption).foregroundStyle(.secondary) }
                        Text(q.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        HStack {
                            Button("练习这道题") {
                                guard !store.isEvaluating else { return }
                                store.selectedDeck = "全部题库"; store.reviewOnly = false; store.choose(q.id); openWindow(id: "practice")
                            }.buttonStyle(.borderedProminent).disabled(store.isEvaluating)
                            Button("编辑") { editing = q }.disabled(store.isEvaluating)
                            Button("删除…", role: .destructive) { deleting = q }.disabled(store.isEvaluating)
                        }
                        Divider()
                        Text("参考答案").font(.headline)
                        Text(q.referenceAnswer.isEmpty ? "尚未填写，补充后可用于自动评价。" : q.referenceAnswer).textSelection(.enabled)
                        Text("评分要点").font(.headline)
                        if q.criteria.isEmpty { Text("未单独设置时，按参考答案整体评价（10 分）。").foregroundStyle(.secondary) }
                        ForEach(q.criteria) { criterion in
                            HStack(alignment: .top) { Text(criterion.text); Spacer(); Text("\(criterion.weight) 分").foregroundStyle(.secondary) }
                        }
                        if !q.tags.isEmpty { Text("标签：" + q.tags.joined(separator: "、")).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("选择一道题，或导入你的题库").font(.title3)
                    Text("现有 \(store.questions.count) 题 · 支持 PDF / Excel / CSV / JSON").foregroundStyle(.secondary)
                    Button("导入题库…") { openWindow(id: "practice"); store.openImportPanel() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 540)
        .toolbar {
            ToolbarItemGroup {
                Button { openWindow(id: "practice"); store.openImportPanel() } label: { Label("导入题库", systemImage: "square.and.arrow.down") }.disabled(store.isImporting)
                Button { editing = Question(title: "") } label: { Label("新增", systemImage: "plus") }
                Button { store.exportQuestions() } label: { Label("导出", systemImage: "square.and.arrow.up") }
                Button { NSWorkspace.shared.open(templateDirectory()) } label: { Label("导入模板", systemImage: "doc.badge.arrow.down") }
            }
        }
        .sheet(item: $editing) { q in QuestionEditor(question: q).environmentObject(store) }
        .confirmationDialog("删除这道题？历史回答会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除题目", role: .destructive) { if let q = deleting { store.deleteQuestion(q) }; deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }
}

struct QuestionEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var question: Question
    var onSave: ((Question) throws -> Void)? = nil
    @State private var tags = ""
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(question.title.isEmpty ? "新增题目" : "编辑题目").font(.title3.weight(.semibold)); Spacer() }.padding(20)
            Divider()
            Form {
                Section("题目信息") {
                    TextField("题目", text: $question.title, axis: .vertical).lineLimit(2...4)
                    TextField("题库", text: $question.deck)
                    TextField("分类", text: $question.category)
                    TextField("难度", text: $question.difficulty)
                    TextField("标签（用逗号分隔）", text: $tags)
                }
                Section("参考答案") { TextEditor(text: $question.referenceAnswer).font(.body).frame(minHeight: 110) }
                Section("评分要点与权重") {
                    ForEach($question.criteria) { $criterion in
                        HStack {
                            TextField("要点", text: $criterion.text, axis: .vertical)
                            Stepper("\(criterion.weight) 分", value: $criterion.weight, in: 1...100).frame(width: 110)
                            Button { question.criteria.removeAll { $0.id == criterion.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        }
                    }
                    Button("添加评分要点") { question.criteria.append(Criterion(text: "", weight: 2)) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(18)
        }.frame(width: 640, height: 680)
        .onAppear { tags = question.tags.joined(separator: ", ") }
    }
    private func save() {
        do {
            question.title = question.title.trimmed
            if question.deck.trimmed.isEmpty { question.deck = "我的题库" }
            if question.category.trimmed.isEmpty { question.category = "未分类" }
            question.tags = tags.components(separatedBy: CharacterSet(charactersIn: ",，")).map(\.trimmed).filter { !$0.isEmpty }
            if let onSave {
                guard !question.title.trimmed.isEmpty else { throw AppFailure("请填写题目。") }
                guard question.criteria.allSatisfy({ !$0.text.trimmed.isEmpty && (1...100).contains($0.weight) }) else { throw AppFailure("评分要点不能为空，权重为 1–100。") }
                try onSave(question)
            } else { try store.saveQuestion(question) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ImportPreviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var replaceExisting = false
    @State private var skipInvalid = false
    @State private var existingIDs = Set<String>()
    @State private var existingTitles = Set<String>()
    @State private var editingRow: ImportRow?
    @State private var editingSource = false
    private var rows: [ImportRow] { store.importDocument?.rows ?? [] }
    private var valid: Int { rows.filter { $0.question != nil }.count }
    private var invalid: Int { rows.count - valid }
    private var duplicates: Int { rows.compactMap(\.question).filter(isDuplicate).count }
    private func isDuplicate(_ q: Question) -> Bool { existingIDs.contains(q.id) || existingTitles.contains(q.fingerprint) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("导入题库预览").font(.title2.weight(.semibold)); Spacer(); Text(store.importDocument?.name ?? "").foregroundStyle(.secondary) }
            Text("有效 \(valid) 题 · 错误 \(invalid) 行 · 与现有题库重复 \(duplicates) 题").font(.callout)
            if let notice = store.importDocument?.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Excel 读取第一张工作表；重复题按 ID 或相同题目名称识别。").font(.caption).foregroundStyle(.secondary)
            }
            if store.importDocument?.sourceText != nil {
                HStack {
                    Label("PDF 导入 · 本地提取与识别", systemImage: "doc.text").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("调整提取文字…") { editingSource = true }
                }
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(row.line)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 35, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 5) {
                                if let q = row.question {
                                    Text(q.title).lineLimit(2)
                                    HStack {
                                        Text(q.category).foregroundStyle(.secondary)
                                        if let source = row.source { Text(source).foregroundStyle(.secondary) }
                                        if isDuplicate(q) { Text("重复题").foregroundStyle(.orange) }
                                        if let warning = row.warning { Text(warning).foregroundStyle(.orange) }
                                    }.font(.caption)
                                } else { Text(row.issue ?? "无法读取").foregroundStyle(.red) }
                            }
                            Spacer()
                            if row.question != nil { Button("编辑") { editingRow = row } }
                        }.padding(.vertical, 12)
                        Divider()
                    }
                }
            }
            Picker("重复题", selection: $replaceExisting) {
                Text("跳过已有题目").tag(false)
                Text("更新题目，保留历史作答").tag(true)
            }.pickerStyle(.segmented)
            if invalid > 0 { Toggle("跳过错误行，只导入有效题目", isOn: $skipInvalid) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认导入 \(valid) 题") { store.commitImport(replaceExisting: replaceExisting) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(valid == 0 || (invalid > 0 && !skipInvalid))
            }
        }.padding(24).frame(width: 740, height: 600)
        .onAppear {
            existingIDs = Set(store.questions.map(\.id)); existingTitles = Set(store.questions.map(\.fingerprint))
        }
        .sheet(item: $editingRow) { row in
            if let question = row.question {
                QuestionEditor(question: question, onSave: { store.updateImportRow(row.id, question: $0) }).environmentObject(store)
            }
        }
        .sheet(isPresented: $editingSource) {
            PDFSourceEditor(text: store.importDocument?.sourceText ?? "", name: store.importDocument?.name ?? "PDF题库")
                .environmentObject(store)
        }
    }
}

private struct PDFSourceEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    let name: String
    @State private var error: String?
    @State private var parsing = false
    @State private var parsingTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("调整 PDF 提取文字").font(.title3.weight(.semibold))
            Text("使用“题目：”与“答案：”分段；可添加“评分要点：”。保留页码标记，方便回溯原文。重新识别会替换当前预览。").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 14, design: .monospaced))
                .border(Color.secondary.opacity(0.25)).disabled(parsing)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            if parsing { HStack { ProgressView().controlSize(.small); Text("正在重新识别题目…").font(.callout).foregroundStyle(.secondary) } }
            HStack {
                Button("取消") { parsingTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("重新识别题目") {
                    let source = text, deckName = name
                    parsing = true; error = nil
                    parsingTask = Task {
                        let worker = Task.detached(priority: .userInitiated) { try PDFQuestionImporter.parse(text: source, name: deckName) }
                        do {
                            let doc = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                            try Task.checkCancellation()
                            store.importDocument = doc; parsing = false; dismiss()
                        } catch is CancellationError { parsing = false }
                        catch { self.error = error.localizedDescription; parsing = false }
                    }
                }.buttonStyle(.borderedProminent).disabled(parsing)
            }
        }.padding(22).frame(width: 740, height: 580)
        .onDisappear { parsingTask?.cancel() }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected: String?
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(store.attempts) { attempt in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(attempt.question.title).lineLimit(2)
                        Text(attempt.resultLabel).font(.caption).foregroundStyle(.secondary)
                        Text(attempt.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 5).tag(attempt.id)
                }
            }.navigationSplitViewColumnWidth(min: 250, ideal: 290)
        } detail: {
            if let attempt = store.attempts.first(where: { $0.id == selected }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(attempt.question.title).font(.title2.weight(.semibold))
                        Text(attempt.createdAt, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary)
                        Text("当时的回答").font(.headline)
                        Text(attempt.answer).textSelection(.enabled)
                        if let evaluation = attempt.evaluation { EvaluationView(question: attempt.question, evaluation: evaluation) }
                        else { Text(attempt.resultLabel).foregroundStyle(.secondary) }
                        Divider(); Text("当时的参考答案").font(.headline)
                        Text(attempt.question.referenceAnswer).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(store.attempts.isEmpty ? "提交回答后，记录会保存在这里" : "选择一次回答，查看当时的内容与反馈").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(minWidth: 780, minHeight: 520)
    }
}

func templateDirectory() -> URL {
    if let resources = Bundle.main.resourceURL {
        let bundled = resources.appendingPathComponent("Templates")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
    }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Templates")
}
