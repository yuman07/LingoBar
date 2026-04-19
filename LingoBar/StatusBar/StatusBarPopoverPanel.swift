import AppKit

/// Custom popover-style panel shown from the status-bar icon.
/// Replaces NSPopover because NSPopover auto-dims to its "inactive" appearance
/// the moment it resigns key — which is unavoidable system chrome — and that
/// looks bad when we want to *keep* the panel visible (lock mode). A borderless
/// non-activating NSPanel backed by an always-active NSVisualEffectView renders
/// identically whether it holds key status or not. The effect view is masked
/// into a rounded-rect + upward-arrow shape so it reads as a popover.
@MainActor
final class StatusBarPopoverPanel: NSPanel {
    private static let arrowHeight: CGFloat = 8
    private static let arrowHalfWidth: CGFloat = 8
    private static let cornerRadius: CGFloat = 11

    private let effectView: PopoverShapeEffectView
    private let contentContainer: NSView

    init(contentViewController: NSViewController) {
        let effect = PopoverShapeEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.arrowHeight = Self.arrowHeight
        effect.arrowHalfWidth = Self.arrowHalfWidth
        effect.cornerRadius = Self.cornerRadius
        self.effectView = effect

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        self.contentContainer = container

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260 + Self.arrowHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow

        contentView = effect
        effect.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: effect.topAnchor, constant: Self.arrowHeight),
            container.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])

        embed(contentViewController)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        if SharedEnvironment.shared.appState?.isPanelLocked == true { return }
        close()
    }

    private func embed(_ vc: NSViewController) {
        let child = vc.view
        child.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            child.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])
    }

    /// Position the panel so the arrow tip points at the bottom-center of the
    /// given screen-coordinate rect (typically the status-item button's frame).
    func anchor(below rect: NSRect, gap: CGFloat = 2) {
        let width = frame.width
        let topLeftX = rect.midX - width / 2
        let topLeftY = rect.minY - gap
        setFrameTopLeftPoint(NSPoint(x: topLeftX, y: topLeftY))
        // Icon midX in panel-local coords = icon midX on screen − panel origin X.
        // When the panel is centered on the icon this equals width/2, but screen
        // edges can push the panel sideways — recompute so the arrow still
        // points at the icon.
        effectView.arrowCenterX = rect.midX - frame.minX
    }

    /// Set preferred content size of the embedded VC (excludes arrow chrome).
    func setPreferredContentSize(_ size: NSSize) {
        setContentSize(NSSize(width: size.width, height: size.height + Self.arrowHeight))
    }
}

/// NSVisualEffectView shaped into a rounded rect with an upward-pointing arrow
/// along the top edge. The mask regenerates on layout so the shape tracks
/// bounds and arrow position changes.
@MainActor
final class PopoverShapeEffectView: NSVisualEffectView {
    var arrowHeight: CGFloat = 8 { didSet { needsLayout = true } }
    var arrowHalfWidth: CGFloat = 8 { didSet { needsLayout = true } }
    var cornerRadius: CGFloat = 11 { didSet { needsLayout = true } }
    /// Fraction of each arrow edge replaced by a rounded cubic curve at the
    /// tip. 0 = sharp point. Larger values soften the tip.
    var arrowTipRoundingFraction: CGFloat = 0.55 { didSet { needsLayout = true } }
    var arrowCenterX: CGFloat = 0 {
        didSet {
            guard oldValue != arrowCenterX else { return }
            needsLayout = true
        }
    }

    private var lastMaskedSize: NSSize = .zero
    private var lastMaskedArrowX: CGFloat = -1

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        if size == lastMaskedSize && arrowCenterX == lastMaskedArrowX { return }
        lastMaskedSize = size
        lastMaskedArrowX = arrowCenterX
        maskImage = makeMaskImage(size: size)
        window?.invalidateShadow()
    }

    private func makeMaskImage(size: NSSize) -> NSImage {
        let ah = arrowHeight
        let ahw = arrowHalfWidth
        let r = cornerRadius
        let tt = min(max(arrowTipRoundingFraction, 0), 0.9)
        let minCX = ahw + r
        let maxCX = size.width - ahw - r
        let cx = max(minCX, min(maxCX, arrowCenterX))

        return NSImage(size: size, flipped: false) { rect in
            let bodyRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - ah)
            let path = NSBezierPath(roundedRect: bodyRect, xRadius: r, yRadius: r)

            let tipY = rect.height
            let baseY = rect.height - ah
            // Straight portion of each edge ends at `trim` before the virtual
            // tip. A cubic curve with both control points at the virtual tip
            // stitches the two straight ends into a smooth rounded cap.
            let trimX = ahw * tt
            let trimY = ah * tt
            let leftCurveStart = NSPoint(x: cx - trimX, y: tipY - trimY)
            let rightCurveStart = NSPoint(x: cx + trimX, y: tipY - trimY)
            let cp = NSPoint(x: cx, y: tipY)

            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: cx - ahw, y: baseY))
            arrow.line(to: leftCurveStart)
            arrow.curve(to: rightCurveStart, controlPoint1: cp, controlPoint2: cp)
            arrow.line(to: NSPoint(x: cx + ahw, y: baseY))
            arrow.close()
            path.append(arrow)

            NSColor.black.set()
            path.fill()
            return true
        }
    }
}
