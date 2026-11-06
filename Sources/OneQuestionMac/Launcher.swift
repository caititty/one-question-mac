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
                try Keychain.save(configuration.apiKey.trimmed)
                try db.set(configuration.settings, for: "ai-settings")
                let verified = try Keychain.read() == configuration.apiKey.trimmed
                guard verified else { throw AppFailure("密钥保存后验证失败。") }
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("OneQuestionAISettingsChanged"), object: nil, userInfo: nil, deliverImmediately: true)
                print("AI 配置已保存；钥匙串读回验证通过。")
                print("接口：\(configuration.settings.endpoint)")
                print("模型：\(configuration.settings.model)")
                return
            }
            if arguments.contains("--test-ai") {
                let db = try runtimeDatabase()
                guard var settings = try db.get(AISettings.self, for: "ai-settings") else { throw AppFailure("尚未配置 AI。") }
                if arguments.contains("--no-json-mode") { settings.jsonMode = false }
                let key = try Keychain.read()
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
