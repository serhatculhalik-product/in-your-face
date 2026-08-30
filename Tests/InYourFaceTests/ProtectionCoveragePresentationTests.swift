import AppKit
import CommitmentProtection
import SwiftUI
import XCTest
@testable import InYourFace

final class ProtectionCoveragePresentationTests: XCTestCase {
    func testEverySemanticStateUsesTheCanonicalPresentationContract() {
        XCTAssertEqual(ProtectionCoveragePresentation.State.allCases.count, contract.count)

        for state in ProtectionCoveragePresentation.State.allCases {
            XCTAssertNotNil(
                contract.first(where: { $0.state == state }),
                "Missing canonical test expectation for \(state)."
            )
        }

        for expectation in contract {
            XCTAssertTrue(
                ProtectionCoveragePresentation.State.allCases.contains(expectation.state),
                "The canonical contract includes an undeclared presentation state."
            )
            assertPresentation(
                ProtectionCoveragePresentation(state: expectation.state),
                matches: expectation
            )
        }
    }

    func testEveryContractSymbolResolvesAsATemplateImageOnTheCurrentSupportedRuntime() throws {
        for state in ProtectionCoveragePresentation.State.allCases {
            let presentation = ProtectionCoveragePresentation(state: state)

            let image = try XCTUnwrap(
                NSImage(
                    systemSymbolName: presentation.systemImage,
                    accessibilityDescription: presentation.label
                ),
                "Missing SF Symbol \(presentation.systemImage) for \(presentation.label)"
            )
            XCTAssertTrue(image.isTemplate)
        }
    }

    @MainActor
    func testEverySharedStatusRendersWithoutCollapsing() {
        for state in ProtectionCoveragePresentation.State.allCases {
            let presentation = ProtectionCoveragePresentation(state: state)
            let host = NSHostingView(
                rootView: HStack(spacing: 6) {
                    ProtectionCoverageStatusLabel(presentation: presentation)
                    if presentation.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                }
                .fixedSize()
            )
            host.layoutSubtreeIfNeeded()

            XCTAssertGreaterThan(host.fittingSize.width, 20, presentation.label)
            XCTAssertGreaterThan(host.fittingSize.height, 10, presentation.label)
        }
    }

    func testAccountCoverageHealthMapsToItsExactScopedState() {
        let cases: [(CoverageHealth, ProtectionCoveragePresentation.State)] = [
            (.noCoverage, .noCoverage),
            (.checking, .checkingCoverage),
            (.fresh, .freshCoverage),
            (.stale, .staleCoverage),
            (.reconnectRequired, .reconnectRequired),
            (.unavailable("Refresh failed"), .coverageUnavailable),
        ]

        for (health, expectedState) in cases {
            assertPresentation(
                ProtectionCoveragePresentation.account(health),
                matchesState: expectedState
            )
        }
    }

    func testReconnectConnectionStateTakesPresentationPrecedenceOverCoverageErrors() {
        assertPresentation(
            ProtectionCoveragePresentation.account(
                .unavailable("Protected data could not be read"),
                requiresReconnect: true
            ),
            matchesState: .reconnectRequired
        )
        assertPresentation(
            ProtectionCoveragePresentation.account(.stale),
            matchesState: .staleCoverage
        )
        assertPresentation(
            ProtectionCoveragePresentation.account(.unavailable("Refresh failed")),
            matchesState: .coverageUnavailable
        )
    }

    func testGlobalResolutionUsesTheAuthoritativePrecedenceOrder() {
        let cases: [GlobalExpectation] = [
            .init(
                description: "restore dominates every other input",
                isRestoringConnection: true,
                needsSetup: true,
                status: .active,
                isCheckingCoverage: true,
                isPaused: true,
                hasReconnectRequiredAccount: true,
                expectedState: .loadingProtection
            ),
            .init(
                description: "menu setup gate precedes domain status",
                needsSetup: true,
                status: .active,
                isCheckingCoverage: true,
                isPaused: true,
                hasReconnectRequiredAccount: true,
                expectedState: .finishSetup
            ),
            .init(
                description: "no coverage precedes pause, checking, and reconnect",
                status: .noCoverage,
                isCheckingCoverage: true,
                isPaused: true,
                hasReconnectRequiredAccount: true,
                expectedState: .noCoverage
            ),
            .init(
                description: "pause applies when protection is active",
                status: .active,
                isCheckingCoverage: true,
                isPaused: true,
                hasReconnectRequiredAccount: true,
                expectedState: .protectionPaused
            ),
            .init(
                description: "active protection precedes checking and account exceptions",
                status: .active,
                isCheckingCoverage: true,
                hasReconnectRequiredAccount: true,
                expectedState: .activeProtection
            ),
            .init(
                description: "checking precedes reconnect while unavailable",
                status: .unavailable,
                isCheckingCoverage: true,
                isPaused: true,
                hasReconnectRequiredAccount: true,
                expectedState: .checkingCoverage
            ),
            .init(
                description: "reconnect applies only after unavailable settles",
                status: .unavailable,
                isPaused: true,
                hasReconnectRequiredAccount: true,
                expectedState: .reconnectRequired
            ),
            .init(
                description: "other unavailable coverage uses the degraded summary",
                status: .unavailable,
                isPaused: true,
                expectedState: .coverageNeedsAttention
            ),
        ]

        for expectation in cases {
            let presentation = ProtectionCoveragePresentation.global(
                isRestoringConnection: expectation.isRestoringConnection,
                needsSetup: expectation.needsSetup,
                status: expectation.status,
                isCheckingCoverage: expectation.isCheckingCoverage,
                isPaused: expectation.isPaused,
                hasReconnectRequiredAccount: expectation.hasReconnectRequiredAccount
            )

            assertPresentation(
                presentation,
                matchesState: expectation.expectedState,
                message: expectation.description
            )
        }
    }

