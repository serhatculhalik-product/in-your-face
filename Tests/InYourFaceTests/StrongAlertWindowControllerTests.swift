import AppKit
import SwiftUI
import XCTest
@testable import InYourFace

@MainActor
final class StrongAlertWindowControllerTests: XCTestCase {
    func testDisplayRecoveryRestartsApplicationActivationObservation() async throws {
        _ = NSApplication.shared
        let screens = NSScreen.screens
        try XCTSkipIf(screens.isEmpty, "Strong Alert display recovery requires a connected test display.")
        let registry = WindowRegistry()
        let notificationCenter = NotificationCenter()
        let screenProvider = MutableStrongAlertScreenProvider()
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            notificationCenter: notificationCenter,
            availableScreens: { screenProvider.screens }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            controller.close()
            window.close()
        }

        controller.present(content: AnyView(Text("Strong Alert")), surfaceDidClose: {})
        registry.register(window, for: .strongAlert)

        XCTAssertFalse(controller.isObservingApplicationActivation)

        screenProvider.screens = screens
        notificationCenter.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertTrue(controller.isObservingApplicationActivation)
    }

    func testPrimaryWindowIsFittedInitiallyAndAgainAfterHostedContentLayout() {
        _ = NSApplication.shared
        let registry = WindowRegistry()
        var scheduledFit: (@MainActor () -> Void)?
        var fittedWindows: [NSWindow] = []
        let controller = StrongAlertWindowController(
            windowRegistry: registry,
            scheduleAfterLayout: { scheduledFit = $0 },
            fitWindow: { window, _ in
                if let window {
                    fittedWindows.append(window)
                }
            }
        )
        let content = ConstraintUpdatingStrongAlertProbe()
        let hostingView = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer {
            controller.close()
            window.close()
        }

        controller.present(content: AnyView(content), surfaceDidClose: {})
        registry.register(window, for: .strongAlert)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(fittedWindows.filter { $0 === window }.count, 1)
        let deferredFit = scheduledFit
        XCTAssertNotNil(deferredFit)

        deferredFit?()

        XCTAssertEqual(fittedWindows.filter { $0 === window }.count, 2)
    }
}

@MainActor
private final class MutableStrongAlertScreenProvider {
    var screens: [NSScreen] = []
}

private struct ConstraintUpdatingStrongAlertProbe: View {
    @State private var measuredContentHeight: CGFloat = 280

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Strong Alert")
                    .font(.headline)
                Text("A commitment with enough content to exercise the production alert layout")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Button("Stop reminders") {}
                    .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ConstraintUpdatingHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 500, maxWidth: 620)
        .frame(height: min(measuredContentHeight, 680))
        .onPreferenceChange(ConstraintUpdatingHeightKey.self) { height in
            measuredContentHeight = max(240, height)
        }
    }
}

private struct ConstraintUpdatingHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 280

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
