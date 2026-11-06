import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OneQuestionCore

struct PracticeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var referenceExpanded = true
    @FocusState private var answerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if store.isImporting {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(store.importProgress).font(.callout).foregroundStyle(.secondary)
                            Spacer(); Button("取消") { store.cancelImport() }
                        }
                    }
                    if let notice = store.notice {
                        HStack(alignment: .top) {
                            Label(notice, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.secondary)
                            Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭提示")
                        }.padding(12).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let question = store.currentQuestion {
                        questionBody(question)
                    } else {
                        VStack(spacing: 15) {
                            Image(systemName: store.reviewOnly ? "checkmark.seal" : "tray.and.arrow.down").font(.system(size: 36)).foregroundStyle(.secondary)
                            Text(store.reviewOnly ? "当前没有需要复习的题" : "导入题库，开始第一题").font(.title3.weight(.medium))
                            Text(store.reviewOnly ? "可以切换到全部题目继续练习。" : "支持 PDF、Excel、CSV 和 JSON，也可以手动新增题目。").foregroundStyle(.secondary)
                            Button("导入题库…") { store.openImportPanel() }.buttonStyle(.borderedProminent)
                        }.frame(maxWidth: .infinity).padding(.vertical, 85)
                    }
                }.padding(26)
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 500, minHeight: 550)
        .toolbar {
            ToolbarItemGroup {
                Button { openWindow(id: "library") } label: { Label("题库", systemImage: "books.vertical") }.help("题库管理 ⇧⌘L")
                Button { store.openImportPanel() } label: { Label("导入", systemImage: "square.and.arrow.down") }.disabled(store.isImporting)
                Button { store.togglePin() } label: { Label(store.pinned ? "取消置顶" : "置顶", systemImage: store.pinned ? "pin.fill" : "pin") }.help(store.pinned ? "取消窗口置顶" : "窗口置顶")
            }
        }
        .onChange(of: store.draft) { _ in store.queueDraftSave() }
        .onChange(of: store.selectedDeck) { _ in store.updateFilter() }
        .onChange(of: store.reviewOnly) { _ in store.updateFilter() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in store.loadImport(url) } }
            }
            return true
        }
    }
    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("题库", selection: $store.selectedDeck) {
                Text("全部题库").tag("全部题库")
                ForEach(store.decks, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(maxWidth: 210).disabled(store.isEvaluating)
            Toggle("只练待复习", isOn: $store.reviewOnly).toggleStyle(.checkbox).disabled(store.isEvaluating)
            Spacer()
            Text(store.position).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.horizontal, 22).padding(.vertical, 13)
    }
    @ViewBuilder private func questionBody(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(question.category).font(.callout).foregroundStyle(.secondary)
                Text(question.difficulty).font(.caption).padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule())
                Spacer()
                Text("简答题").font(.callout).foregroundStyle(.secondary)
            }
            Text(question.title).font(.system(size: 24, weight: .semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("你的回答").font(.headline)
                Spacer()
                Text(store.isSubmitted ? "已保存" : "草稿自动保存").font(.caption).foregroundStyle(.secondary)
            }
            if store.isSubmitted {
                Text(store.draft).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(13)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                TextEditor(text: $store.draft).font(.system(size: 15)).focused($answerFocused)
                    .padding(7).frame(minHeight: 145)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
                Text("按面试口述的方式组织答案，⌘ Return 提交。").font(.caption).foregroundStyle(.secondary)
            }
        }
        if store.isEvaluating {
            HStack { ProgressView().controlSize(.small); Text("正在按要点评价，回答已保存在本机…").foregroundStyle(.secondary); Spacer(); Button("取消") { store.cancelEvaluation() } }
        }
        if let attempt = store.currentAttempt {
            if let evaluation = attempt.evaluation {
                EvaluationView(question: attempt.question, evaluation: evaluation)
            } else if !store.isEvaluating {
                VStack(alignment: .leading, spacing: 9) {
                    Label("对照参考答案，标记掌握程度", systemImage: "text.book.closed").font(.headline)
                    Text(question.canEvaluate ? (store.settings.enabled ? "本次回答已保存，可重试 AI 评价或自行对照。" : "启用 AI 后可获得分项评分；现在可以先自行对照。") : "这道题缺少参考答案，可在题库管理中补充。")
                        .font(.callout).foregroundStyle(.secondary)
                    if store.settings.enabled && question.canEvaluate { Button("AI 评价本次回答") { store.evaluateCurrent() } }
                    else if !store.settings.enabled { Button("配置 AI…") { openWindow(id: "preferences") } }
                }
            }
            if question.canEvaluate {
                DisclosureGroup("参考答案", isExpanded: $referenceExpanded) {
                    Text(question.referenceAnswer).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(.body)
            }
            if !store.isEvaluating {
                VStack(alignment: .leading, spacing: 9) {
                    Text(attempt.selfRating.map { "本次自评：\($0)" } ?? "我的掌握程度").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        ForEach(["需复习", "部分掌握", "已掌握"], id: \.self) { rating in
                            Button { store.rate(rating) } label: {
                                Label(rating, systemImage: attempt.selfRating == rating ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
            }
        }
    }
    private var actionBar: some View {
        HStack {
            if store.isSubmitted {
                Button("改写再答") { store.rewrite(); answerFocused = true }.disabled(store.isEvaluating)
            } else {
                Button("暂时跳过") { store.next() }.disabled(store.isEvaluating || store.currentQuestion == nil)
            }
            Spacer()
            Toggle("随机", isOn: $store.randomOrder).toggleStyle(.checkbox).disabled(store.isEvaluating)
            if store.isSubmitted {
                Button("下一题") { store.next() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(store.isEvaluating)
            } else {
                Button("提交回答") { store.submit() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(store.draft.trimmed.isEmpty || store.currentQuestion == nil || store.isEvaluating)
            }
        }.padding(.horizontal, 22).padding(.vertical, 16)
    }
}

struct EvaluationView: View {
    let question: Question
    let evaluation: Evaluation
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(evaluation.earned)").font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("/ \(question.effectiveCriteria.reduce(0) { $0 + $1.weight })").font(.title3).foregroundStyle(.secondary)
                Spacer(); Text("AI 评价 · 可结合自评复核").font(.caption).foregroundStyle(.secondary)
            }
            Text(evaluation.summary).textSelection(.enabled)
            ForEach(question.effectiveCriteria) { criterion in
                if let item = evaluation.criteria.first(where: { $0.criterionID == criterion.id }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(criterion.text).font(.headline)
                            Spacer(); Text("\(item.earned) / \(criterion.weight)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        if !item.evidence.isEmpty { Text("原文：“\(item.evidence)”").font(.callout).foregroundStyle(.secondary) }
                        Text(item.explanation).font(.callout)
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    Divider()
                }
            }
            if !evaluation.corrections.isEmpty {
                Text("需要纠正").font(.headline)
                ForEach(Array(evaluation.corrections.enumerated()), id: \.offset) { _, item in Text("• \(item)").textSelection(.enabled) }
            }
            DisclosureGroup("改进后的面试回答") { Text(evaluation.improvedAnswer).textSelection(.enabled).padding(.top, 8) }
        }.padding(17).background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
