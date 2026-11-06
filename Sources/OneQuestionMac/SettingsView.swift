import SwiftUI
import AppKit
import OneQuestionCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settings = AISettings()
    @State private var key = ""
    @State private var message: String?
    @State private var isError = false
    @State private var isSaving = false
    @State private var isWarning = false
    @State private var withoutKey = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("AI 评价") {
                    Toggle("提交回答后自动评价", isOn: $settings.enabled)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("接口基础地址")
                        TextField("https://你的接口地址/v1", text: $settings.endpoint, axis: .vertical)
                            .lineLimit(2...3).textFieldStyle(.roundedBorder)
                    }
                    TextField("模型名称", text: $settings.model, prompt: Text("填写服务商提供的模型 ID"))
                    SecureField("API 密钥", text: $key, prompt: Text("输入新密钥；留空保留已有密钥"))
                        .disabled(withoutKey)
                    Toggle("此接口无需 API 密钥", isOn: $withoutKey)
                    Text("已有密钥不会自动读回显示。输入新密钥会保存为独立条目，留空保留同一服务的已有密钥。").font(.caption).foregroundStyle(.secondary)
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
            }.formStyle(.grouped).disabled(isSaving)
            Divider()
            if let message {
                Label(message, systemImage: isError ? "exclamationmark.circle" : isSaving ? "clock" : isWarning ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(isError ? Color.red : isWarning ? Color.orange : isSaving ? Color.secondary : Color.green)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    .padding(.horizontal, 18).padding(.top, 12)
            }
            HStack {
                Text("一题 · macOS 原生试用版 0.3.1").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button(isSaving ? "保存中…" : "保存设置") { save() }.buttonStyle(.borderedProminent).keyboardShortcut("s").disabled(isSaving)
            }.padding(18)
        }.frame(width: 620, height: 660)
        .onAppear {
            settings = store.settings; withoutKey = settings.credentialAccount == nil; key = ""
        }
    }
    private func save() {
        guard !isSaving else { return }
        isSaving = true; isError = false; isWarning = false; message = "正在保存设置与密钥，请稍候…"
        let configuration = settings, supplied = key, noKey = withoutKey
        Task {
            defer { isSaving = false }
            do {
                let outcome = try await store.saveSettings(configuration, key: supplied, withoutKey: noKey)
                settings = store.settings; key = ""; message = outcome.message; isWarning = outcome.warning
            } catch { message = error.localizedDescription; isError = true }
        }
    }
}
