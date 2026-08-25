import AppKit

enum WindowFrameFitter {
    static func centeredFrame(
        preferredSize: CGSize,
        minimumSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = 40
    ) -> CGRect {
        let visibleWidth = max(visibleFrame.width, 0)
        let visibleHeight = max(visibleFrame.height, 0)
        let minimumUsableWidth = min(
            max(minimumSize.width, min(visibleWidth, 1)),
            visibleWidth
        )
        let minimumUsableHeight = min(
            max(minimumSize.height, min(visibleHeight, 1)),
            visibleHeight
        )
        let horizontalMargin = min(
            max(margin, 0),
            max((visibleWidth - minimumUsableWidth) / 2, 0)
        )
        let verticalMargin = min(
            max(margin, 0),
            max((visibleHeight - minimumUsableHeight) / 2, 0)
        )
        let availableFrame = visibleFrame.insetBy(
            dx: horizontalMargin,
            dy: verticalMargin
        )
        let availableSize = availableFrame.size
        let resolvedMinimumSize = CGSize(
            width: min(max(minimumSize.width, 0), availableSize.width),
            height: min(max(minimumSize.height, 0), availableSize.height)
        )
        let resolvedPreferredSize = CGSize(
            width: preferredSize.width.isFinite ? max(preferredSize.width, 0) : availableSize.width,
            height: preferredSize.height.isFinite ? max(preferredSize.height, 0) : availableSize.height
        )
        let fittedSize = CGSize(
            width: min(max(resolvedPreferredSize.width, resolvedMinimumSize.width), availableSize.width),
            height: min(max(resolvedPreferredSize.height, resolvedMinimumSize.height), availableSize.height)
        )

        return CGRect(
            x: availableFrame.midX - fittedSize.width / 2,
            y: availableFrame.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    @MainActor
    static func fit(
        _ window: NSWindow?,
        on screen: NSScreen?,
        minimumContentSize: CGSize,
        margin: CGFloat = 40
    ) {
        guard let window, let screen = screen ?? NSScreen.main else { return }
        fit(
            window,
            visibleFrame: screen.visibleFrame,
            minimumContentSize: minimumContentSize,
            margin: margin
        )
    }

    @MainActor
    static func fit(
        _ window: NSWindow?,
        visibleFrame: CGRect,
        minimumContentSize: CGSize,
        margin: CGFloat = 40
    ) {
        guard let window else { return }

        window.contentView?.layoutSubtreeIfNeeded()
        let fittingContentSize = window.contentView?.fittingSize ?? window.contentLayoutRect.size
        let preferredContentSize = CGSize(
            width: fittingContentSize.width > 0
                ? fittingContentSize.width
                : window.contentLayoutRect.width,
            height: fittingContentSize.height > 0
                ? fittingContentSize.height
                : window.contentLayoutRect.height
        )
        let preferredFrameSize = window.frameRect(
            forContentRect: CGRect(origin: .zero, size: preferredContentSize)
        ).size
        let minimumFrameSize = window.frameRect(
            forContentRect: CGRect(origin: .zero, size: minimumContentSize)
        ).size
        let fittedFrame = centeredFrame(
            preferredSize: preferredFrameSize,
            minimumSize: minimumFrameSize,
            visibleFrame: visibleFrame,
            margin: margin
        )
        let maximumFrame = centeredFrame(
            preferredSize: CGSize(width: CGFloat.infinity, height: CGFloat.infinity),
            minimumSize: minimumFrameSize,
            visibleFrame: visibleFrame,
            margin: margin
        )

        window.maxSize = maximumFrame.size
        let currentFrame = window.frame
        let needsUpdate = abs(currentFrame.minX - fittedFrame.minX) > 0.5 ||
            abs(currentFrame.minY - fittedFrame.minY) > 0.5 ||
            abs(currentFrame.width - fittedFrame.width) > 0.5 ||
            abs(currentFrame.height - fittedFrame.height) > 0.5
        if needsUpdate {
            window.setFrame(fittedFrame, display: true)
        }
    }
}
