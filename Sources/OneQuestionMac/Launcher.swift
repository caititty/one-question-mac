import SwiftUI
import Foundation
import OneQuestionCore

/// Configuration uses stdin so credentials never appear in process arguments.
@main enum OneQuestionLauncher {
    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        do {
            if arguments.contains("--configure-ai") {
                let input = FileHandle.standardInput.readDataToEndOfFile()
                guard input.count <= 65_536 else { throw AppFailure("配置输入过大。") }
                let configuration = try JSONDecoder().decode(ConfigurationInput.self, from: input)
                _ = try configuration.settings.requestURL()
                let db = try runtimeDatabase()
                let previous = try db.aiSettings() ?? AISettings()
                let supplied = configuration.apiKey.trimmed
                let prepared = try configuration.settings.preparedForSaving(previous: previous, suppliedKey: supplied, withoutKey: supplied.isEmpty)
                if let account = prepared.credentialAccount {
                    try await BackgroundOperation.run(timeoutMessage: "钥匙串保存超时，配置未切换。") {
                        try Keychain.create(supplied, account: account)
                    }
                    let saved = try await BackgroundOperation.run(timeoutMessage: "钥匙串验证超时，配置未切换。") {
                        try Keychain.read(account: account, allowInteraction: false)
                    }
                    guard saved == supplied else { throw AppFailure("密钥保存后验证失败，配置未切换。") }
                }
                try db.saveAISettings(prepared)
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("OneQuestionAISettingsV2Changed"), object: nil, userInfo: nil, deliverImmediately: true)
                print("AI 配置已保存；钥匙串读回验证通过。")
                print("接口：\(configuration.settings.endpoint)")
                print("模型：\(configuration.settings.model)")
                return
            }
            if arguments.contains("--test-import-ai") || arguments.contains("--test-import-ai-composite") {
                let composite = arguments.contains("--test-import-ai-composite")
                FileHandle.standardError.write(Data("正在读取 AI 配置…\n".utf8))
                let db = try runtimeDatabase()
                guard let settings = try db.aiSettings() else { throw AppFailure("尚未配置 AI。") }
                FileHandle.standardError.write(Data("正在读取钥匙串密钥（不弹出授权窗口）…\n".utf8))
                let key = try await readKey(for: settings)
                let source = composite ? """
                【PDF第1页】
                第1题：线程池综合题
                （1）什么是线程池？
                （1）线程池复用工作线程来执行任务。
                （2）为什么使用线程池？
                （2）减少线程创建开销，并限制并发线程数。
                【PDF第2页】
                （3）任务队列满了怎么办？
                （3）根据配置执行拒绝策略，例如拒绝任务或由调用者执行。
                第2题：什么是数据库索引？
                索引是辅助查找的数据结构，可以减少适用查询的扫描工作。
                """ : "【PDF第1页】\n1. 什么是线程？\n线程是进程中的执行单元，同一进程内的线程共享地址空间。\n2. 什么是数据库索引？\n索引是辅助查找的数据结构，能减少适用查询的扫描工作。"
                let document = ImportDocument(name: "公开示例", rows: [], sourceText: source)
                FileHandle.standardError.write(Data("正在请求配置的模型…\n".utf8))
                let result = try await AIImportAnalyzer.analyze(document: document, settings: settings, apiKey: key)
                if composite {
                    guard result.rows.count == 2, let first = result.rows.first?.question,
                          ["什么是线程池", "为什么使用线程池", "任务队列满了怎么办"].allSatisfy({ first.title.contains($0) }),
                          ["复用工作线程", "减少线程创建开销", "执行拒绝策略"].allSatisfy({ first.referenceAnswer.contains($0) }),
                          result.unassignedExcerpts.isEmpty else { throw AppFailure("复合题自检发现小问、答案或归类结果不完整。") }
                }
                let report: [String: Any] = ["ok": true, "model": settings.model, "unassignedCount": result.unassignedExcerpts.count,
                    "compositeCheck": composite, "questions": result.rows.compactMap { row -> [String: String]? in
                    guard let q = row.question else { return nil }; return ["title": q.title, "answer": q.referenceAnswer]
                }]
                print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
                return
            }
            if arguments.contains("--test-ai") {
                let db = try runtimeDatabase()
                guard var settings = try db.aiSettings() else { throw AppFailure("尚未配置 AI。") }
                if arguments.contains("--no-json-mode") { settings.jsonMode = false }
                let key = try await readKey(for: settings)
                let question = Samples.questions[0]
                let answer = "== 对基本类型比较值，对引用类型判断是否是同一个对象。Object.equals 默认也是判断同一对象，类可以重写 equals 定义逻辑相等。String.equals 比较字符内容。"
                let evaluation = try await AIClient.evaluate(question: question, answer: answer, settings: settings, apiKey: key)
                let report: [String: Any] = ["ok": true, "model": settings.model, "earned": evaluation.earned,
                    "maximum": question.effectiveCriteria.reduce(0) { $0 + $1.weight },
                    "criteriaCount": evaluation.criteria.count, "summary": evaluation.summary]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
                return
            }
            OneQuestionApp.main()
        } catch {
            FileHandle.standardError.write(Data(("操作失败：\(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }
    private static func readKey(for settings: AISettings) async throws -> String {
        guard let account = settings.credentialAccount else { return "" }
        return try await BackgroundOperation.run(timeoutMessage: "钥匙串读取超时，请在新版设置中重新输入密钥并保存。") {
            try Keychain.read(account: account, allowInteraction: false)
        }
    }
    private static func runtimeDatabase() throws -> Database {
        let directory: URL
        if let path = ProcessInfo.processInfo.environment["ONEQUESTION_DATA_DIR"] {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("OneQuestion", isDirectory: true)
        }
        return try Database(url: directory.appendingPathComponent("questions.sqlite3"))
    }
}

private struct ConfigurationInput: Decodable {
    var settings: AISettings
    var apiKey: String
}
