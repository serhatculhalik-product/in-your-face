import Foundation

@MainActor
final class RefreshCoordinator {
    enum Intent: Equatable, Sendable {
        case ordinary
        case recovery
    }

    struct Request: Equatable, Sendable {
        let id: UInt64
        let date: Date
        let intent: Intent
    }

    typealias Work = @MainActor (Request) async -> Void

    private var nextID: UInt64 = 0
    private var currentID: UInt64 = 0
    private var pendingRequest: Request?
    private var isRunning = false
    private var work: Work?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func submit(
        at date: Date,
        intent: Intent,
        work: @escaping Work
    ) async {
        self.work = work
        let pendingIntent = pendingRequest?.id == currentID
            ? pendingRequest?.intent
            : nil
        nextID &+= 1
        currentID = nextID
        let effectiveIntent: Intent = pendingIntent == .recovery || intent == .recovery
            ? .recovery
            : .ordinary
        pendingRequest = Request(id: currentID, date: date, intent: effectiveIntent)
        await waitForDrain()
    }

    func invalidate() {
        nextID &+= 1
        currentID = nextID
    }

    func isCurrent(_ request: Request) -> Bool {
        request.id == currentID
    }

    private func waitForDrain() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            pump()
        }
    }

    private func pump() {
        guard !isRunning,
              let request = pendingRequest,
              let work else {
            return
        }

        pendingRequest = nil
        isRunning = true
        Task { @MainActor [weak self] in
            await work(request)
            guard let self else { return }
            self.isRunning = false
            if self.pendingRequest != nil {
                self.pump()
            } else {
                self.resumeWaiters()
            }
        }
    }

    private func resumeWaiters() {
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}
