import CommitmentProtection
import XCTest
@testable import InYourFace

final class AccountRowActionPresentationTests: XCTestCase {
    func testReconnectRequiredShowsReconnectWithoutDisconnect() {
        let presentation = AccountRowActionPresentation.make(
            connectionState: .reconnectRequired,
            isConnectingThisAccount: false
        )

        XCTAssertEqual(presentation.connectionAction, .reconnect)
        XCTAssertTrue(presentation.showsRemoveAccountAction)
    }

    func testConnectedAccountShowsDisconnectAndSeparateRemoveAction() {
        let presentation = AccountRowActionPresentation.make(
            connectionState: .connected,
            isConnectingThisAccount: false
        )

        XCTAssertEqual(presentation.connectionAction, .disconnect)
        XCTAssertTrue(presentation.showsRemoveAccountAction)
    }

    func testConnectingAccountReplacesActionsWithProgress() {
        let presentation = AccountRowActionPresentation.make(
            connectionState: .reconnectRequired,
            isConnectingThisAccount: true
        )

        XCTAssertEqual(presentation.connectionAction, .connecting)
        XCTAssertFalse(presentation.showsRemoveAccountAction)
    }

    func testFailedLiveSessionOffersDisconnectAndSeparateRemoveAction() {
        let presentation = AccountRowActionPresentation.make(
            connectionState: .failed("Refresh failed"),
            isConnectingThisAccount: false
        )

        XCTAssertEqual(presentation.connectionAction, .disconnect)
        XCTAssertTrue(presentation.showsRemoveAccountAction)
    }
}
