import Foundation

public struct AppFailure: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Criterion: Codable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var weight: Int
    public init(id: String = UUID().uuidString, text: String, weight: Int = 1) {
        self.id = id; self.text = text; self.weight = weight
    }
}

public struct Question: Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var referenceAnswer: String
    public var criteria: [Criterion]
    public var deck: String
    public var category: String
    public var difficulty: String
    public var tags: [String]
    public var source: String?
    public init(id: String = UUID().uuidString, title: String, referenceAnswer: String = "",
                criteria: [Criterion] = [], deck: String = "我的题库", category: String = "未分类",
                difficulty: String = "基础", tags: [String] = [], source: String? = nil) {
        self.id = id; self.title = title; self.referenceAnswer = referenceAnswer; self.criteria = criteria
        self.deck = deck; self.category = category; self.difficulty = difficulty; self.tags = tags
        self.source = source
    }
    public var canEvaluate: Bool { !referenceAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var effectiveCriteria: [Criterion] {
        criteria.isEmpty ? [Criterion(id: "reference", text: "依据参考答案评价概念准确性与关键内容的完整性", weight: 10)] : criteria
    }
    public var fingerprint: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct CriterionResult: Codable, Hashable, Identifiable {
    public var id: String { criterionID }
    public let criterionID: String
    public let earned: Int
    public let evidence: String
    public let explanation: String
    public init(criterionID: String, earned: Int, evidence: String, explanation: String) {
        self.criterionID = criterionID; self.earned = earned; self.evidence = evidence; self.explanation = explanation
    }
}

public struct Evaluation: Codable, Hashable {
    public let summary: String
    public let criteria: [CriterionResult]
    public let corrections: [String]
    public let improvedAnswer: String
    public init(summary: String, criteria: [CriterionResult], corrections: [String], improvedAnswer: String) {
        self.summary = summary; self.criteria = criteria; self.corrections = corrections; self.improvedAnswer = improvedAnswer
    }
    public var earned: Int { criteria.reduce(0) { $0 + $1.earned } }
    public func validate(for question: Question, answer: String) throws {
        let expected = question.effectiveCriteria
        guard criteria.count == expected.count,
              Set(criteria.map(\.criterionID)).count == expected.count else {
            throw AppFailure("AI 返回的评分要点不完整，请重试。")
        }
        for item in criteria {
            guard let criterion = expected.first(where: { $0.id == item.criterionID }),
                  (0...criterion.weight).contains(item.earned) else {
                throw AppFailure("AI 返回的分项分数无效，请重试。")
            }
            let quote = item.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard quote.isEmpty || answer.contains(quote) else {
                throw AppFailure("AI 引用的内容与本次答案不一致，请重试。")
            }
            guard item.earned == 0 || !quote.isEmpty else {
                throw AppFailure("AI 未提供得分依据，请重试。")
            }
        }
    }
}

public struct Attempt: Codable, Identifiable, Hashable {
    public var id: String
    public var question: Question
    public var answer: String
    public var createdAt: Date
    public var evaluation: Evaluation?
    public var selfRating: String?
    public init(question: Question, answer: String) {
        id = UUID().uuidString; self.question = question; self.answer = answer; createdAt = Date()
    }
    public var needsReview: Bool {
        if let selfRating { return selfRating != "已掌握" }
        guard let evaluation else { return true }
        let maxScore = question.effectiveCriteria.reduce(0) { $0 + $1.weight }
        return Double(evaluation.earned) / Double(max(1, maxScore)) < 0.8
    }
    public var resultLabel: String {
        if let selfRating { return "自评 · \(selfRating)" }
        if let evaluation { return "AI · \(evaluation.earned) / \(question.effectiveCriteria.reduce(0) { $0 + $1.weight })" }
        return "待评价"
    }
}

public struct AISettings: Codable, Equatable {
    public var enabled = false
    public var endpoint = ""
    public var model = ""
    public var jsonMode = true
    public init() {}
    public func requestURL() throws -> URL {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw AppFailure("请填写 HTTPS 接口地址；本地模型可使用 http://localhost。")
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure("请填写模型名称。") }
        if url.path.hasSuffix("/chat/completions") { return url }
        return url.appendingPathComponent("chat/completions")
    }
}

