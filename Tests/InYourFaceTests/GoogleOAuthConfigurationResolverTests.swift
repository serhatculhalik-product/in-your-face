import Foundation
import XCTest
@testable import InYourFace

final class GoogleOAuthConfigurationResolverTests: XCTestCase {
    func testBundledOAuthConfigurationTakesPrecedenceOverEnvironment() {
        let configuration = GoogleOAuthConfigurationResolver.resolve(
            infoDictionary: [
                "GoogleOAuthClientID": "bundled-client-id",
                "GoogleOAuthClientSecret": "bundled-client-secret"
            ],
            environment: [
                "GOOGLE_OAUTH_CLIENT_ID": "environment-client-id",
                "GOOGLE_OAUTH_CLIENT_SECRET": "environment-client-secret"
            ]
        )

        XCTAssertEqual(configuration.clientID, "bundled-client-id")
        XCTAssertEqual(configuration.clientSecret, "bundled-client-secret")
    }

    func testEnvironmentSuppliesOAuthConfigurationWhenBundleValuesAreBlank() {
        let configuration = GoogleOAuthConfigurationResolver.resolve(
            infoDictionary: [
                "GoogleOAuthClientID": "  ",
                "GoogleOAuthClientSecret": "\n"
            ],
            environment: [
                "GOOGLE_OAUTH_CLIENT_ID": "environment-client-id",
                "GOOGLE_OAUTH_CLIENT_SECRET": "environment-client-secret"
            ]
        )

        XCTAssertEqual(configuration.clientID, "environment-client-id")
        XCTAssertEqual(configuration.clientSecret, "environment-client-secret")
    }

    func testMissingOAuthClientSecretRemainsOptional() {
        let configuration = GoogleOAuthConfigurationResolver.resolve(
            infoDictionary: ["GoogleOAuthClientID": "bundled-client-id"],
            environment: [:]
        )

        XCTAssertEqual(configuration.clientID, "bundled-client-id")
        XCTAssertNil(configuration.clientSecret)
    }

    func testPackagedAppTemplateProvidesOAuthClientSecretKey() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = repositoryRoot
            .appendingPathComponent("Resources/InYourFace.app/Contents/Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil)
                as? [String: Any]
        )

        XCTAssertNotNil(plist["GoogleOAuthClientSecret"] as? String)
    }
}
