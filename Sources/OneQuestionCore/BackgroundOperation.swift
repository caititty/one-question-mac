import Foundation

/// Runs blocking OS work off the UI thread and bounds how long callers wait.
/// The underlying system call may finish later; callers must use unique write IDs.
public enum BackgroundOperation {
    public static func run<Value>(timeout: TimeInterval = 8, timeoutMessage: String,
                                   operation: @escaping () throws -> Value) async throws -> Value {
        let completion = Completion<Value>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                DispatchQueue.global(qos: .userInitiated).async {
                    completion.finish(Result { try operation() })
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.001, timeout)) {
                    completion.finish(.failure(AppFailure(timeoutMessage)))
                }
            }
        }, onCancel: { completion.finish(.failure(CancellationError())) })
    }
}

private final class Completion<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var earlyResult: Result<Value, Error>?
    private var settled = false
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result = earlyResult {
            earlyResult = nil; lock.unlock(); continuation.resume(with: result)
        } else {
            self.continuation = continuation; lock.unlock()
        }
    }
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !settled else { lock.unlock(); return }
        settled = true
        let waiting = continuation; continuation = nil
        if waiting == nil { earlyResult = result }
        lock.unlock()
        waiting?.resume(with: result)
    }
}