public struct ImportRow: Identifiable {
    public let id = UUID()
    public var line: Int
    public var question: Question?
    public var issue: String?
    public var warning: String?
    public var source: String?
    public init(line: Int, question: Question?, issue: String? = nil, warning: String? = nil, source: String? = nil) {
        self.line = line; self.question = question; self.issue = issue; self.warning = warning; self.source = source
    }
}

public struct ImportDocument {
    public var name: String
    public var rows: [ImportRow]
    public var notice: String?
    public var sourceText: String?
    public init(name: String, rows: [ImportRow], notice: String? = nil, sourceText: String? = nil) {
        self.name = name; self.rows = rows; self.notice = notice; self.sourceText = sourceText
    }
}

public enum Samples {
    public static let questions: [Question] = [
        Question(id: "sample-equals", title: "Java 中，== 和 equals() 有什么区别？",
            referenceAnswer: "== 对基本类型比较值，对引用类型判断是否指向同一对象。Object.equals() 默认也按对象身份判断，类可以重写它定义逻辑相等；例如 String.equals() 按字符内容比较。",
            criteria: [Criterion(id: "primitive", text: "区分基本类型的值比较", weight: 2), Criterion(id: "reference", text: "解释引用类型的对象身份比较", weight: 3), Criterion(id: "override", text: "说明 Object.equals 默认行为及可重写性", weight: 3), Criterion(id: "example", text: "给出 String 内容比较的例子", weight: 2)], deck: "Java 面试示例", category: "Java 基础", tags: ["对象", "相等性"]),
        Question(id: "sample-hashcode", title: "为什么重写 equals() 时通常也要重写 hashCode()？",
            referenceAnswer: "equals 相等的对象必须有相同的 hashCode，反过来不成立。重写 equals 后，继承的 hashCode 不一定满足新的相等规则，可能影响 HashMap、HashSet 中的查找和去重。",
            criteria: [Criterion(text: "解释相等对象必须有相同哈希值", weight: 4), Criterion(text: "说明哈希值相同不代表相等", weight: 2), Criterion(text: "解释哈希容器中的影响", weight: 4)], deck: "Java 面试示例", category: "Java 基础", tags: ["集合"]),
        Question(id: "sample-map", title: "HashMap 和 ConcurrentHashMap 的使用场景有什么区别？",
            referenceAnswer: "HashMap 本身不保证线程安全，适合单线程或外部已同步的场景。ConcurrentHashMap 用于并发访问，提供线程安全的操作；跨多个调用的复合逻辑仍需使用合适的原子方法或同步方案。它不允许 null 键和值。",
            criteria: [Criterion(text: "说明 HashMap 的线程安全边界", weight: 3), Criterion(text: "说明并发容器适用场景", weight: 3), Criterion(text: "指出复合操作与 null 的注意事项", weight: 4)], deck: "Java 面试示例", category: "集合与并发", tags: ["HashMap", "并发"]),
        Question(id: "sample-index", title: "数据库索引为什么能加快查询？使用索引有哪些代价？",
            referenceAnswer: "索引提供有序或其他组织结构，帮助数据库减少查找目标行需要扫描的数据。收益取决于查询条件、选择性和执行计划。索引占用空间，并增加插入、更新、删除时的维护成本，并非越多越好。",
            criteria: [Criterion(text: "解释减少扫描与索引结构的关系", weight: 4), Criterion(text: "说明适用条件与执行计划", weight: 2), Criterion(text: "说明空间和写入维护成本", weight: 4)], deck: "Java 面试示例", category: "数据库", tags: ["索引"])
    ]
}
