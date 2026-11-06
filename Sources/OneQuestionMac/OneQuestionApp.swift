import SwiftUI
import AppKit
import OneQuestionCore

struct OneQuestionApp: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("一题", id: "practice") {
            PracticeView().environmentObject(store)
                .background(WindowIdentity(pinned: store.pinned))
                .onAppear { delegate.importFile = { store.loadImport($0) } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in store.persistDraftNow() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.reloadAISettings() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.persistDraftNow() }
                .alert("操作提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("知道了") { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
                .sheet(isPresented: $store.showImportPreview) { ImportPreviewView().environmentObject(store) }
        }
        .defaultSize(width: 590, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入题库…") { store.openImportPanel() }.keyboardShortcut("o")
                Button("导出题库…") { store.exportQuestions() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            NavigationCommands()
        }
        Window("题库管理", id: "library") {
            LibraryView().environmentObject(store)
        }.defaultSize(width: 940, height: 650)
        Window("答题记录", id: "history") {
            HistoryView().environmentObject(store)
        }.defaultSize(width: 900, height: 650)
        Window("一题设置", id: "preferences") {
            SettingsView().environmentObject(store)
        }.defaultSize(width: 570, height: 540).windowResizability(.contentSize)
        MenuBarExtra("一题", systemImage: "rectangle.stack") {
            AppMenu().environmentObject(store)
        }
    }
}

private struct NavigationCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { openWindow(id: "preferences"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut(",")
        }
        CommandMenu("练习") {
            Button("显示答题卡") { openWindow(id: "practice"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut("1")
            Button("题库管理") { openWindow(id: "library") }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("答题记录") { openWindow(id: "history") }.keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }
}

private struct AppMenu: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("显示答题卡") { show("practice") }
        Button("题库管理") { show("library") }
        Button("导入题库…") { show("practice"); store.openImportPanel() }
        Button("答题记录") { show("history") }
        Divider()
        Button("设置…") { show("preferences") }
        Button("退出一题") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func show(_ id: String) { openWindow(id: id); NSApp.activate(ignoringOtherApps: true) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURL: URL?
    var importFile: ((URL) -> Void)? {
        didSet { if let url = pendingURL, let importFile { pendingURL = nil; importFile(url) } }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { if let importFile { importFile(url) } else { pendingURL = url } }
    }
}

private struct WindowIdentity: NSViewRepresentable {
    let pinned: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.identifier = NSUserInterfaceItemIdentifier("practice-window")
            view.window?.level = pinned ? .floating : .normal
        }
    }
}
