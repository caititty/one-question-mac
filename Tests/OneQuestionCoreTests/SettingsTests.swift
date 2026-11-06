import Testing
import Foundation
@testable import OneQuestionCore

struct SettingsTests {
    @Test @MainActor func blockingWorkRunsOffTheUIThread() async throws {
        let isMain = try await BackgroundOperation.run(timeoutMessage: "timeout") { Thread.isMainThread }
        #expect(isMain == false)
    }
    @Test func deadlineReturnsBeforeBlockedWorkFinishes() async throws {
        let gate = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        await #expect(throws: AppFailure.self) {
            try await BackgroundOperation.run(timeout: 0.02, timeoutMessage: "deadline") {
                _ = gate.wait(timeout: .now() + 1); finished.signal(); return 7
            }
        }
        #expect(isSignalled(finished) == false)
    }
    @Test func cancellationDoesNotWaitForBlockedSystemCall() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let task = Task {
            try await BackgroundOperation.run(timeout: 2, timeoutMessage: "deadline") {
                _ = gate.wait(timeout: .now() + 1); return 3
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func lateCompletionAfterDeadlineIsIgnored() async throws {
        let gate = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        await #expect(throws: AppFailure.self) {
            try await BackgroundOperation.run(timeout: 0.02, timeoutMessage: "deadline") {
                _ = gate.wait(timeout: .now() + 1); finished.signal(); return 9
            }
        }
        gate.signal()
        let status = try await BackgroundOperation.run(timeout: 2, timeoutMessage: "worker did not finish") {
            finished.wait(timeout: .now() + 1) == .success
        }
        #expect(status)
    }
    @Test func oldConfigurationDecodesAndRetainsItsCredential() throws {
        let json = #"{"enabled":true,"endpoint":"https://first.example/v1","model":"example-model","jsonMode":true}"#
        let old = try JSONDecoder().decode(AISettings.self, from: Data(json.utf8))
        #expect(old.credentialID == nil)
        #expect(old.credentialAccount == "api-key")
        var changed = old; changed.model = "another-model"
        let prepared = try changed.preparedForSaving(previous: old, suppliedKey: "", withoutKey: false)
        #expect(prepared.credentialAccount == old.credentialAccount)
    }
    @Test func newKeysGetIndependentReferencesWithoutEncodingTheSecret() throws {
        var config = AISettings(); config.endpoint = "https://first.example/v1"; config.model = "example-model"
        let a = try config.preparedForSaving(previous: config, suppliedKey: "dummy-input-for-test", withoutKey: false)
        let b = try config.preparedForSaving(previous: a, suppliedKey: "another-dummy-input", withoutKey: false)
        #expect(a.credentialID != nil)
        #expect(a.credentialAccount != b.credentialAccount)
        #expect(String(decoding: try JSONEncoder().encode(a), as: UTF8.self).contains("dummy-input-for-test") == false)
    }
    @Test func changingProviderRequiresANewKeyOrExplicitKeylessMode() throws {
        var previous = AISettings(); previous.endpoint = "https://first.example/v1"; previous.model = "model"
        var changed = previous; changed.endpoint = "https://second.example/v1"
        #expect(throws: AppFailure.self) { try changed.preparedForSaving(previous: previous, suppliedKey: "", withoutKey: false) }
        let keyless = try changed.preparedForSaving(previous: previous, suppliedKey: "", withoutKey: true)
        #expect(keyless.credentialAccount == nil)
    }
    @Test func legacyAppWritesCannotOverwriteNewCredentialReferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try Database(url: directory.appendingPathComponent("settings.sqlite3"))
        var legacy = AISettings(); legacy.endpoint = "https://first.example/v1"; legacy.model = "legacy"
        try db.set(legacy, for: "ai-settings")
        #expect(try db.aiSettings()?.model == "legacy")
        var current = legacy; current.model = "current"; current.credentialID = UUID().uuidString
        try db.saveAISettings(current)
        // A still-running old app only knows the original preference key.
        legacy.model = "old-app-wrote-again"; try db.set(legacy, for: "ai-settings")
        #expect(try db.aiSettings()?.model == "current")
        #expect(try db.aiSettings()?.credentialID == current.credentialID)
    }
    private func isSignalled(_ semaphore: DispatchSemaphore) -> Bool { semaphore.wait(timeout: .now()) == .success }
}