    func testFreshAccountKeepsGlobalProtectionActiveAlongsideEveryDegradedAccountState() {
        let degradedCases: [(CoverageHealth, ProtectionCoveragePresentation.State)] = [
            (.stale, .staleCoverage),
            (.reconnectRequired, .reconnectRequired),
            (.unavailable("Refresh failed"), .coverageUnavailable),
        ]

        for (degradedHealth, expectedAccountState) in degradedCases {
            // The domain flow reports `.active` when at least one confirmed account is fresh.
            let global = ProtectionCoveragePresentation.global(
                isRestoringConnection: false,
                needsSetup: false,
                status: .active,
                isCheckingCoverage: false,
                isPaused: false,
                hasReconnectRequiredAccount: degradedHealth == .reconnectRequired
            )

            assertPresentation(global, matchesState: .activeProtection)
            assertPresentation(
                ProtectionCoveragePresentation.account(degradedHealth),
                matchesState: expectedAccountState
            )
        }
    }

    private func assertPresentation(
        _ presentation: ProtectionCoveragePresentation,
        matchesState state: ProtectionCoveragePresentation.State,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let expectation = contract.first(where: { $0.state == state }) else {
            XCTFail("Missing test contract for \(state)", file: file, line: line)
            return
        }
        assertPresentation(
            presentation,
            matches: expectation,
            message: message,
            file: file,
            line: line
        )
    }

    private func assertPresentation(
        _ presentation: ProtectionCoveragePresentation,
        matches expectation: StateExpectation,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(presentation.state, expectation.state, message, file: file, line: line)
        XCTAssertEqual(presentation.label, expectation.label, message, file: file, line: line)
        XCTAssertEqual(
            presentation.systemImage, expectation.systemImage, message, file: file, line: line)
        XCTAssertEqual(presentation.tone, expectation.tone, message, file: file, line: line)
        XCTAssertEqual(
            presentation.showsProgress, expectation.showsProgress, message, file: file, line: line)
    }

    private var contract: [StateExpectation] {
        [
            .init(
                state: .loadingProtection,
                label: "Loading Protection",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .neutral,
                showsProgress: true
            ),
            .init(
                state: .finishSetup,
                label: "Finish Setup",
                systemImage: "shield.slash",
                tone: .neutral,
                showsProgress: false
            ),
            .init(
                state: .checkingCoverage,
                label: "Checking Coverage",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .neutral,
                showsProgress: true
            ),
            .init(
                state: .noCoverage,
                label: "No Coverage",
                systemImage: "shield.slash",
                tone: .neutral,
                showsProgress: false
            ),
            .init(
                state: .activeProtection,
                label: "Active Protection",
                systemImage: "checkmark.shield.fill",
                tone: .positive,
                showsProgress: false
            ),
            .init(
                state: .freshCoverage,
                label: "Fresh Coverage",
                systemImage: "checkmark.circle.fill",
                tone: .positive,
                showsProgress: false
            ),
            .init(
                state: .protectionPaused,
                label: "Protection Paused",
                systemImage: "pause.circle.fill",
                tone: .neutral,
                showsProgress: false
            ),
            .init(
                state: .staleCoverage,
                label: "Stale Coverage",
                systemImage: "calendar.badge.clock",
                tone: .caution,
                showsProgress: false
            ),
            .init(
                state: .reconnectRequired,
                label: "Reconnect Required",
                systemImage: "person.crop.circle.badge.exclamationmark",
                tone: .caution,
                showsProgress: false
            ),
            .init(
                state: .coverageUnavailable,
                label: "Coverage Unavailable",
                systemImage: "calendar.badge.exclamationmark",
                tone: .caution,
                showsProgress: false
            ),
            .init(
                state: .coverageNeedsAttention,
                label: "Coverage Needs Attention",
                systemImage: "calendar.badge.exclamationmark",
                tone: .caution,
                showsProgress: false
            ),
            .init(
                state: .unverifiedReminder,
                label: "Unverified Reminder",
                systemImage: "questionmark.circle",
                tone: .caution,
                showsProgress: false
            ),
            .init(
                state: .commitmentConflict,
                label: "Commitment Conflict",
                systemImage: "rectangle.3.group",
                tone: .neutral,
                showsProgress: false
            ),
            .init(
                state: .primary,
                label: "Primary",
                systemImage: "checkmark.circle",
                tone: .neutral,
                showsProgress: false
            ),
        ]
    }
}

private struct StateExpectation {
    let state: ProtectionCoveragePresentation.State
    let label: String
    let systemImage: String
    let tone: ProtectionCoveragePresentation.Tone
    let showsProgress: Bool

    init(
        state: ProtectionCoveragePresentation.State,
        label: String,
        systemImage: String,
        tone: ProtectionCoveragePresentation.Tone,
        showsProgress: Bool
    ) {
        self.state = state
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
        self.showsProgress = showsProgress
    }
}

private struct GlobalExpectation {
    let description: String
    var isRestoringConnection = false
    var needsSetup = false
    let status: ProtectionStatus
    var isCheckingCoverage = false
    var isPaused = false
    var hasReconnectRequiredAccount = false
    let expectedState: ProtectionCoveragePresentation.State
}
