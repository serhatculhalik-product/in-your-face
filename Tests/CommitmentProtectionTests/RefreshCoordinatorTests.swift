import XCTest
@testable import CommitmentProtection

@MainActor
final class RefreshCoordinatorTests: XCTestCase {
    func testEnqueueCoalescesRecoveryBurstToTheCurrentFollowUp() async {
        let coordinator = RefreshCoordinator()
        let gate = RefreshCoordinatorGate()
        var executedRequests: [RefreshCoordinator.Request] = []

        coordinator.enqueue(at: Date(timeIntervalSince1970: 1), intent: .recovery) { request in
            executedRequests.append(request)
            await gate.markStartedAndWaitForRelease()
        }
        await gate.waitForStart()

        coordinator.enqueue(at: Date(timeIntervalSince1970: 2), intent: .recovery) { request in
            executedRequests.append(request)
        }
        coordinator.enqueue(at: Date(timeIntervalSince1970: 3), intent: .recovery) { request in
            executedRequests.append(request)
        }
        coordinator.enqueue(at: Date(timeIntervalSince1970: 4), intent: .recovery) { request in
            executedRequests.append(request)
        }

        let drain = Task { @MainActor in
            await coordinator.drain()
        }
        await gate.release()
        await drain.value

        XCTAssertEqual(executedRequests.count, 2)
        XCTAssertEqual(executedRequests.map(\.intent), [.recovery, .recovery])
        XCTAssertEqual(executedRequests.last?.date, Date(timeIntervalSince1970: 4))
    }
}

private actor RefreshCoordinatorGate {
    private var hasStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func markStartedAndWaitForRelease() async {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
