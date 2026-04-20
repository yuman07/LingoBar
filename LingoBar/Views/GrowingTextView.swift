import AppKit

/// Scrollable text view with dynamic intrinsic height. Emits `onTextChange`
/// on edits and `onHeightChange` whenever the laid-out content height changes.
final class GrowingTextView: NSView {
    var onTextChange: ((String) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    let scrollView: NSScrollView
    let textView: FocusableTextView
    let placeholderLabel: NSTextField

    private let textContainerInset = NSSize(width: 8, height: 6)
    private var lastReportedHeight: CGFloat = -1

    var text: String {
        get { textView.string }
        set {
            guard textView.string != newValue else { return }
            textView.string = newValue
            updatePlaceholderVisibility()
            recomputeHeight()
        }
    }

    var placeholder: String = "" {
        didSet { placeholderLabel.stringValue = placeholder }
    }

    var isEditable: Bool = true {
        didSet { textView.isEditable = isEditable }
    }

    /// External clamp on how tall this view can get. Used to decide whether a
    /// vertical scroller is actually needed — when content fits within the
    /// clamp, we keep `hasVerticalScroller` off so AppKit has no scroller to
    /// fade in when the panel reopens. `autohidesScrollers` alone is not
    /// enough: overlay scrollers can still flash during layout / window
    /// visibility transitions.
    var maxVisibleHeight: CGFloat = .greatestFiniteMagnitude {
        didSet { syncScrollerVisibility() }
    }

    override init(frame: NSRect) {
        let textView = FocusableTextView(frame: .zero)
        let scrollView = QuietScrollView()
        scrollView.documentView = textView
        self.scrollView = scrollView
        self.textView = textView

        let label = NonInteractiveLabel(labelWithString: "")
        label.textColor = .tertiaryLabelColor
        label.font = .preferredFont(forTextStyle: .body)
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel = label

        super.init(frame: frame)

        configureScrollView()
        configureTextView()
        addSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .allowed
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureTextView() {
        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = textContainerInset
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private func addSubviews() {
        addSubview(scrollView)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: textContainerInset.height),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textContainerInset.width + 4),
        ])
    }

    override func layout() {
        super.layout()
        recomputeHeight()
    }

    fileprivate func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.string.isEmpty || textView.hasMarkedText()
    }

    private func recomputeHeight() {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = used.height + textContainerInset.height * 2
        let rounded = (height * 100).rounded() / 100
        guard rounded != lastReportedHeight else { return }
        lastReportedHeight = rounded
        onHeightChange?(rounded)
        syncScrollerVisibility()
    }

    private func syncScrollerVisibility() {
        let needs = lastReportedHeight > maxVisibleHeight
        if scrollView.hasVerticalScroller != needs {
            scrollView.hasVerticalScroller = needs
        }
    }
}

extension GrowingTextView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        updatePlaceholderVisibility()
        recomputeHeight()
        onTextChange?(textView.string)
    }
}

/// NSTextView that makes itself first responder on click and always defers
/// to `super.mouseDown` so standard cursor / selection behaviour is intact,
/// even after Cmd+A selects all.
final class FocusableTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        if let window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        super.becomeFirstResponder()
    }

    override var acceptsFirstResponder: Bool { true }

    private func enclosingGrowingTextView() -> GrowingTextView? {
        var next: NSView? = superview
        while let candidate = next {
            if let host = candidate as? GrowingTextView { return host }
            next = candidate.superview
        }
        return nil
    }

    // `textDidChange` doesn't fire for IME composition (marked text), so the
    // placeholder stays visible behind the candidate glyphs. Hook setMarkedText
    // / unmarkText to refresh the host view whenever composition state changes.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        enclosingGrowingTextView()?.updatePlaceholderVisibility()
    }

    override func unmarkText() {
        super.unmarkText()
        enclosingGrowingTextView()?.updatePlaceholderVisibility()
    }
}

/// Label that never participates in hit testing — clicks always pass through.
private final class NonInteractiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// NSScrollView that suppresses the "flash on appear" scroller behavior.
///
/// AppKit flashes overlay scrollers whenever the document becomes visible or
/// the content size changes — which, for a popover that re-shows and re-lays
/// out its text views every time it opens, reads as a scrollbar popping in
/// on every panel open. Stub `flashScrollers()` to a no-op. Real scrolling
/// (trackpad gesture, mouse wheel) still reveals the overlay scroller via
/// the NSScroller's own response to scroll events — that code path does not
/// go through `flashScrollers`.
private final class QuietScrollView: NSScrollView {
    override func flashScrollers() {}
}
