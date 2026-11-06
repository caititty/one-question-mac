import SwiftUI
import AppKit
import OneQuestionCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settings = AISettings()
    @State private var key = ""
    @State private var message: String?
    @State private var isError = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("AI 评价") {
                    Toggle("提交回答后自动评价", isOn: $settings.enabled)
                    TextField("接口基础地址", text: $settings.endpoint, prompt: Text("https://你的接口地址/v1"))
                    TextField("模型名称", text: $settings.model, prompt: Text("填写服务商提供的模型 ID"))
                    SecureField("API 密钥", text: $key, prompt: Text("本地模型可留空"))
                    Toggle("请求 JSON 模式", isOn: $settings.jsonMode)
                    Text("支持 Chat Completions 兼容接口。地址填写到 /v1，或填写完整 /chat/completions 路径。部分服务不支持 JSON 模式时可关闭。").font(.caption).foregroundStyle(.secondary)
                }
                Section("数据与隐私") {
                    Text("题库、草稿和作答记录保存在本机。API 密钥保存在 macOS 钥匙串中。")
                    Text("启用 AI 后，每次评价会将本题、参考答案、评分要点和本次回答发送到你配置的服务；不会发送整个题库。").font(.callout).foregroundStyle(.secondary)
                    Text("主动使用 AI 整理时，会发送当前 PDF 的提取文字或所选题目文字，以区分问题与原文答案；本地 OCR 本身不联网。").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("打开数据目录") { NSWorkspace.shared.open(store.dataDirectory) }
                        Button("打开导入模板") { NSWorkspace.shared.open(templateDirectory()) }
                    }
                }
                if let message { Text(message).foregroundStyle(isError ? Color.red : Color.secondary) }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Text("一题 · macOS 原生试用版 0.3").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("保存设置") { save() }.buttonStyle(.borderedProminent).keyboardShortcut("s")
            }.padding(18)
        }.frame(width: 590, height: 570)
        .onAppear {
            settings = store.settings
            do { key = try Keychain.read() } catch { message = error.localizedDescription; isError = true }
        }
    }
    private func save() {
        do { try store.saveSettings(settings, key: key); message = "设置已保存。下一次提交会使用新配置。"; isError = false }
        catch { message = error.localizedDescription; isError = true }
    }
}
