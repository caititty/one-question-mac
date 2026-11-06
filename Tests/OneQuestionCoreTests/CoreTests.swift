import Testing
import Foundation
@testable import OneQuestionCore

struct CoreTests {
    @Test func csvQuotedMultilineAndBOM() throws {
        let csv = "\u{feff}题目,参考答案,评分要点\r\n\"为什么,这样？\",\"第一行\n包含\"\"引号\"\"\",要点一;要点二\r\n"
        let table = try QuestionImporter.parseCSV(csv)
        let result = try QuestionImporter.fromTable(table, name: "CSV题库")
        #expect(result.rows.count == 1)
        let q = try #require(result.rows.first?.question)
        #expect(q.title == "为什么,这样？")
        #expect(q.referenceAnswer == "第一行\n包含\"引号\"")
        #expect(q.criteria.count == 2)
    }
    @Test func csvRejectsBrokenQuotesAndMissingHeader() throws {
        #expect(throws: AppFailure.self) { try QuestionImporter.parseCSV("题目,答案\n\"未结束,答案") }
        #expect(throws: AppFailure.self) { try QuestionImporter.fromTable([["名字"], ["题目"]], name: "测试") }
    }
    @Test func jsonAliasesWeightsAndInvalidRows() throws {
        let json = #"{"deckName":"测试","questions":[{"id":"a","title":"问题一","answer":"答案","criteria":[{"id":"c","text":"要点","weight":3}]},{"id":"a","title":"重复编号"},{"title":""},{"title":"权重错误","criteria":[{"text":"要点","weight":0}]}]}"#
        let doc = try QuestionImporter.parseJSON(Data(json.utf8), name: "默认")
        #expect(doc.name == "测试")
        #expect(doc.rows[0].question?.criteria.first?.weight == 3)
        #expect(doc.rows.filter { $0.question == nil }.count == 3)
    }
    @Test func xlsxReadsNamedFirstSheetAndSharedStrings() throws {
        let url = try #require(Bundle.module.url(forResource: "shared-strings", withExtension: "xlsx", subdirectory: "Fixtures"))
        let doc = try QuestionImporter.load(url: url)
        let q = try #require(doc.rows.first?.question)
        #expect(q.title == "从共享字符串读取的问题")
        #expect(q.referenceAnswer == "多行\n参考答案")
        #expect(q.criteria.count == 2)
    }
    @Test func templatesAllImport() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Templates")
        for ext in ["json", "csv", "xlsx"] {
            let doc = try QuestionImporter.load(url: directory.appendingPathComponent("interview-template.\(ext)"))
            #expect(doc.rows.count == 2)
            #expect(doc.rows.allSatisfy { $0.question != nil })
        }
    }
    @Test func databasePersistsSnapshotAfterQuestionUpdate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite3")
        var question = Question(id: "q", title: "旧问题", referenceAnswer: "旧答案")
        let attempt = Attempt(question: question, answer: "我的回答")
        do {
            let db = try Database(url: url)
            try db.save(questions: [question]); try db.save(attempt: attempt)
            question.title = "新问题"; question.referenceAnswer = "新答案"; try db.save(questions: [question])
            try db.set(["q": "中文草稿\n第二行"], for: "drafts")
        }
        let reopened = try Database(url: url)
        #expect(try reopened.questions().first?.title == "新问题")
        #expect(try reopened.attempts().first?.question.title == "旧问题")
        #expect(try reopened.get([String: String].self, for: "drafts")?["q"] == "中文草稿\n第二行")
        try reopened.deleteQuestion(id: "q")
        #expect(try reopened.questions().isEmpty)
        #expect(try reopened.attempts().count == 1)
    }
    @Test func evaluationRejectsFabricatedEvidenceAndInvalidScores() throws {
        let question = Question(title: "问题", referenceAnswer: "答案", criteria: [Criterion(id: "c", text: "要点", weight: 3)])
        func evaluation(_ points: Int, _ evidence: String) -> Evaluation {
            Evaluation(summary: "反馈", criteria: [CriterionResult(criterionID: "c", earned: points, evidence: evidence, explanation: "解释")], corrections: [], improvedAnswer: "改进")
        }
        try evaluation(2, "原文").validate(for: question, answer: "这是原文")
        #expect(throws: AppFailure.self) { try evaluation(4, "原文").validate(for: question, answer: "这是原文") }
        #expect(throws: AppFailure.self) { try evaluation(2, "伪造原文").validate(for: question, answer: "这是原文") }
        #expect(throws: AppFailure.self) { try evaluation(2, "").validate(for: question, answer: "这是原文") }
    }
    @Test func endpointValidation() throws {
        var settings = AISettings(); settings.model = "user-specified-model"; settings.endpoint = "https://example.com/v1"
        #expect(try settings.requestURL().absoluteString == "https://example.com/v1/chat/completions")
        settings.endpoint = "http://example.com/v1"; #expect(throws: AppFailure.self) { try settings.requestURL() }
        settings.endpoint = "http://localhost:1234/v1"; _ = try settings.requestURL()
    }
}
