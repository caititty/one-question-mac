import Testing
import Foundation
@testable import OneQuestionCore

struct AIImportTests {
    @Test func separatesUnlabelledAnswersFromOriginalText() async throws {
        let wrong = Question(title: "题干与答案被合并", referenceAnswer: "")
        let original = ImportDocument(name: "面试", rows: [ImportRow(line: 1, question: wrong)], sourceText: "【PDF第1页】\n1. == 和 equals 有什么区别？\n== 对引用比较对象身份。\nString.equals 比较内容。\n2. 什么是线程？\n线程是进程中的执行单元。")
        let result = try await AIImportAnalyzer.analyze(document: original) { _, input in
            let body = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let lines = try #require(body["source_lines"] as? [[String: Any]])
            #expect(lines.count == 5)
            #expect(lines.first?["page"] as? Int == 1)
            return #"{"questions":[{"question":[1,1],"answers":[[2,3]]},{"question":[4,4],"answers":[[5,5]]}]}"#
        }
        #expect(result.rows.count == 2)
        #expect(result.rows[0].question?.title == "== 和 equals 有什么区别？")
        #expect(result.rows[0].question?.referenceAnswer == "== 对引用比较对象身份。\nString.equals 比较内容。")
        #expect(result.rows[0].question?.source?.contains("题目第 1 页") == true)
        #expect(original.rows[0].question?.title == wrong.title)
        #expect(result.sourceText == original.sourceText)
    }
    @Test func inlineQuestionAndStandardAnswerCanBeSeparated() async throws {
        let doc = ImportDocument(name: "一行", rows: [], sourceText: "1. 什么是线程？标准答案：线程是进程中的执行单元。")
        let result = try await AIImportAnalyzer.analyze(document: doc) { _, _ in
            #"{"questions":[{"question":[1,1],"answers":[[2,2]]}]}"#
        }
        #expect(result.rows[0].question?.title == "什么是线程？")
        #expect(result.rows[0].question?.referenceAnswer == "线程是进程中的执行单元。")
    }
    @Test func missingAnswersRemainEmpty() async throws {
        let doc = ImportDocument(name: "无答案", rows: [], sourceText: "题目：什么是线程？")
        let result = try await AIImportAnalyzer.analyze(document: doc) { _, _ in #"{"questions":[{"question":[1,1],"answers":[]}]}"# }
        #expect(result.rows[0].question?.canEvaluate == false)
        #expect(result.rows[0].warning?.contains("未找到答案") == true)
    }
    @Test func inlineUnlabelledAnswerHasSeparateSourceLines() async throws {
        let doc = ImportDocument(name: "无标记", rows: [], sourceText: "1. 什么是线程？线程是进程中的执行单元。")
        let result = try await AIImportAnalyzer.analyze(document: doc) { _, _ in
            #"{"questions":[{"question":[1,1],"answers":[[2,2]]}]}"#
        }
        #expect(result.rows[0].question?.title == "什么是线程？")
        #expect(result.rows[0].question?.referenceAnswer == "线程是进程中的执行单元。")
    }
    @Test func rejectsNonexistentSourceLines() async throws {
        let doc = ImportDocument(name: "测试", rows: [], sourceText: "问题\n答案")
        await #expect(throws: AppFailure.self) {
            try await AIImportAnalyzer.analyze(document: doc) { _, _ in #"{"questions":[{"question":[1,1],"answers":[[2,99]]}]}"# }
        }
    }
    @Test func rejectsQuestionAnswerRoleConflicts() async throws {
        let doc = ImportDocument(name: "测试", rows: [], sourceText: "第一题\n第一个答案\n第二题\n第二个答案")
        await #expect(throws: AppFailure.self) {
            try await AIImportAnalyzer.analyze(document: doc) { _, _ in #"{"questions":[{"question":[1,1],"answers":[[2,3]]},{"question":[3,3],"answers":[[4,4]]}]}"# }
        }
    }
    @Test func rejectsInvalidJSONAndEmptyExtraction() async throws {
        let doc = ImportDocument(name: "测试", rows: [], sourceText: "问题\n答案")
        await #expect(throws: AppFailure.self) { try await AIImportAnalyzer.analyze(document: doc) { _, _ in "not JSON" } }
        await #expect(throws: AppFailure.self) { try await AIImportAnalyzer.analyze(document: doc) { _, _ in #"{"questions":[]}"# } }
    }
    @Test func mergesLongAnswersAcrossChunksWithoutDuplicatingText() async throws {
        let paragraphs = (1...16).map { "第\($0)段：" + String(repeating: "原文中的解释内容", count: 4) }
        let doc = ImportDocument(name: "长答案", rows: [], sourceText: (["为什么需要线程池？"] + paragraphs).joined(separator: "\n"))
        var calls = 0
        let result = try await AIImportAnalyzer.analyze(document: doc, maximumChunkCharacters: 150) { _, input in
            calls += 1
            let payload = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let lines = try #require(payload["source_lines"] as? [[String: Any]])
            let ids = lines.compactMap { $0["id"] as? Int }.filter { $0 != 1 }
            if calls > 1 {
                let known = try #require(payload["known_questions"] as? [[String: Any]])
                #expect(!known.isEmpty)
            }
            let answers = ids.first.map { [[$0, ids.last!]] } ?? []
            let response: [String: Any] = ["questions": [["question": [1,1], "answers": answers]]]
            return String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        }
        #expect(calls > 1)
        #expect(result.rows.count == 1)
        #expect(result.rows[0].question?.referenceAnswer == paragraphs.joined(separator: "\n"))
    }
    @Test func partialNetworkFailureLeavesOriginalPreviewUntouched() async throws {
        let original = Question(title: "已有预览", referenceAnswer: "原有答案")
        let doc = ImportDocument(name: "失败", rows: [ImportRow(line: 1, question: original)], sourceText: "问题\n" + String(repeating: "解释段落\n", count: 100))
        var calls = 0
        await #expect(throws: AppFailure.self) {
            try await AIImportAnalyzer.analyze(document: doc, maximumChunkCharacters: 150) { _, _ in
                calls += 1
                if calls > 1 { throw AppFailure("模拟接口失败") }
                return #"{"questions":[{"question":[1,1],"answers":[[2,2]]}]}"#
            }
        }
        #expect(doc.rows[0].question?.referenceAnswer == "原有答案")
    }
    @Test func existingQuestionRepairRetainsIdentityAndMetadata() async throws {
        let question = Question(id: "existing", title: "问题与答案合在一起", referenceAnswer: "补充解释", deck: "Java", category: "并发", difficulty: "中等", tags: ["线程"], source: "旧文件.pdf · 第1页")
        let doc = ImportDocument(name: question.deck, rows: [], sourceText: "什么是线程？\n线程是执行单元。", repairTarget: question)
        let result = try await AIImportAnalyzer.analyze(document: doc) { _, _ in #"{"questions":[{"question":[1,1],"answers":[[2,2]]}]}"# }
        let fixed = try #require(result.rows.first?.question)
        #expect(fixed.id == question.id)
        #expect(fixed.category == "并发")
        #expect(fixed.deck == "Java")
        #expect(fixed.source == question.source)
        #expect(fixed.referenceAnswer == "线程是执行单元。")
    }
    @Test func cancellationDoesNotProduceAReplacement() async throws {
        let doc = ImportDocument(name: "取消", rows: [], sourceText: "问题\n答案")
        let task = Task {
            try await AIImportAnalyzer.analyze(document: doc) { _, _ in
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return #"{"questions":[{"question":[1,1],"answers":[[2,2]]}]}"#
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func everyInlineSubquestionRemainsInTheCard() async throws {
        let doc = ImportDocument(name: "连续多问", rows: [], sourceText: "1. 什么是线程池？为什么要使用它？有哪些代价？线程池复用线程，减少创建开销，但需要管理队列和资源。")
        let result = try await AIImportAnalyzer.analyze(document: doc) { _, input in
            let payload = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let lines = try #require(payload["source_lines"] as? [[String: Any]])
            #expect(lines.count == 4)
            return #"{"questions":[{"question":[1,1],"question_parts":[[2,3]],"answers":[[4,4]]}]}"#
        }
        let question = try #require(result.rows.first?.question)
        #expect(question.title == "什么是线程池？\n为什么要使用它？\n有哪些代价？")
        #expect(question.referenceAnswer == "线程池复用线程，减少创建开销，但需要管理队列和资源。")
        #expect(result.unassignedExcerpts.isEmpty)
    }
    @Test func interleavedSubquestionsAndAnswersStayTogetherAcrossPages() async throws {
        let text = "【PDF第1页】\n1. 线程池综合题\n（1）什么是线程池？\n（1）线程池复用工作线程执行任务。\n【PDF第2页】\n（2）为什么使用线程池？\n（2）减少线程创建开销并限制并发数。\n（3）队列满了怎么办？"
        let doc = ImportDocument(name: "复合题", rows: [], sourceText: text)
        let result = try await AIImportAnalyzer.analyze(document: doc) { _, _ in
            #"{"questions":[{"question":[1,1],"question_parts":[[2,2],[4,4],[6,6]],"answers":[[3,3],[5,5]],"note":"第3小问原文未提供答案"}]}"#
        }
        #expect(result.rows.count == 1)
        let question = try #require(result.rows[0].question)
        #expect(question.title == "线程池综合题\n（1）什么是线程池？\n（2）为什么使用线程池？\n（3）队列满了怎么办？")
        #expect(!question.title.contains("工作线程"))
        #expect(question.referenceAnswer == "（1）线程池复用工作线程执行任务。\n（2）减少线程创建开销并限制并发数。")
        #expect(result.rows[0].warning?.contains("第3小问") == true)
        #expect(question.source?.contains("题目第 1-2 页") == true)
        #expect(result.unassignedExcerpts.isEmpty)
    }
    @Test func omittedFollowupAndAnswerAreExposedForReview() async throws {
        let doc = ImportDocument(name: "遗漏", rows: [], sourceText: "【PDF第3页】\n1. 什么是线程池？\n线程池复用工作线程。\n追问：队列满了怎么办？\n执行拒绝策略。")
        let result = try await AIImportAnalyzer.analyze(document: doc) { _, _ in
            #"{"questions":[{"question":[1,1],"answers":[[2,2]],"note":"已整理"}]}"#
        }
        #expect(result.unassignedExcerpts.count == 1)
        #expect(result.unassignedExcerpts[0].text == "追问：队列满了怎么办？\n执行拒绝策略。")
        #expect(result.unassignedExcerpts[0].source == "第 3 页")
        #expect(result.notice?.contains("未归类") == true)
    }
    @Test func subquestionRangesCannotUseAnswerLinesOrInventedLines() async throws {
        let doc = ImportDocument(name: "冲突", rows: [], sourceText: "线程池综合题\n什么是线程池？\n线程池复用线程。")
        await #expect(throws: AppFailure.self) {
            try await AIImportAnalyzer.analyze(document: doc) { _, _ in
                #"{"questions":[{"question":[1,1],"question_parts":[[2,3]],"answers":[[3,3]]}]}"#
            }
        }
        await #expect(throws: AppFailure.self) {
            try await AIImportAnalyzer.analyze(document: doc) { _, _ in
                #"{"questions":[{"question":[1,1],"question_parts":[[99,99]],"answers":[[3,3]]}]}"#
            }
        }
    }
    @Test func laterChunksAppendSubquestionsToTheirOriginalParent() async throws {
        let paragraphs = (1...12).map { "解释\($0)：" + String(repeating: "复用工作线程来处理任务", count: 3) }
        let text = (["1. 线程池综合题", "（1）什么是线程池？"] + paragraphs + ["（2）为什么要使用它？", "减少创建开销并控制并发。"])
        let doc = ImportDocument(name: "跨段多问", rows: [], sourceText: text.joined(separator: "\n"))
        var calls = 0
        let result = try await AIImportAnalyzer.analyze(document: doc, maximumChunkCharacters: 160) { _, input in
            calls += 1
            let payload = try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let lines = try #require(payload["source_lines"] as? [[String: Any]])
            let questionIDs = lines.filter { ($0["text"] as? String)?.contains("？") == true }.compactMap { $0["id"] as? Int }
            let answerIDs = lines.compactMap { $0["id"] as? Int }.filter { $0 != 1 && !questionIDs.contains($0) }
            if calls > 1 {
                let known = try #require(payload["known_questions"] as? [[String: Any]])
                #expect(known.first?["question_parts"] != nil)
            }
            let response: [String: Any] = ["questions": [["question": [1,1], "question_parts": questionIDs.map { [$0,$0] }, "answers": answerIDs.map { [$0,$0] }]]]
            return String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        }
        #expect(calls > 1)
        #expect(result.rows.count == 1)
        #expect(result.rows[0].question?.title == "线程池综合题\n（1）什么是线程池？\n（2）为什么要使用它？")
        #expect(result.rows[0].question?.referenceAnswer == (paragraphs + ["减少创建开销并控制并发。"]).joined(separator: "\n"))
        #expect(result.unassignedExcerpts.isEmpty)
    }
}
