import AppKit
import Combine

final class MainContentViewController: NSViewController {
    var onPreferredSizeChange: ((NSSize) -> Void)?

    private var segmented: NSSegmentedControl!
    private var tabBar: NSStackView!
    private var divider: NSBox!
    private var containerView: NSView!
    private let translationVC = TranslationViewController()
    private let historyVC = HistoryViewController()
    private var cancellables: Set<AnyCancellable> = []
    private var lastReportedSize: NSSize = .zero

    private var appState: AppState { SharedEnvironment.shared.appState! }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(translationVC)
        addChild(historyVC)
        showTranslate()

        appState.$activeTab
            .removeDuplicates()
            .sink { [weak self] tab in
                self?.applyTab(tab)
            }
            .store(in: &cancellables)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // `view.fittingSize` reads the current stretched layout, not the natural
        // minimum: if the window is currently taller than needed, the tabBar
        // absorbs the slack and fittingSize keeps reporting the old height —
        // so the popover never shrinks back after the content shrinks. Sum
        // the children's own fittingSize instead to get the true minimum.
        let content = 8 + tabBar.fittingSize.height + 6 + divider.fittingSize.height + containerView.fittingSize.height
        let size = NSSize(width: 380, height: max(170, content))
        guard size != lastReportedSize else { return }
        lastReportedSize = size
        preferredContentSize = size
        onPreferredSizeChange?(size)
    }

    // MARK: - Layout

    private func buildLayout() {
        segmented = NSSegmentedControl(labels: [
            String(localized: "Translate"),
            String(localized: "History"),
        ], trackingMode: .selectOne, target: self, action: #selector(tabChanged))
        segmented.selectedSegment = 0
        segmented.segmentStyle = .texturedSquare
        segmented.translatesAutoresizingMaskIntoConstraints = false

        tabBar = NSStackView(views: [segmented, NSView()])
        tabBar.orientation = .horizontal
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBar)
        view.addSubview(divider)
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            divider.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 6),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            containerView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // AppKit lowers required constraints on the window/popover's top-level
            // content view to priority 501, so pinning width on `view` lets the
            // content shrink when fittingSize drops (e.g. during translation while
            // the output body is just a spinner). Anchor width on a child view
            // instead — child constraints keep their priority.
            containerView.widthAnchor.constraint(equalToConstant: 380),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])

        // Safety net: even if AppKit lowers this one, the child containerView's
        // required width=380 still wins; but this stops the popover/panel from
        // ever growing the content view wider than 380 under edge conditions.
        let maxWidth = view.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        maxWidth.priority = .required
        maxWidth.isActive = true
    }

    // MARK: - Tabs

    @objc private func tabChanged() {
        let tab: AppState.Tab = segmented.selectedSegment == 0 ? .translate : .history
        appState.activeTab = tab
    }

    private func applyTab(_ tab: AppState.Tab) {
        switch tab {
        case .translate:
            segmented.selectedSegment = 0
            showTranslate()
        case .history:
            segmented.selectedSegment = 1
            showHistory()
        }
    }

    private func showTranslate() {
        swap(to: translationVC.view)
    }

    private func showHistory() {
        swap(to: historyVC.view)
    }

    private func swap(to child: NSView) {
        for sub in containerView.subviews { sub.removeFromSuperview() }
        child.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: containerView.topAnchor),
            child.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])
        view.needsLayout = true
    }
}
