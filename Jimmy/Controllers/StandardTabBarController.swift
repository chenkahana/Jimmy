import UIKit
import SwiftUI
import Combine
import Observation
import os

private final class MiniPlayerHostingController: UIHostingController<AnyView> {
    private let chrome: ShellChromeModel

    init(rootView: AnyView, chrome: ShellChromeModel) {
        self.chrome = chrome
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshAccessoryEnvironment()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshAccessoryEnvironment()
    }

    private func refreshAccessoryEnvironment() {
        if #available(iOS 26.0, *) {
            chrome.updateAccessoryEnvironment(traitCollection.tabAccessoryEnvironment)
        } else {
            chrome.isMiniPlayerInline = false
        }
    }
}

final class StandardTabBarController: UITabBarController, UITabBarControllerDelegate {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "StandardTabBarController")

    private let shell = ShellStore.shared
    private let chrome = ShellStore.shared.chrome
    private let tracker = InteractionLatencyTracker.shared
    private let audioPlayer = AudioPlayerService.shared

    private var miniPlayerHostingController: MiniPlayerHostingController?
    private var miniPlayerContainerView: UIView?
    private var miniPlayerHeightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingShellSelection = false
    private var hasFinishedInitialShellRender = false

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 26.0, *) {
            mode = .tabBar
        }

        tracker.beginShellFirstRender()
        setupTabs()
        configureTabBarAppearance()
        setupMiniPlayer()
        setupMiniPlayerBindings()
        setupShellObservation()
        setupChromeObservation()
        setupFileImportObserver()
        delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasFinishedInitialShellRender else {
            return
        }

        tracker.endShellFirstRender()
        hasFinishedInitialShellRender = true
    }

    private func setupTabs() {
        let queueTab = UITab(
            title: "Queue",
            image: UIImage(systemName: "list.bullet"),
            identifier: ShellTab.queue.identifier
        ) { [weak self] _ in
            guard let self else {
                return UIViewController()
            }
            return self.createSwiftUIViewController(view: QueueView())
        }

        let libraryTab = UITab(
            title: "Library",
            image: UIImage(systemName: "music.note.list"),
            identifier: ShellTab.library.identifier
        ) { [weak self] _ in
            guard let self else {
                return UIViewController()
            }
            return self.createSwiftUIViewController(view: LibraryView())
        }

        let discoverTab = UITab(
            title: "Discover",
            image: UIImage(systemName: "magnifyingglass"),
            identifier: ShellTab.discover.identifier
        ) { [weak self] _ in
            guard let self else {
                return UIViewController()
            }
            return self.createSwiftUIViewController(view: DiscoverView())
        }

        let settingsTab = UITab(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            identifier: ShellTab.settings.identifier
        ) { [weak self] _ in
            guard let self else {
                return UIViewController()
            }
            return self.createSwiftUIViewController(view: SettingsView())
        }

        tabs = [queueTab, libraryTab, discoverTab, settingsTab]
        applyShellSelection(shell.selectedTab)
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    private func setupMiniPlayer() {
        let miniPlayerView = applySharedEnvironment(
            to: NativeMiniPlayerView(onTap: { [weak self] in
            Task {
                await MiniPlayerTip.openedNowPlaying.donate()
            }
            self?.shell.present(.nowPlaying)
            })
        )

        let hostingController = MiniPlayerHostingController(
            rootView: AnyView(miniPlayerView),
            chrome: chrome
        )
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)

        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.translatesAutoresizingMaskIntoConstraints = false

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: miniPlayerHeight)
        heightConstraint.isActive = true
        miniPlayerHeightConstraint = heightConstraint

        view.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: tabBar.topAnchor)
        ])

        hostingController.didMove(toParent: self)
        miniPlayerContainerView = containerView
        miniPlayerHostingController = hostingController
        updateMiniPlayerVisibility(animated: false)
    }

    private func setupMiniPlayerBindings() {
        audioPlayer.$currentEpisode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] episode in
                guard let self else {
                    return
                }
                self.chrome.showsMiniPlayer = episode != nil
                self.updateMiniPlayerVisibility(animated: true)
            }
            .store(in: &cancellables)
    }

    private func updateMiniPlayerVisibility(animated: Bool) {
        let shouldShow = audioPlayer.currentEpisode != nil
        chrome.showsMiniPlayer = shouldShow

        guard let miniPlayerContainerView else {
            return
        }

        if #available(iOS 26.0, *), bottomAccessory != nil {
            setBottomAccessory(nil, animated: false)
        }

        if animated {
            UIView.animate(withDuration: 0.22) {
                miniPlayerContainerView.alpha = shouldShow ? 1 : 0
            } completion: { _ in
                miniPlayerContainerView.isHidden = !shouldShow
                self.updateHostedContentBottomInset(isMiniPlayerVisible: shouldShow)
            }
        } else {
            miniPlayerContainerView.alpha = shouldShow ? 1 : 0
            miniPlayerContainerView.isHidden = !shouldShow
            updateHostedContentBottomInset(isMiniPlayerVisible: shouldShow)
        }
    }

    private func setupShellObservation() {
        observeShellState()
    }

    private func observeShellState() {
        withObservationTracking { [weak self] in
            guard let self else {
                return
            }
            _ = self.shell.selectedTab
            _ = self.shell.presentation
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.applyObservedShellState()
                self.observeShellState()
            }
        }

        applyObservedShellState()
    }

    private func applyObservedShellState() {
        applyShellSelection(shell.selectedTab)
        chrome.isPresentingModal = shell.presentation != nil || presentedViewController != nil
    }

    private func setupChromeObservation() {
        observeChromeState()
    }

    private func observeChromeState() {
        withObservationTracking { [weak self] in
            guard let self else {
                return
            }
            _ = self.chrome.prefersTabBarMinimization
            _ = self.chrome.isMiniPlayerInline
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyChromeState()
                self?.observeChromeState()
            }
        }

        applyChromeState()
    }

    private func applyChromeState() {
        miniPlayerHeightConstraint?.constant = miniPlayerHeight
        miniPlayerContainerView?.setNeedsLayout()
        miniPlayerContainerView?.layoutIfNeeded()

        guard #available(iOS 26.0, *) else {
            return
        }

        tabBarMinimizeBehavior = chrome.prefersTabBarMinimization ? .onScrollDown : .never
    }

    private func applyShellSelection(_ tab: ShellTab) {
        guard let uiTab = tabs.first(where: { $0.identifier == tab.identifier }),
              selectedTab?.identifier != tab.identifier else {
            updateHostedContentBottomInset(isMiniPlayerVisible: audioPlayer.currentEpisode != nil)
            return
        }

        if selectedTab != nil {
            tracker.beginTabSwitch()
        }

        isApplyingShellSelection = true
        selectedTab = uiTab
        isApplyingShellSelection = false
        updateHostedContentBottomInset(isMiniPlayerVisible: audioPlayer.currentEpisode != nil)
        tracker.endTabSwitch(tab: tab)
    }

    private func createSwiftUIViewController<Content: View>(view: Content) -> UIViewController {
        let rootView = NavigationStack {
            view
        }
        .modifier(SharedShellEnvironmentModifier(shell: shell, chrome: chrome, tracker: tracker))

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .systemBackground
        return hostingController
    }

    private func setupFileImportObserver() {
        BulletproofAudioImporter.shared.$pendingURL
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] url in
                self?.presentImportSheet(for: url)
            }
            .store(in: &cancellables)
    }

    private func presentImportSheet(for url: URL) {
        let importView = BulletproofImportView(
            audioURL: url,
            onSuccess: { [weak self] _ in
                self?.dismiss(animated: true) {
                    BulletproofAudioImporter.shared.pendingURL = nil
                    self?.chrome.isPresentingModal = false
                    Motion.mediumHaptic()
                }
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true) {
                    BulletproofAudioImporter.shared.pendingURL = nil
                    self?.chrome.isPresentingModal = false
                }
            }
        )

        let hostingController = UIHostingController(
            rootView: applySharedEnvironment(to: importView)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        )
        hostingController.modalPresentationStyle = .pageSheet
        chrome.isPresentingModal = true

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
        }

        hostingController.presentationController?.delegate = self

        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.chrome.isPresentingModal = true
                self?.present(hostingController, animated: true)
            }
        } else {
            present(hostingController, animated: true)
        }
    }

    func navigate(to tabIdentifier: String) {
        guard let tab = ShellTab(identifier: tabIdentifier) else {
            return
        }
        shell.navigate(to: tab.destination)
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        guard !isApplyingShellSelection else {
            return true
        }

        shell.handleUserSelectedTab(identifier: tab.identifier)
        return true
    }

    private func applySharedEnvironment<Content: View>(to view: Content) -> some View {
        view.modifier(SharedShellEnvironmentModifier(shell: shell, chrome: chrome, tracker: tracker))
    }

    private var miniPlayerHeight: CGFloat {
        76
    }

    private func updateHostedContentBottomInset(isMiniPlayerVisible: Bool) {
        let inset = isMiniPlayerVisible ? max(miniPlayerHeight - 12, 0) : 0

        viewControllers?.forEach { controller in
            controller.additionalSafeAreaInsets.bottom = inset
        }
    }
}

extension StandardTabBarController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        BulletproofAudioImporter.shared.pendingURL = nil
        chrome.isPresentingModal = false
    }
}

private struct SharedShellEnvironmentModifier: ViewModifier {
    let shell: ShellStore
    let chrome: ShellChromeModel
    let tracker: InteractionLatencyTracker

    func body(content: Content) -> some View {
        content
            .environment(shell)
            .environment(chrome)
            .environment(tracker)
    }
}
