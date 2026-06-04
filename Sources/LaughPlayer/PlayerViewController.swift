import AppKit
import AVKit
import AVFoundation
import CoreMedia

protocol PlayerViewControllerDelegate: AnyObject {
    func playerViewController(_ controller: PlayerViewController, didRequestWindowAspectRatio ratio: CGFloat?)
    func playerViewControllerDidRequestOpenVideo(_ controller: PlayerViewController)
    func playerViewControllerDidRequestOpenSettings(_ controller: PlayerViewController)
    func playerViewController(_ controller: PlayerViewController, setImmersiveChromeVisible visible: Bool, animated: Bool)
}

final class PlayerViewController: NSViewController, MediaLibraryDelegate {
    private static let optimisticFallbackCodecs: Set<String> = ["1veh", "hev1"]
    /// Codecs macOS plays natively — do not run black-frame probes or ffmpeg on these.
    private static let nativeVideoCodecs: Set<String> = [
        "avc1", "h264", "x264", "1cva", "mp4v", "hvc1", "1cvh", "hev1", "1dvh"
    ]

    weak var delegate: PlayerViewControllerDelegate?

    private let player = AVPlayer()
    private let mpvController = MpvPlaybackController()
    private var mpvBackendActive = false
    private var mpvPlaybackStarted = false
    private var activeSession: ActivePlaybackSession?
    private var mpvTimelineTimer: Timer?
    private let playerSurfaceView = PlayerSurfaceView()
    private let queueDropZone = QueueDropZoneView()
    private let dragHostView = DragHostView()
    private let openButton = NSButton(title: "Open Media", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "Drop video or image to open. Drop video in bottom-right to queue.")
    private let imageSurfaceView = ImageSurfaceView()
    private let controlsContainer = RoundedPlaybackBarView()
    private let imageControlsContainer = RoundedPlaybackBarView()
    private let imageControlsStack = NSStackView()
    private let imageZoomOutButton = NSButton(title: "Zoom −", target: nil, action: nil)
    private let imageZoomInButton = NSButton(title: "Zoom +", target: nil, action: nil)
    private let imageFitButton = NSButton(title: "Fit", target: nil, action: nil)
    private let imageSettingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let controlsStack = NSStackView()
    private let transportClusterStack = NSStackView()
    private let playbackCenterClusterStack = NSStackView()
    private let playbackTopRowView = NSView()
    private let topControlsStack = NSStackView()
    private let bottomControlsStack = NSStackView()
    private let bottomLeftControlsStack = NSStackView()
    private let bottomRightControlsStack = NSStackView()
    private var playbackBarWidthConstraint: NSLayoutConstraint?
    private var playbackBarBottomConstraint: NSLayoutConstraint?
    private var imageBarWidthConstraint: NSLayoutConstraint?
    private var imageBarBottomConstraint: NSLayoutConstraint?
    private var miniPreviewWidthConstraint: NSLayoutConstraint?
    private var miniPreviewHeightConstraint: NSLayoutConstraint?
    private let transportSpeedLeftCluster = NSStackView()
    private let transportSpeedLeftSpacer = NSView()
    private let playbackSpeedSlowLabel = NSTextField(labelWithString: "")
    private let queuePreviousButton = NSButton(title: "", target: nil, action: nil)
    private let speedStepDownButton = NSButton(title: "", target: nil, action: nil)
    private let playPauseButton = NSButton(title: "Play", target: nil, action: nil)
    private let transportSpeedRightCluster = NSStackView()
    private let speedStepUpButton = NSButton(title: "", target: nil, action: nil)
    private let queueNextButton = NSButton(title: "", target: nil, action: nil)
    private let playbackSpeedFastLabel = NSTextField(labelWithString: "")
    private let transportSpeedRightSpacer = NSView()
    private let queueButton = NSButton(title: "Queue", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let playbackAccessoryCluster = NSStackView()
    private let imageAccessoryCluster = NSStackView()
    private let libraryButton = NSButton(title: "Library", target: nil, action: nil)
    private let mediaLibraryController = MediaLibraryController()
    private lazy var librarySidebar = LibrarySidebarView(controller: mediaLibraryController)
    private lazy var libraryBrowse = LibraryBrowseView(controller: mediaLibraryController)
    private let playbackMiniPreview = PlaybackMiniPreviewView()
    private let titleBarChromeStrip = NSVisualEffectView()
    private var titleBarChromeHeightConstraint: NSLayoutConstraint?
    private let rightSettingsSheet = NSVisualEffectView()
    private let videoSettingsTabsRow = NSStackView()
    private let imageSettingsTabsRow = NSStackView()
    private var videoSettingsTabButtons: [HoverTextButton] = []
    private var imageSettingsTabButtons: [HoverTextButton] = []
    private var videoSettingsTabHeaders: [SettingsTabHeaderItemView] = []
    private var imageSettingsTabHeaders: [SettingsTabHeaderItemView] = []
    private var selectedVideoSettingsTabIndex = 0
    private var selectedImageSettingsTabIndex = 0
    private let settingsContentContainer = NSView()
    private let settingsScrollView = NSScrollView()
    private let videoTabView = NSStackView()
    private let audioTabView = NSStackView()
    private let audioSettings = AudioSettingsControls()
    private var cachedAudioTracks: [AudioTrackInfo] = []
    private var suppressAudioTrackPopUpAction = false
    private var pendingAudioTrackBackendID: AudioTrackInfo.BackendID?
    private var pendingResumePlayingAfterLoad: Bool?
    private let subtitlesSettings = SubtitlesSettingsControls()
    private var cachedSubtitleTracks: [SubtitleTrackInfo] = []
    private var suppressSubtitlePopUpAction = false
    private var suppressSubtitleAppearanceCallback = false
    private var primarySubtitlesEnabled = false
    private var secondarySubtitlesEnabled = false
    private var lastExternalSubtitlePath: String?
    private var cachedDiscoveredCompanions: [DiscoveredCompanionSubtitle] = []
    private let subtitlesTabView = NSStackView()
    private let nativeSubtitleOverlay = NativeSubtitleOverlay()
    private let playbackSubtitleToggle = PlaybackSubtitleToggleButton()
    private let imageTabView = NSStackView()
    private let imageFitTabView = NSStackView()
    private var activeMediaKind: ActiveMediaKind = .empty
    private let seekSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeCluster = NSStackView()
    private let volumeMuteButton = NSButton(title: "", target: nil, action: nil)
    private let volumeSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let currentTimeLabel = NSTextField(labelWithString: "00:00")
    private let totalTimeLabel = NSTextField(labelWithString: "00:00")
    private let playbackSourcePopUp = NSPopUpButton()
    private let videoFitModeControl = NSSegmentedControl(labels: ["Fit", "Fill"], trackingMode: .selectOne, target: nil, action: nil)
    private let windowAspectControl = NSSegmentedControl(
        labels: WindowAspectPreset.selectablePresets.map(\.displayTitle),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let playbackSpeedSlider = NSSlider(value: 2, minValue: 0, maxValue: 6, target: nil, action: nil)
    private let playbackSpeedStepDownButton = NSButton(title: "", target: nil, action: nil)
    private let playbackSpeedStepUpButton = NSButton(title: "", target: nil, action: nil)
    private let playbackSpeedValueLabel = NSTextField(labelWithString: "1×")
    private let lockAspectCheckbox = NSButton(checkboxWithTitle: "Lock window to video aspect", target: nil, action: nil)
    private let loopPlaybackCheckbox = NSButton(checkboxWithTitle: "Loop playback", target: nil, action: nil)
    private var playToEndObserver: NSObjectProtocol?
    private var preferredPlaybackRate: Float = 1.0
    private var suppressPlaybackSourceAction = false
    private var queue: [PlaybackQueueItem] = []
    private var playbackHistory: [URL] = []
    private var suppressPlaybackHistoryAppend = false
    private var queuePopover: NSPopover?
    private var queueListViewController: PlaybackQueueListViewController?
    private var failedToPlayObserver: NSObjectProtocol?
    private var playbackStalledObserver: NSObjectProtocol?
    private var newAccessLogEntryObserver: NSObjectProtocol?
    private var newErrorLogEntryObserver: NSObjectProtocol?
    private weak var observedItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private let renderMonitor = PlaybackRenderMonitor()
    private let compatibilityBanner = CompatibilityBannerView()
    private var currentMediaURL: URL?
    /// User-selected file (used for cache/fallback lookup while a remuxed temp file plays).
    private var playbackSourceURL: URL?
    /// File path actually loaded in AVPlayer (may be a LaughPlayerFallback temp copy).
    private var activePlaybackFileURL: URL?
    private var lastPlaybackStartedItemID: ObjectIdentifier?
    private var lastVideoCodecFourCC: String?
    private var lastVideoSize: CGSize?
    private var lastImageSize: CGSize?
    private var lastAudioSummary: String = "Unknown"
    private var lastVideoTrackSummary: String = "Unknown"
    private var isSeekingFromUI = false
    private var seekGeneration = 0
    private var currentControlTier: ControlDensityTier = .regular
    private var outsideClickMonitor: Any?
    private var suppressSettingsDismissForColorPicker = false
    private var immersivePointerMonitor: Any?
    private var keyboardShortcutMonitor: Any?
    private var videoDoubleClickMonitor: Any?
    private var immersiveChromeHideWorkItem: DispatchWorkItem?
    private var immersiveChromeVisible = false
    private var immersiveCursorHiddenUntilMove = false
    private var immersiveCursorWindowObservers: [NSObjectProtocol] = []
    private var dragSessionActive = false
    /// Brief pause before edge-hover opens a side panel (avoids accidental opens).
    private static let edgePanelOpenDelay: TimeInterval = 0.4
    private var pendingLeftEdgePanelOpen: DispatchWorkItem?
    private var pendingRightEdgePanelOpen: DispatchWorkItem?
    private var settingsContentBottomConstraint: NSLayoutConstraint?
    private var securityScopedMediaURL: URL?
    private var videoLoadGeneration = 0
    private var activePlaybackGeneration = 0
    private var observedItemLoadGeneration = 0
    private var observedItemPlayableURL: URL?
    private var fallbackConvertedOutputPaths: Set<String> = []
    private var fallbackInProgress = false
    private var pendingStartTimeAfterLoad: CMTime?
    private var fallbackStartedAt: CFAbsoluteTime?
    private var fallbackResumeTargetSec: Double?
    private var fallbackLastMethod: String?
    private var activePreviewFullTargetURL: URL?
    private var activePreviewSourceDurationSec: Double?
    private var activePlayableDurationSec: Double = 0
    private var progressiveExtendInProgress = false
    private var lastProgressiveExtendWallTime: CFAbsoluteTime = 0
    private var progressiveExtentMonitorToken: Int = 0
    private var seekBarPrepareTimer: Timer?
    private var playbackPrepareActive = false
    private var fallbackSessionToken: Int = 0
    private var lastLoadRequestURL: String?
    private var lastLoadRequestAt: CFAbsoluteTime = 0
    private var lastLikelyToKeepUp: Bool?
    private var lastBufferEmpty: Bool?
    private var lastBufferFull: Bool?
    private var desiredPlaybackVolume: Float = 1.0
    private var isUserVolumeMuted = false
    private var volumeLevelBeforeUserMute: Float = 1.0
    private var volumeRampToken: Int = 0
    private var isMutedForSwitch: Bool = false
    private var pendingVideoLoadWorkItem: DispatchWorkItem?
    private var committedPlayerItemID: ObjectIdentifier?
    private let baseSettingsPanelWidth: CGFloat = 320
    private let baseLibrarySidebarWidth: CGFloat = LibrarySidebarView.width
    private var librarySidebarWidthConstraint: NSLayoutConstraint?
    private var settingsPanelWidthConstraint: NSLayoutConstraint?
    private var volumeSliderWidthConstraint: NSLayoutConstraint?
    private var playbackCenterToVolumeConstraint: NSLayoutConstraint?
    private var playbackCenterToEdgeConstraint: NSLayoutConstraint?
    private var playbackTopRowLayoutConfigured = false
    private var audioOutputEnabled = true
    private var playerInterfaceInstalled = false
    private var libraryChromeInstalled = false
    private let playbackControlClusterSpacing: CGFloat = 20
    private var lastAppliedUIScale: CGFloat = 1
    private enum PlaybackLibraryOverlay {
        case closed
        case sidebarOnly
        case sidebarAndBrowse
    }

    private var playbackLibraryOverlay: PlaybackLibraryOverlay = .closed
    private let settingsPanelInnerInset: CGFloat = 12
    private let settingsTabsTopInset: CGFloat = 40
    private let settingsContentBottomClearance: CGFloat = 108
    private let settingsStackSpacing: CGFloat = 4
    private let settingsSectionExtraGap: CGFloat = 14

    private enum ControlDensityTier {
        case compact
        case regular
        case spacious
    }

    override func loadView() {
        view = dragHostView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installImmersiveCursorWindowObserversIfNeeded()
        prepareInterfaceForDisplay()
    }

    /// Ensures the library empty state is laid out once the window has a real size.
    func prepareInterfaceForDisplay() {
        guard view.window != nil else { return }
        installImmersiveCursorWindowObserversIfNeeded()
        installPlayerInterfaceIfNeeded()
        installLibraryChromeIfNeeded()
        if activeMediaKind == .empty {
            showFullMediaLibrary()
            setImmersiveChromeVisible(true, animated: false)
        }
        view.layoutSubtreeIfNeeded()
        LaunchLog.emit("prepareInterfaceForDisplay: bounds=\(view.bounds)")
    }

    override func viewDidLoad() {
        LaunchLog.emit("PlayerViewController.viewDidLoad: begin")
        super.viewDidLoad()
        activeMediaKind = .empty
        LaunchLog.emit("PlayerViewController.viewDidLoad: end")
    }

    func installPlayerInterfaceIfNeeded() {
        guard !playerInterfaceInstalled else { return }
        playerInterfaceInstalled = true
        LaunchLog.emit("installPlayerInterfaceIfNeeded: begin")

        playerSurfaceView.player = player
        player.automaticallyWaitsToMinimizeStalling = true
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.actionAtItemEnd = .pause
        if #available(macOS 12.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        playerSurfaceView.videoGravity = .resizeAspect
        playerSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        nativeSubtitleOverlay.install(in: playerSurfaceView)
        playerSurfaceView.onMpvLayoutChanged = { [weak self] in
            guard let self, self.mpvBackendActive else { return }
            let wid = self.playerSurfaceView.mpvEmbeddingWindowID
            guard wid > 0 else { return }
            self.mpvController.setEmbeddingWindowID(wid)
        }
        view.addSubview(playerSurfaceView)

        imageSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        imageSurfaceView.isHidden = true
        view.addSubview(imageSurfaceView)

        queueDropZone.translatesAutoresizingMaskIntoConstraints = false
        queueDropZone.isHidden = true
        view.addSubview(queueDropZone)
        
        openButton.bezelStyle = .rounded
        openButton.font = .systemFont(ofSize: 14, weight: .semibold)
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.target = self
        openButton.action = #selector(openVideoPressed)
        view.addSubview(openButton)

        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        compatibilityBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(compatibilityBanner)

        MusicStylePlaybackBar.applyChrome(to: controlsContainer)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.isHidden = true
        view.addSubview(controlsContainer)

        MusicStylePlaybackBar.applyChrome(to: imageControlsContainer)
        imageControlsContainer.isHidden = true
        imageControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageControlsContainer)

        imageControlsStack.orientation = .horizontal
        imageControlsStack.alignment = .centerY
        imageControlsStack.spacing = 8
        imageControlsStack.translatesAutoresizingMaskIntoConstraints = false
        imageControlsContainer.addSubview(imageControlsStack)
        configureImageControls()

        mediaLibraryController.delegate = self

        styleTitleBarChromeStrip()
        titleBarChromeStrip.isHidden = true
        titleBarChromeStrip.alphaValue = 0
        titleBarChromeStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleBarChromeStrip)
        titleBarChromeHeightConstraint = titleBarChromeStrip.heightAnchor.constraint(equalToConstant: 28)
        NSLayoutConstraint.activate([
            titleBarChromeStrip.topAnchor.constraint(equalTo: view.topAnchor),
            titleBarChromeStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBarChromeStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBarChromeHeightConstraint!
        ])

        styleRightSettingsPanel()
        rightSettingsSheet.isHidden = true
        rightSettingsSheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightSettingsSheet)

        videoSettingsTabsRow.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(videoSettingsTabsRow)

        imageSettingsTabsRow.isHidden = true
        imageSettingsTabsRow.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(imageSettingsTabsRow)
        configureSettingsTabsAppearance()

        settingsScrollView.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.hasVerticalScroller = true
        settingsScrollView.autohidesScrollers = true
        settingsScrollView.drawsBackground = false
        settingsScrollView.borderType = .noBorder
        rightSettingsSheet.addSubview(settingsScrollView)

        settingsContentContainer.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.documentView = settingsContentContainer
        ensureSettingsTabRowsAboveContent()

        configureSettingsTabViews()
        LaunchLog.emit("installPlayerInterfaceIfNeeded: settings tabs")

        controlsStack.orientation = .vertical
        controlsStack.alignment = .centerX
        controlsStack.distribution = .fill
        controlsStack.spacing = 10
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(controlsStack)

        transportClusterStack.orientation = .horizontal
        transportClusterStack.alignment = .centerY
        transportClusterStack.distribution = .fill
        transportClusterStack.spacing = 8

        transportSpeedLeftCluster.orientation = .horizontal
        transportSpeedLeftCluster.alignment = .centerY
        transportSpeedLeftCluster.spacing = 1
        configureTransportSpeedClusterSpacer(transportSpeedLeftSpacer)
        transportSpeedLeftCluster.addArrangedSubview(transportSpeedLeftSpacer)
        transportSpeedLeftCluster.addArrangedSubview(playbackSpeedSlowLabel)
        transportSpeedLeftCluster.addArrangedSubview(speedStepDownButton)

        transportSpeedRightCluster.orientation = .horizontal
        transportSpeedRightCluster.alignment = .centerY
        transportSpeedRightCluster.spacing = 1
        transportSpeedRightCluster.addArrangedSubview(speedStepUpButton)
        transportSpeedRightCluster.addArrangedSubview(playbackSpeedFastLabel)
        configureTransportSpeedClusterSpacer(transportSpeedRightSpacer)
        transportSpeedRightCluster.addArrangedSubview(transportSpeedRightSpacer)
        transportSpeedLeftCluster.translatesAutoresizingMaskIntoConstraints = false
        transportSpeedRightCluster.translatesAutoresizingMaskIntoConstraints = false

        topControlsStack.orientation = .horizontal
        topControlsStack.alignment = .centerY
        topControlsStack.distribution = .fill
        topControlsStack.spacing = 12

        bottomControlsStack.orientation = .horizontal
        bottomControlsStack.alignment = .centerY
        bottomControlsStack.distribution = .fill
        bottomControlsStack.spacing = 10

        playbackCenterClusterStack.orientation = .horizontal
        playbackCenterClusterStack.alignment = .centerY
        playbackCenterClusterStack.distribution = .fill
        playbackCenterClusterStack.spacing = playbackControlClusterSpacing
        playbackCenterClusterStack.setContentHuggingPriority(.required, for: .horizontal)
        playbackCenterClusterStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        transportClusterStack.setContentHuggingPriority(.required, for: .horizontal)
        transportClusterStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        transportSpeedLeftCluster.setContentCompressionResistancePriority(.required, for: .horizontal)
        transportSpeedRightCluster.setContentCompressionResistancePriority(.required, for: .horizontal)

        bottomLeftControlsStack.orientation = .horizontal
        bottomLeftControlsStack.alignment = .centerY
        bottomLeftControlsStack.distribution = .fill
        bottomLeftControlsStack.spacing = 0

        bottomRightControlsStack.orientation = .horizontal
        bottomRightControlsStack.alignment = .centerY
        bottomRightControlsStack.distribution = .fill
        bottomRightControlsStack.spacing = 0
        LaunchLog.emit("installPlayerInterfaceIfNeeded: transport clusters")

        configureControls()
        LaunchLog.emit("installPlayerInterfaceIfNeeded: controls")

        let initialLayoutWidth: CGFloat = 960
        let initialBarWidth = MusicStylePlaybackBar.preferredBarWidth(forContentWidthPoints: initialLayoutWidth)
        let initialBarBottomInset = MusicStylePlaybackBar.preferredBarBottomInset(forContentWidthPoints: initialLayoutWidth)
        playbackBarWidthConstraint = controlsContainer.widthAnchor.constraint(equalToConstant: initialBarWidth)
        playbackBarBottomConstraint = controlsContainer.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -initialBarBottomInset
        )
        imageBarWidthConstraint = imageControlsContainer.widthAnchor.constraint(equalToConstant: min(420, initialBarWidth))
        imageBarBottomConstraint = imageControlsContainer.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -initialBarBottomInset
        )
        settingsPanelWidthConstraint = rightSettingsSheet.widthAnchor.constraint(equalToConstant: baseSettingsPanelWidth)

        NSLayoutConstraint.activate([
            playerSurfaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerSurfaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerSurfaceView.topAnchor.constraint(equalTo: view.topAnchor),
            playerSurfaceView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            imageSurfaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageSurfaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageSurfaceView.topAnchor.constraint(equalTo: view.topAnchor),
            imageSurfaceView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            queueDropZone.widthAnchor.constraint(equalToConstant: 180),
            queueDropZone.heightAnchor.constraint(equalToConstant: 96),
            queueDropZone.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            queueDropZone.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hintLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 8),
            hintLabel.centerXAnchor.constraint(equalTo: openButton.centerXAnchor),

            compatibilityBanner.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            compatibilityBanner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            compatibilityBanner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            compatibilityBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            compatibilityBanner.widthAnchor.constraint(lessThanOrEqualToConstant: 520),

            controlsContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playbackBarBottomConstraint!,
            controlsContainer.heightAnchor.constraint(equalToConstant: 76),
            playbackBarWidthConstraint!,

            imageControlsContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageBarBottomConstraint!,
            imageControlsContainer.heightAnchor.constraint(equalToConstant: 52),
            imageBarWidthConstraint!,

            imageControlsStack.leadingAnchor.constraint(equalTo: imageControlsContainer.leadingAnchor, constant: 10),
            imageControlsStack.trailingAnchor.constraint(equalTo: imageControlsContainer.trailingAnchor, constant: -10),
            imageControlsStack.topAnchor.constraint(equalTo: imageControlsContainer.topAnchor, constant: 8),
            imageControlsStack.bottomAnchor.constraint(equalTo: imageControlsContainer.bottomAnchor, constant: -8),

            controlsStack.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 16),
            controlsStack.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -16),
            controlsStack.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 10),
            controlsStack.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -10),

            rightSettingsSheet.topAnchor.constraint(equalTo: view.topAnchor),
            rightSettingsSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightSettingsSheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            settingsPanelWidthConstraint!,

            videoSettingsTabsRow.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor, constant: settingsTabsTopInset),
            videoSettingsTabsRow.heightAnchor.constraint(equalToConstant: 34),
            videoSettingsTabsRow.centerXAnchor.constraint(equalTo: rightSettingsSheet.centerXAnchor),
            videoSettingsTabsRow.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset + 2),
            videoSettingsTabsRow.trailingAnchor.constraint(equalTo: rightSettingsSheet.trailingAnchor, constant: -(settingsPanelInnerInset + 2)),

            imageSettingsTabsRow.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor, constant: settingsTabsTopInset),
            imageSettingsTabsRow.heightAnchor.constraint(equalToConstant: 34),
            imageSettingsTabsRow.centerXAnchor.constraint(equalTo: rightSettingsSheet.centerXAnchor),
            imageSettingsTabsRow.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset + 2),
            imageSettingsTabsRow.trailingAnchor.constraint(equalTo: rightSettingsSheet.trailingAnchor, constant: -(settingsPanelInnerInset + 2)),

            settingsScrollView.topAnchor.constraint(equalTo: videoSettingsTabsRow.bottomAnchor, constant: settingsPanelInnerInset + 14),
            settingsScrollView.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset),
            settingsScrollView.trailingAnchor.constraint(equalTo: rightSettingsSheet.trailingAnchor, constant: -settingsPanelInnerInset),

            settingsContentContainer.leadingAnchor.constraint(equalTo: settingsScrollView.contentView.leadingAnchor),
            settingsContentContainer.trailingAnchor.constraint(equalTo: settingsScrollView.contentView.trailingAnchor),
            settingsContentContainer.topAnchor.constraint(equalTo: settingsScrollView.contentView.topAnchor),
            settingsContentContainer.bottomAnchor.constraint(equalTo: settingsScrollView.contentView.bottomAnchor),
            settingsContentContainer.widthAnchor.constraint(equalTo: settingsScrollView.widthAnchor)
        ])

        settingsContentBottomConstraint = settingsScrollView.bottomAnchor.constraint(
            equalTo: rightSettingsSheet.bottomAnchor,
            constant: -settingsPanelInnerInset
        )
        settingsContentBottomConstraint?.isActive = true
        LaunchLog.emit("installPlayerInterfaceIfNeeded: constraints")

        raisePlaybackChromeToFront()

        dragHostView.readURLs = { drag in
            guard let items = drag.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
                return []
            }
            return items.filter { $0.isFileURL }
        }
        dragHostView.onPerformDrop = { [weak self] urls, locationInView in
            guard let self else { return false }
            let inDropZone = self.queueDropZone.frame.contains(locationInView)
            let shouldQueue = inDropZone && self.canAcceptQueueDrop
            return self.handleDroppedURLs(urls, queueOnly: shouldQueue)
        }
        dragHostView.onDragSessionActive = { [weak self] active in
            guard let self else { return }
            self.dragSessionActive = active
            self.setQueueDropZoneVisibleForDrag(active)
            if active {
                self.cancelEdgePanelHoverTimers()
                self.hideSettingsSheet()
                self.refreshImmersiveChromePinnedState()
            } else {
                self.scheduleImmersiveChromeHide()
            }
        }
        dragHostView.onMouseMoved = { [weak self] point in
            self?.handleMouseMoved(point)
        }
        dragHostView.onMouseEnteredView = { [weak self] in
            self?.noteImmersiveChromePointerActivity()
        }
        dragHostView.onMouseExitedView = { [weak self] in
            self?.handlePointerLeftContentView()
        }

        failedToPlayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            let message = err?.localizedDescription ?? "Playback failed."
            self?.showCompatibilityFailure("Playback failed.\n\n\(message)")
        }

        playbackStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let stalledItem = notification.object as? AVPlayerItem else { return }
            guard stalledItem == self.player.currentItem else { return }
            print("[DEBUG-qos] playback stalled (possible audio/video pipeline starvation)")
            self.logPlaybackHealthSnapshot(reason: "stalled", item: stalledItem)
        }

        newAccessLogEntryObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let item = notification.object as? AVPlayerItem else { return }
            guard item == self.player.currentItem else { return }
            self.logPlaybackHealthSnapshot(reason: "access_log", item: item)
        }

        newErrorLogEntryObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let item = notification.object as? AVPlayerItem else { return }
            guard item == self.player.currentItem else { return }
            self.logErrorLogSnapshot(reason: "error_log", item: item)
        }

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds >= 0 {
                let rounded = String(format: "%.2f", seconds)
                print("[DEBUG-playback] t=\(rounded)s rate=\(self.player.rate)")
                self.ensureLaughVolumeIfPlaying()
                _ = self.extendProgressivePlaybackIfNeeded()
                self.updateTimelineUI()
            }
        }

        updateSettingsContentBottomInset()
        installKeyboardShortcutMonitor()
        installVideoDoubleClickFullscreenMonitor()

        LaunchLog.emit("installPlayerInterfaceIfNeeded: end")
    }

    private func installLibraryChromeIfNeeded() {
        guard !libraryChromeInstalled else { return }
        libraryChromeInstalled = true
        LaunchLog.emit("installLibraryChromeIfNeeded")

        librarySidebar.isHidden = true
        librarySidebar.translatesAutoresizingMaskIntoConstraints = false
        libraryBrowse.isHidden = true
        libraryBrowse.translatesAutoresizingMaskIntoConstraints = false
        libraryBrowse.onOpenMediaPanel = { [weak self] in
            guard let self else { return }
            self.delegate?.playerViewControllerDidRequestOpenVideo(self)
        }
        libraryBrowse.onPlayAll = { [weak self] in
            self?.playAllFromCurrentLibraryFolder()
        }
        libraryBrowse.onContextAction = { [weak self] action, entry in
            self?.handleLibraryBrowseContextAction(action, entry: entry)
        }
        playbackMiniPreview.isHidden = true
        playbackMiniPreview.translatesAutoresizingMaskIntoConstraints = false
        playbackMiniPreview.onExpand = { [weak self] in
            self?.collapsePlaybackLibraryOverlay()
        }
        playbackMiniPreview.onClose = { [weak self] in
            self?.closePlaybackFromMiniPreview()
        }

        view.addSubview(librarySidebar)
        view.addSubview(libraryBrowse)
        view.addSubview(playbackMiniPreview)

        mediaLibraryController.onChange = { [weak self] in
            guard let self, self.libraryChromeInstalled else { return }
            self.librarySidebar.refresh()
            self.libraryBrowse.refresh()
            self.syncPlaybackLibraryBrowseExpansion()
        }

        librarySidebarWidthConstraint = librarySidebar.widthAnchor.constraint(equalToConstant: baseLibrarySidebarWidth)
        NSLayoutConstraint.activate([
            librarySidebar.topAnchor.constraint(equalTo: view.topAnchor),
            librarySidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            librarySidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            librarySidebarWidthConstraint!,

            libraryBrowse.topAnchor.constraint(equalTo: view.topAnchor),
            libraryBrowse.leadingAnchor.constraint(equalTo: librarySidebar.trailingAnchor),
            libraryBrowse.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            libraryBrowse.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            playbackMiniPreview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playbackMiniPreview.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        let previewSize = PlaybackMiniPreviewMetrics.preferredSize(forContentWidth: max(view.bounds.width, 1))
        miniPreviewWidthConstraint = playbackMiniPreview.widthAnchor.constraint(equalToConstant: previewSize.width)
        miniPreviewHeightConstraint = playbackMiniPreview.heightAnchor.constraint(equalToConstant: previewSize.height)
        miniPreviewWidthConstraint?.isActive = true
        miniPreviewHeightConstraint?.isActive = true
        playbackMiniPreview.applyLayoutScale(forWidth: previewSize.width)

        raisePlaybackChromeToFront()
    }

    func loadVideo(url: URL, replaceCurrent: Bool = true, startAt: CMTime? = nil, forceDirectMpv: Bool = false) {
        pendingVideoLoadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performLoadVideo(
                url: url,
                replaceCurrent: replaceCurrent,
                startAt: startAt,
                forceDirectMpv: forceDirectMpv
            )
        }
        pendingVideoLoadWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    private func performLoadVideo(
        url: URL,
        replaceCurrent: Bool,
        startAt: CMTime?,
        forceReload: Bool = false,
        forceDirectMpv: Bool = false
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let samePath = lastLoadRequestURL == url.path
        if !forceReload, samePath, (now - lastLoadRequestAt) < 0.35 {
            print("[DEBUG-playback] skipped duplicate load request path=\(url.path)")
            return
        }
        if fallbackInProgress, currentMediaURL?.standardizedFileURL == url.standardizedFileURL {
            print("[DEBUG-fallback] ignored load; conversion already running for \(url.lastPathComponent)")
            return
        }
        if !forceReload, !isGeneratedFallbackURL(url), isActivelyPlayingSource(url) {
            if let cached = FFmpegVideoFallback.cachedPlayableURL(for: url),
               activePlaybackFileURL == cached {
                print("[DEBUG-playback] already playing cached copy of \(url.lastPathComponent)")
            } else {
                print("[DEBUG-playback] already playing \(url.lastPathComponent)")
            }
            ensureLaughVolumeIfPlaying()
            return
        }
        if fallbackInProgress {
            fallbackSessionToken += 1
            fallbackInProgress = false
            fallbackStartedAt = nil
            fallbackResumeTargetSec = nil
            fallbackLastMethod = nil
            activePreviewFullTargetURL = nil
            activePreviewSourceDurationSec = nil
            FFmpegVideoFallback.terminateRunningProcesses()
            updateSeekBarPreparingState()
            print("[DEBUG-fallback] invalidated due to switch to \(url.lastPathComponent)")
        }
        if mpvBackendActive {
            stopMpvBackend()
        }
        lastLoadRequestURL = url.path
        lastLoadRequestAt = now
        print("[DEBUG-playback] Loading video: \(url.path)")
        videoLoadGeneration += 1
        seekGeneration += 1
        let generation = videoLoadGeneration
        if let startAt {
            let sec = CMTimeGetSeconds(startAt)
            pendingStartTimeAfterLoad = sec.isFinite && sec >= 0 ? startAt : nil
        } else {
            pendingStartTimeAfterLoad = nil
        }

        hideCompatibilityFailure()
        renderMonitor.reset()
        audioOutputEnabled = true
        isUserVolumeMuted = false
        lastPlaybackStartedItemID = nil
        committedPlayerItemID = nil
        let previousMediaURL = currentMediaURL
        currentMediaURL = url
        if !isGeneratedFallbackURL(url) {
            playbackSourceURL = url
        }
        lastVideoCodecFourCC = nil
        lastVideoSize = nil
        lastImageSize = nil
        lastAudioSummary = "Loading..."
        lastVideoTrackSummary = "Loading..."
        renderMonitor.videoCodecFourCC = nil
        updateVideoInfoLabels()

        if replaceCurrent,
           !suppressPlaybackHistoryAppend,
           let previousMediaURL,
           !isGeneratedFallbackURL(previousMediaURL) {
            playbackHistory.append(previousMediaURL)
        }

        preparePlayerForVideoSwitch()

        if isVideoFileURL(url) {
            enterInstantPlaybackPrepareUI(for: url)
        }

        if forceDirectMpv, MpvPlaybackController.isAvailable() {
            print("[DEBUG-route] forced mpv path=\(url.path)")
            startDirectMpvPlayback(sourceURL: url, generation: generation)
            return
        }

        if likelyNeedsCompatibilityRemux(url) {
            print("[DEBUG-route] fast remux path=\(url.path)")
            startPlannedCompatibilityPlayback(sourceURL: url, generation: generation)
            return
        }

        Task {
            await MainActor.run {
                guard generation == self.videoLoadGeneration else { return }
                if forceDirectMpv, MpvPlaybackController.isAvailable() {
                    print("[DEBUG-route] forced mpv path=\(url.path)")
                    self.startDirectMpvPlayback(sourceURL: url, generation: generation)
                    return
                }
                Task {
                    let route = await PlaybackRoutePlanner.route(for: url)
                    await MainActor.run {
                        guard generation == self.videoLoadGeneration else { return }
                        switch route {
                        case .directMpv(let reason):
                            print("[DEBUG-route] planned mpv (\(reason)) path=\(url.path)")
                            self.startDirectMpvPlayback(sourceURL: url, generation: generation)
                        case .compatibilityRemux(let reason):
                            print("[DEBUG-route] planned remux (\(reason)) path=\(url.path)")
                            self.startPlannedCompatibilityPlayback(sourceURL: url, generation: generation)
                        case .nativeAVFoundation:
                            print("[DEBUG-route] planned native path=\(url.path)")
                            self.startNativePlayback(url: url, generation: generation)
                        }
                    }
                }
            }
        }
    }

    private func isVideoFileURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return true }
        let videoExtensions: Set<String> = [
            "mkv", "mp4", "m4v", "mov", "webm", "avi", "flv", "wmv", "ogv",
            "rm", "rmvb", "mpg", "mpeg", "ts", "m2ts", "3gp"
        ]
        return videoExtensions.contains(ext)
    }

    private func likelyNeedsCompatibilityRemux(_ url: URL) -> Bool {
        guard !isGeneratedFallbackURL(url) else { return false }
        guard FFmpegVideoFallback.isAvailable() else { return false }
        let ext = url.pathExtension.lowercased()
        let remuxContainers: Set<String> = [
            "mkv", "webm", "avi", "flv", "wmv", "ogv", "rm", "rmvb"
        ]
        return remuxContainers.contains(ext)
    }

    /// Show playback chrome and animated seek bar immediately while remux/decode prepares.
    private func enterInstantPlaybackPrepareUI(for url: URL) {
        playbackPrepareActive = true
        hideCompatibilityFailure()
        showVideoChrome()
        currentTimeLabel.stringValue = "···"
        totalTimeLabel.stringValue = "--:--"
        seekSlider.maxValue = 1
        seekSlider.doubleValue = 0
        updatePlayPauseButtonIcon()
        updateSeekBarPreparingState()
        if !isGeneratedFallbackURL(url) {
            RecentlyViewedStore.shared.record(url: url, kind: .video)
        }

        Task.detached(priority: .utility) { [weak self] in
            let sourceDuration = FFmpegVideoFallback.probeSourceDurationSec(for: url)
            await MainActor.run {
                guard url.standardizedFileURL == self?.currentMediaURL?.standardizedFileURL else { return }
                self?.activePreviewSourceDurationSec = sourceDuration
                if let sourceDuration, sourceDuration > 0 {
                    self?.seekSlider.maxValue = sourceDuration
                    self?.totalTimeLabel.stringValue = self?.formatTime(sourceDuration) ?? "--:--"
                }
                self?.updateSeekBarPreparingState()
            }
        }
    }

    private func leavePlaybackPrepareUI() {
        guard playbackPrepareActive else { return }
        playbackPrepareActive = false
        updateSeekBarPreparingState()
        syncPlaybackBarVisibilityForCurrentState()
        if usesImmersiveChrome, !immersiveChromePinnedVisible {
            resetImmersiveChromeAfterMediaChange()
        }
    }

    private func startPlannedCompatibilityPlayback(sourceURL: URL, generation: Int) {
        FFmpegVideoFallback.prefetchFullRemux(for: sourceURL)
        attemptFFmpegFallbackIfNeeded(plannedRoute: true, generation: generation)
    }

    private func startDirectMpvPlayback(sourceURL: URL, generation: Int) {
        FFmpegVideoFallback.terminateRunningProcesses()
        beginSecurityScopedAccess(for: sourceURL)
        detachCurrentPlayerItemObserver()
        committedPlayerItemID = nil
        lastPlaybackStartedItemID = nil
        activePlaybackFileURL = sourceURL
        mpvBackendActive = true
        mpvPlaybackStarted = false
        activeSession = nil
        nativeSubtitleOverlay.setSuppressedForAlternateBackend(true)

        activeMediaKind = .video
        showVideoChrome()
        RecentlyViewedStore.shared.record(url: sourceURL, kind: .video)
        disconnectPlayerFromVideoSurfaces()
        playerSurfaceView.setMpvEmbeddingActive(true)
        view.layoutSubtreeIfNeeded()

        let wid = playerSurfaceView.mpvEmbeddingWindowID
        guard wid > 0 else {
            print("[DEBUG-mpv] embedding wid unavailable; falling back to remux")
            mpvBackendActive = false
            playerSurfaceView.setMpvEmbeddingActive(false)
            startPlannedCompatibilityPlayback(sourceURL: sourceURL, generation: generation)
            return
        }

        wireMpvCallbacks(generation: generation, sourceURL: sourceURL)

        mpvController.load(url: sourceURL, wid: wid) { [weak self] result in
            guard let self, generation == self.videoLoadGeneration else { return }
            switch result {
            case .success:
                self.leavePlaybackPrepareUI()
                self.finishMpvPlaybackStart(sourceURL: sourceURL, generation: generation)
            case .failed(let message):
                print("[DEBUG-mpv] load failed: \(message); falling back to remux")
                self.stopMpvBackend()
                self.startPlannedCompatibilityPlayback(sourceURL: sourceURL, generation: generation)
            }
        }
    }

    private func wireMpvCallbacks(generation: Int, sourceURL: URL) {
        mpvController.onTimeUpdate = { [weak self] _, _ in
            guard let self, generation == self.videoLoadGeneration, self.mpvBackendActive else { return }
            self.updateTimelineUI()
        }
        mpvController.onPauseChanged = { [weak self] _ in
            guard let self, generation == self.videoLoadGeneration else { return }
            self.updatePlayPauseButtonIcon()
        }
        mpvController.onPlaybackEnded = { [weak self] in
            guard let self, generation == self.videoLoadGeneration, self.mpvBackendActive else { return }
            self.handleMpvPlaybackEnded()
        }
        mpvController.onReady = nil
    }

    private func finishMpvPlaybackStart(sourceURL: URL, generation: Int) {
        guard generation == videoLoadGeneration, mpvBackendActive else { return }
        activeSession = MpvPlaybackSession(controller: mpvController)
        mpvPlaybackStarted = true
        activePlaybackFileURL = sourceURL
        isMutedForSwitch = false
        if audioOutputEnabled {
            applyEffectivePlaybackVolume()
            updateVolumeMuteButtonIcon()
        }
        activeSession?.setRate(preferredPlaybackRate)
        updatePlayPauseButtonIcon()

        let pending = pendingStartTimeAfterLoad
        pendingStartTimeAfterLoad = nil
        let pendingSec = pending.map { CMTimeGetSeconds($0) } ?? 0
        let targetSec = (pendingSec.isFinite && pendingSec >= 0) ? pendingSec : 0

        let shouldPlay = pendingResumePlayingAfterLoad ?? true
        pendingResumePlayingAfterLoad = nil

        let start = { [weak self] in
            guard let self, generation == self.videoLoadGeneration, self.mpvBackendActive else { return }
            let resumePlayback = {
                if shouldPlay {
                    self.activeSession?.play()
                } else {
                    self.activeSession?.pause()
                }
                self.updatePlayPauseButtonIcon()
                self.updateTimelineUI()
            }
            if targetSec > 0.05 {
                self.activeSession?.seek(to: targetSec, exact: true) { _ in
                    resumePlayback()
                }
            } else {
                resumePlayback()
            }
            self.startMpvTimelinePolling()
            self.refreshMpvDebugMetadata()
            self.applyPlaybackEQToActiveMpv()
            self.applySubtitleAppearanceToActiveMpv()
            Task {
                let companions = CompanionSubtitleDiscovery.discover(for: sourceURL)
                let controller = self.mpvController
                await Task.detached {
                    controller.prepareSubtitleTracks(companionURLs: companions.map(\.url))
                }.value
                await self.refreshAudioTrackPicker()
                await self.refreshSubtitleSettings()
            }
            print("[DEBUG-mpv] playback started path=\(sourceURL.path)")
        }
        start()
    }

    private func refreshMpvDebugMetadata() {
        lastVideoTrackSummary = "mpv"
        lastAudioSummary = "mpv"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, self.mpvBackendActive else { return }
            let codec = self.mpvController.videoCodecTag()
            DispatchQueue.main.async {
                guard self.mpvBackendActive else { return }
                if let codec {
                    self.lastVideoCodecFourCC = codec
                    self.renderMonitor.videoCodecFourCC = codec
                }
                self.updateVideoInfoLabels()
            }
        }
    }

    private func handleMpvPlaybackEnded() {
        if !queue.isEmpty {
            playNextInQueue()
            return
        }
        guard SettingsStore.shared.loopPlaybackEnabled else { return }
        activeSession?.seek(to: 0, exact: true) { [weak self] _ in
            self?.activeSession?.play()
            self?.updatePlayPauseButtonIcon()
        }
    }

    private func stopMpvBackend() {
        stopMpvTimelinePolling()
        mpvController.onTimeUpdate = nil
        mpvController.onPauseChanged = nil
        mpvController.onPlaybackEnded = nil
        mpvController.onReady = nil
        mpvController.terminate()
        mpvBackendActive = false
        mpvPlaybackStarted = false
        if activeSession is MpvPlaybackSession {
            activeSession = nil
        }
        nativeSubtitleOverlay.setSuppressedForAlternateBackend(false)
        playerSurfaceView.setMpvEmbeddingActive(false)
    }

    private func startMpvTimelinePolling() {
        stopMpvTimelinePolling()
        mpvTimelineTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.updateTimelineUI()
        }
    }

    private func stopMpvTimelinePolling() {
        mpvTimelineTimer?.invalidate()
        mpvTimelineTimer = nil
    }

    private func startNativePlayback(url: URL, generation: Int) {
        stopMpvBackend()
        Task {
            let result = await VideoAssetLoader.resolvePlayableAsset(for: url)
            await MainActor.run {
                guard generation == self.videoLoadGeneration else { return }
                switch result {
                case .success(let asset):
                    self.attachResolvedVideo(asset: asset, url: url, generation: generation)
                case .failure(let failure):
                    print("[DEBUG-playback] native open failed: \(failure.debugDetails)")
                    self.handleNativePlaybackUnavailable(failure.userMessage)
                }
            }
        }
    }

    private func resolveAndAttach(playableURL: URL, sourceURL: URL, generation: Int) {
        Task {
            let result = await VideoAssetLoader.resolvePlayableAsset(for: playableURL)
            await MainActor.run {
                guard generation == self.videoLoadGeneration else { return }
                switch result {
                case .success(let asset):
                    self.attachResolvedVideo(
                        asset: asset,
                        url: playableURL,
                        generation: generation,
                        recentsURL: sourceURL
                    )
                    self.currentMediaURL = sourceURL
                    self.playbackSourceURL = sourceURL
                case .failure(let failure):
                    print("[DEBUG-playback] cached open failed: \(failure.debugDetails)")
                    self.attemptFFmpegFallbackIfNeeded()
                }
            }
        }
    }

    private func attachResolvedVideo(
        asset: AVURLAsset,
        url: URL,
        generation: Int,
        recentsURL: URL? = nil
    ) {
        stopMpvBackend()
        beginSecurityScopedAccess(for: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        item.audioTimePitchAlgorithm = .spectral
        activePlaybackGeneration = generation
        observedItemLoadGeneration = generation
        if let previousItem = observedItem, previousItem !== item {
            previousItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        }
        observedItem = item
        observedItemPlayableURL = url
        item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new, .initial], context: nil)

        activeMediaKind = .video
        showVideoChrome()
        let historyURL = recentsURL ?? (isGeneratedFallbackURL(url) ? nil : url)
        if let historyURL {
            RecentlyViewedStore.shared.record(url: historyURL, kind: .video)
        }
        updateAspectRatio(asset: asset)
        updatePlayPauseButtonIcon()
        updateTimelineUI()

        // Item must be the player's current item before status can leave `.unknown`.
        connectPlayerToVideoSurfaces()
        let attachItem = { [weak self] in
            guard let self, generation == self.videoLoadGeneration else { return }
            self.player.replaceCurrentItem(with: item)
            print("[DEBUG-playback] attached item status=\(item.status.rawValue) for \(url.lastPathComponent)")
            self.scheduleCommitWhenReady(item: item, playableURL: url, generation: generation)
        }
        // Brief delay after pause lets Core Audio release the old decoder before we swap items.
        if player.currentItem != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: attachItem)
        } else {
            attachItem()
        }
    }

    private func scheduleCommitWhenReady(item: AVPlayerItem, playableURL: URL, generation: Int) {
        if item.status == .readyToPlay {
            commitPlayerItem(item, playableURL: playableURL, generation: generation)
            return
        }
        if item.status == .failed {
            let details = PlaybackErrorFormatter.describe(item.error)
            print("[DEBUG-playback] item failed before commit: \(details)")
            return
        }

        Task { @MainActor in
            let deadline = CFAbsoluteTimeGetCurrent() + 20
            while CFAbsoluteTimeGetCurrent() < deadline {
                guard generation == self.observedItemLoadGeneration, item === self.observedItem else {
                    print("[DEBUG-playback] wait-for-ready cancelled (newer load)")
                    return
                }
                if item.status == .readyToPlay {
                    self.commitPlayerItem(item, playableURL: playableURL, generation: generation)
                    return
                }
                if item.status == .failed {
                    print("[DEBUG-playback] item failed while waiting to commit")
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            print("[DEBUG-playback] timed out waiting for readyToPlay on \(playableURL.lastPathComponent)")
        }
    }

    /// Swap to the new item only once it is ready — avoids half-open audio decoder churn.
    private func commitPlayerItem(_ item: AVPlayerItem, playableURL: URL, generation: Int) {
        let itemID = ObjectIdentifier(item)
        guard committedPlayerItemID != itemID else {
            print("[DEBUG-playback] commit skipped: already committed this item")
            return
        }
        guard generation == videoLoadGeneration else {
            print("[DEBUG-playback] stale commit ignored gen=\(generation) current=\(videoLoadGeneration)")
            return
        }
        guard item === observedItem else {
            print("[DEBUG-playback] commit skipped: item is no longer current")
            return
        }
        committedPlayerItemID = itemID
        activePlaybackFileURL = playableURL

        connectPlayerToVideoSurfaces()
        if player.currentItem !== item {
            player.replaceCurrentItem(with: item)
            print("[DEBUG-playback] committed player item (replaced on player)")
        } else {
            print("[DEBUG-playback] committed player item (already current, starting playback)")
        }
        beginPlaybackWhenReady(item: item, generation: generation)
    }

    private func isCurrentPlaybackItem(_ item: AVPlayerItem) -> Bool {
        item === observedItem && item === player.currentItem
    }

    /// True when the player's current item is the same logical source (native path or remux of it).
    private func currentPlayerItemMatchesSource(_ sourceURL: URL) -> Bool {
        guard let asset = player.currentItem?.asset as? AVURLAsset else { return false }
        let playing = asset.url.standardizedFileURL
        let source = sourceURL.standardizedFileURL
        if playing == source { return true }
        if isGeneratedFallbackURL(playing),
           playbackSourceURL?.standardizedFileURL == source {
            return true
        }
        return false
    }

    private func isActivelyPlayingSource(_ url: URL) -> Bool {
        guard activeMediaKind == .video else { return false }
        guard playbackSourceURL?.standardizedFileURL == url.standardizedFileURL else { return false }
        if mpvBackendActive {
            return mpvPlaybackStarted
        }
        guard committedPlayerItemID != nil, player.currentItem != nil else { return false }
        return lastPlaybackStartedItemID != nil || player.rate > 0
    }

    private func beginPlaybackWhenReady(item: AVPlayerItem, generation: Int) {
        let itemID = ObjectIdentifier(item)
        if lastPlaybackStartedItemID == itemID {
            return
        }
        guard generation == videoLoadGeneration else {
            print("[DEBUG-playback] ignored stale ready_to_play generation=\(generation) current=\(videoLoadGeneration)")
            return
        }
        guard isCurrentPlaybackItem(item) else {
            print("[DEBUG-playback] ignored ready_to_play for detached item")
            return
        }
        lastPlaybackStartedItemID = itemID

        print("[DEBUG-playback] Ready to play")
        showVideoChrome()

        let pending = pendingStartTimeAfterLoad ?? .zero
        let pendingSec = CMTimeGetSeconds(pending)
        let target = (pendingSec.isFinite && pendingSec >= 0) ? pending : .zero
        pendingStartTimeAfterLoad = nil

        let startPlayback = { [weak self] in
            guard let self else { return }
            guard generation == self.videoLoadGeneration, self.isCurrentPlaybackItem(item) else { return }
            print(String(
                format: "[DEBUG-playback] start_play keepUp=%@ empty=%@ full=%@",
                item.isPlaybackLikelyToKeepUp.description,
                item.isPlaybackBufferEmpty.description,
                item.isPlaybackBufferFull.description
            ))
            let finishStart = {
                self.restoreAudioAfterSwitchSmoothly()
                let shouldPlay = self.pendingResumePlayingAfterLoad ?? true
                self.pendingResumePlayingAfterLoad = nil
                if shouldPlay {
                    self.startPlaybackAtPreferredRate()
                } else {
                    self.player.pause()
                }
                if let startedAt = self.fallbackStartedAt {
                    let totalMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                    let currentSec = CMTimeGetSeconds(target)
                    let resumeDelta = self.fallbackResumeTargetSec.map { abs(currentSec - $0) } ?? 0
                    let method = self.fallbackLastMethod ?? "unknown"
                    print(String(format: "[DEBUG-fallback] handoff ready method=%@ total=%.2fms resumeTarget=%.3fs resumeDelta=%.3fs", method, totalMs, currentSec, resumeDelta))
                    self.fallbackStartedAt = nil
                    self.fallbackResumeTargetSec = nil
                    self.fallbackLastMethod = nil
                }
                self.logPlaybackHealthSnapshot(reason: "ready_to_play", item: item)
                self.updatePlayPauseButtonIcon()
                self.progressiveExtendInProgress = false
                self.leavePlaybackPrepareUI()
                self.updateTimelineUI()
                if self.shouldMonitorVideoRendering(codec: self.lastVideoCodecFourCC) {
                    self.renderMonitor.videoCodecFourCC = self.lastVideoCodecFourCC
                    self.renderMonitor.beginMonitoring(player: self.player, item: item) { [weak self] message in
                        self?.handleRenderFailure(message)
                    }
                }
                Task {
                    await self.refreshAudioTrackPicker()
                    await self.refreshSubtitleSettings()
                }
            }
            self.schedulePlaybackStartWhenBuffered(item: item, generation: generation, start: finishStart)
        }

        if CMTimeCompare(target, .zero) == 0 {
            startPlayback()
            return
        }

        performCooperativeSeek(to: target, precise: true) { finished in
            guard finished else {
                print("[DEBUG-playback] seek-before-play failed")
                return
            }
            startPlayback()
        }
    }

    /// Pause Laugh, seek with loose tolerance, then resume — avoids hammering the shared audio HAL on macOS.
    func performCooperativeSeek(
        to target: CMTime,
        precise: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        seekGeneration += 1
        let generation = seekGeneration
        isSeekingFromUI = true

        let seconds = CMTimeGetSeconds(target)
        guard seconds.isFinite, seconds >= 0 else {
            isSeekingFromUI = false
            completion?(false)
            return
        }

        if mpvBackendActive, let session = activeSession {
            let wasPlaying = session.isPlaying && !isMutedForSwitch
            if wasPlaying { session.pause() }
            session.seek(to: seconds, exact: precise) { [weak self] finished in
                guard let self, generation == self.seekGeneration else {
                    completion?(false)
                    return
                }
                self.isSeekingFromUI = false
                self.updateTimelineUI()
                if wasPlaying, finished, !self.isMutedForSwitch {
                    self.startPlaybackAtPreferredRate()
                }
                completion?(finished)
            }
            return
        }

        let wasPlaying = player.rate > 0 && !isMutedForSwitch
        if wasPlaying {
            player.pause()
        }

        let tolerance = precise
            ? .zero
            : CMTime(seconds: 0.5, preferredTimescale: 600)

        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, generation == self.seekGeneration else {
                    completion?(false)
                    return
                }
                self.isSeekingFromUI = false
                self.updateTimelineUI()
                if wasPlaying, finished, !self.isMutedForSwitch {
                    self.startPlaybackAtPreferredRate()
                }
                completion?(finished)
            }
        }
    }

    private func schedulePlaybackStartWhenBuffered(
        item: AVPlayerItem,
        generation: Int,
        start: @escaping () -> Void
    ) {
        if item.isPlaybackLikelyToKeepUp {
            start()
            return
        }
        Task { @MainActor in
            let deadline = CFAbsoluteTimeGetCurrent() + 2
            while CFAbsoluteTimeGetCurrent() < deadline {
                guard generation == self.videoLoadGeneration, self.isCurrentPlaybackItem(item) else { return }
                if item.isPlaybackLikelyToKeepUp {
                    start()
                    return
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            guard generation == self.videoLoadGeneration, self.isCurrentPlaybackItem(item) else { return }
            start()
        }
    }

    func loadImage(url: URL) {
        pendingVideoLoadWorkItem?.cancel()
        pendingVideoLoadWorkItem = nil
        guard let loaded = ImageDisplayLoader.loadDisplayImage(at: url) else {
            showUnsupportedFileMessage("Could not open this image file.")
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if lastLoadRequestURL == url.path, (now - lastLoadRequestAt) < 0.35 {
            print("[DEBUG-playback] skipped duplicate image load path=\(url.path)")
            return
        }
        lastLoadRequestURL = url.path
        lastLoadRequestAt = now
        print("[DEBUG-playback] Loading image: \(url.path)")
        if !suppressPlaybackHistoryAppend, let currentMediaURL {
            playbackHistory.append(currentMediaURL)
        }
        currentMediaURL = url
        playbackSourceURL = nil
        activePlaybackFileURL = nil
        stopMpvBackend()
        suspendPlayerOutputForStillOrEmpty()

        lastImageSize = loaded.pixelSize
        lastVideoSize = nil
        lastVideoCodecFourCC = nil
        lastAudioSummary = "Unknown"
        lastVideoTrackSummary = "Unknown"
        updateVideoInfoLabels()
        imageSurfaceView.setImage(loaded.image, naturalSize: loaded.pixelSize)
        activeMediaKind = .image
        RecentlyViewedStore.shared.record(url: url, kind: .image)
        showImageChrome()

        applyWindowAspectFromSettings()
    }

    func debugInfo(window: NSWindow?) -> String {
        let windowFrame = window?.frame ?? .zero
        let contentRect: NSRect
        if let contentView = window?.contentView {
            contentRect = contentView.bounds
        } else {
            contentRect = .zero
        }

        let windowSize = "\(Int(windowFrame.width))x\(Int(windowFrame.height))"
        let contentSize = "\(Int(contentRect.width))x\(Int(contentRect.height))"
        let videoSize = lastVideoSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "Unknown"
        let imageSize = lastImageSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "Unknown"
        let mediaSize: String
        let aspect: String
        switch activeMediaKind {
        case .video:
            mediaSize = videoSize
            aspect = lastVideoSize.map { String(format: "%.3f", $0.width / max($0.height, 1)) } ?? "Unknown"
        case .image:
            mediaSize = imageSize
            aspect = lastImageSize.map { String(format: "%.3f", $0.width / max($0.height, 1)) } ?? "Unknown"
        case .empty:
            mediaSize = "Unknown"
            aspect = "Unknown"
        }
        let codec = lastVideoCodecFourCC ?? "Unknown"
        let backendLabel = mpvBackendActive ? "mpv" : "avfoundation"
        let currentTime = activeSession?.currentTimeSec ?? CMTimeGetSeconds(player.currentTime())
        let timeString = currentTime.isFinite ? String(format: "%.2fs", currentTime) : "Unknown"
        let rateValue = mpvBackendActive ? (activeSession?.isPlaying == true ? preferredPlaybackRate : 0) : player.rate
        let rateString = String(format: "%.2f", rateValue)
        let mediaPath = currentMediaURL?.path ?? "None"
        let queueCount = "\(queue.count)"
        let mediaKindLabel: String
        switch activeMediaKind {
        case .empty: mediaKindLabel = "Empty"
        case .video: mediaKindLabel = "Video"
        case .image: mediaKindLabel = "Image"
        }
        let tierDescription: String
        switch currentControlTier {
        case .compact: tierDescription = "Compact"
        case .regular: tierDescription = "Regular"
        case .spacious: tierDescription = "Spacious"
        }

        return """
        File: \(mediaPath)
        Playback backend: \(backendLabel)
        Window size: \(windowSize)
        Content size: \(contentSize)
        Video size: \(videoSize)
        Image size: \(imageSize)
        Active media size: \(mediaSize)
        Media aspect ratio: \(aspect)
        Video codec: \(codec)
        Audio: \(lastAudioSummary)
        Playback time: \(timeString)
        Playback rate: \(rateString)
        Active media: \(mediaKindLabel)
        Controls tier: \(tierDescription)
        Queue items: \(queueCount)
        """
    }

    deinit {
        mpvController.terminate()
        FFmpegVideoFallback.terminateRunningProcesses()
        if let observer = failedToPlayObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = playbackStalledObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = newAccessLogEntryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = newErrorLogEntryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = playToEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        if let observedItem {
            observedItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        removeImmersivePointerMonitor()
        renderMonitor.reset()
        endSecurityScopedAccess()
        removeImmersiveCursorWindowObservers()
        restoreImmersivePlaybackCursor()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == #keyPath(AVPlayerItem.status), let item = object as? AVPlayerItem else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        switch item.status {
        case .readyToPlay:
            DispatchQueue.main.async {
                guard let playableURL = self.observedItemPlayableURL else {
                    print("[DEBUG-playback] readyToPlay but missing observedItemPlayableURL")
                    return
                }
                self.commitPlayerItem(item, playableURL: playableURL, generation: self.observedItemLoadGeneration)
            }
        case .failed:
            guard isCurrentPlaybackItem(item) else { return }
            let details = PlaybackErrorFormatter.describe(item.error)
            print("[DEBUG-playback] AVPlayerItem.failed: \(details)")
            DispatchQueue.main.async {
                let path = self.currentMediaURL?.path ?? "unknown"
                let ext = (path as NSString).pathExtension.lowercased()
                var message = "This video could not be played.\n\n\(item.error?.localizedDescription ?? "Playback failed.")"
                message += "\n\n(\(details))"
                if ext == "mkv" {
                    message += "\n\nThis MKV may use a codec macOS cannot decode natively (common with HEVC 10-bit)."
                }
                self.handleNativePlaybackUnavailable(message)
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func appendToQueue(_ urls: [URL]) {
        var items: [PlaybackQueueItem] = []
        var skipped = 0
        for url in urls {
            let kind = MediaKindDetector.kind(for: url)
            if kind == .video {
                items.append(PlaybackQueueItem(url: url, kind: kind))
            } else {
                skipped += 1
            }
        }
        if items.isEmpty {
            showUnsupportedFileMessage("Queue accepts videos only. Drop images in the main area.")
            return
        }
        if skipped > 0 {
            showCodecWarning("Skipped \(skipped) non-video file(s). Queue is for videos only.")
        }
        appendPlaybackQueueItems(items)
    }

    private func appendPlaybackQueueItems(_ items: [PlaybackQueueItem]) {
        guard !items.isEmpty else { return }
        queue.append(contentsOf: items)
        syncQueueChrome()
    }

    private func insertPlaybackQueueItemsAtFront(_ items: [PlaybackQueueItem]) {
        guard !items.isEmpty else { return }
        queue.insert(contentsOf: items, at: 0)
        syncQueueChrome()
    }

    private func playbackQueueItems(for files: [LibraryMediaFile]) -> [PlaybackQueueItem] {
        files.map { PlaybackQueueItem(url: $0.url, kind: $0.kind) }
    }

    private func removeURLsFromQueue(_ urls: Set<URL>) {
        let standardized = Set(urls.map(\.standardizedFileURL))
        queue.removeAll { standardized.contains($0.url.standardizedFileURL) }
        syncQueueChrome()
    }

    private func remapQueueURL(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL
        let new = newURL.standardizedFileURL
        queue = queue.map { item in
            guard item.url.standardizedFileURL == old else { return item }
            return PlaybackQueueItem(url: new, kind: item.kind)
        }
        syncQueueChrome()
    }

    func handleLibraryBrowseContextAction(_ action: LibraryBrowseContextAction, entry: LibraryBrowseEntry) {
        switch action {
        case .play:
            handleLibraryBrowsePlay(entry)
        case .playNext:
            handleLibraryBrowsePlayNext(entry)
        case .addToQueue:
            handleLibraryBrowseAddToQueue(entry)
        case .rename:
            handleLibraryBrowseRename(entry)
        case .showInFinder:
            handleLibraryBrowseShowInFinder(entry)
        case .remove:
            handleLibraryBrowseRemove(entry)
        }
    }

    private func handleLibraryBrowsePlay(_ entry: LibraryBrowseEntry) {
        switch entry.kind {
        case .media(let file):
            queue.removeAll()
            playbackHistory.removeAll()
            dismissSidePanelsForFocusedPlayback()
            openQueuedMedia(file, replaceVideo: true)
            syncQueueChrome()
        case .folder(let url):
            let files = mediaLibraryController.mediaFiles(in: url)
            guard !files.isEmpty else { return }
            playAllMedia(files)
        }
    }

    private func handleLibraryBrowsePlayNext(_ entry: LibraryBrowseEntry) {
        let files: [LibraryMediaFile]
        switch entry.kind {
        case .media(let file):
            files = [file]
        case .folder(let url):
            files = mediaLibraryController.mediaFiles(in: url)
        }
        guard !files.isEmpty else { return }
        let items = playbackQueueItems(for: files)
        if activeMediaKind == .empty {
            playAllMedia(files)
        } else {
            insertPlaybackQueueItemsAtFront(items)
        }
    }

    private func handleLibraryBrowseAddToQueue(_ entry: LibraryBrowseEntry) {
        let files: [LibraryMediaFile]
        switch entry.kind {
        case .media(let file):
            files = [file]
        case .folder(let url):
            files = mediaLibraryController.mediaFiles(in: url)
        }
        guard !files.isEmpty else { return }
        appendPlaybackQueueItems(playbackQueueItems(for: files))
    }

    private func handleLibraryBrowseShowInFinder(_ entry: LibraryBrowseEntry) {
        guard let url = LibraryBrowseFileActions.itemURL(for: entry) else { return }
        LibraryBrowseFileActions.showInFinder(url: url)
    }

    private func handleLibraryBrowseRename(_ entry: LibraryBrowseEntry) {
        guard let url = LibraryBrowseFileActions.itemURL(for: entry) else { return }
        guard let newName = LibraryBrowseFileActions.promptRename(currentName: entry.name) else { return }
        guard newName != entry.name else { return }

        do {
            let newURL = try LibraryBrowseFileActions.renameItem(at: url, to: newName)
            remapQueueURL(from: url, to: newURL)
            if currentMediaURL?.standardizedFileURL == url.standardizedFileURL {
                currentMediaURL = newURL
            }
            mediaLibraryController.reloadAfterFilesystemChange()
        } catch {
            LibraryBrowseFileActions.presentError(error, title: "Could Not Rename")
        }
    }

    private func handleLibraryBrowseRemove(_ entry: LibraryBrowseEntry) {
        guard let url = LibraryBrowseFileActions.itemURL(for: entry) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            mediaLibraryController.reloadAfterFilesystemChange()
            return
        }

        guard LibraryBrowseFileActions.confirmRemove(itemName: entry.name, isDirectory: isDirectory.boolValue) else {
            return
        }

        do {
            try LibraryBrowseFileActions.moveToTrash(url: url)
            if isDirectory.boolValue {
                let files = mediaLibraryController.mediaFiles(in: url)
                removeURLsFromQueue(Set(files.map(\.url)))
            } else {
                removeURLsFromQueue([url])
            }
            if currentMediaURL?.standardizedFileURL == url.standardizedFileURL {
                suspendPlayerOutputForStillOrEmpty()
                showEmptySurface()
            }
            mediaLibraryController.reloadAfterFilesystemChange()
        } catch {
            LibraryBrowseFileActions.presentError(error, title: "Could Not Remove")
        }
    }

    func playAllFromCurrentLibraryFolder() {
        let files = mediaLibraryController.mediaFilesInBrowseOrder()
        guard !files.isEmpty else { return }
        playAllMedia(files)
    }

    func advancePlaybackQueue() {
        playNextInQueue()
    }

    private func playAllMedia(_ files: [LibraryMediaFile]) {
        guard let first = files.first else { return }
        playbackHistory.removeAll()
        queue = files.dropFirst().map { PlaybackQueueItem(url: $0.url, kind: $0.kind) }
        dismissSidePanelsForFocusedPlayback()
        openQueuedMedia(first, replaceVideo: true)
        syncQueueChrome()
    }

    func playNextInQueue() {
        guard let next = queue.first else { return }
        queue.removeFirst()
        openQueuedMedia(LibraryMediaFile(url: next.url, kind: next.kind), replaceVideo: true)
        syncQueueChrome()
    }

    func playPreviousInQueue() {
        guard let previousURL = playbackHistory.popLast() else { return }

        if let current = currentMediaURL {
            let kind = MediaKindDetector.kind(for: current)
            if kind == .video || kind == .image {
                queue.insert(PlaybackQueueItem(url: current, kind: kind), at: 0)
            }
        }

        suppressPlaybackHistoryAppend = true
        defer { suppressPlaybackHistoryAppend = false }

        switch MediaKindDetector.kind(for: previousURL) {
        case .video:
            loadVideo(url: previousURL, replaceCurrent: true)
        case .image:
            loadImage(url: previousURL)
        case .unsupported:
            break
        }
        syncQueueChrome()
    }

    private func updateQueueTransportButtons() {
        let show = !queue.isEmpty || !playbackHistory.isEmpty
        queuePreviousButton.isHidden = !show
        queueNextButton.isHidden = !show
        queuePreviousButton.isEnabled = !playbackHistory.isEmpty
        queueNextButton.isEnabled = !queue.isEmpty
    }

    private func openQueuedMedia(_ file: LibraryMediaFile, replaceVideo: Bool) {
        switch file.kind {
        case .video:
            loadVideo(url: file.url, replaceCurrent: replaceVideo)
        case .image:
            loadImage(url: file.url)
        case .unsupported:
            break
        }
    }

    private func syncQueueChrome() {
        updateQueueTransportButtons()
        updateQueueButtonState()
        if dragSessionActive {
            setQueueDropZoneVisibleForDrag(true)
        }
        refreshQueuePopoverIfNeeded()
        if activeMediaKind == .video {
            detachImageAccessoryClusterFromImageControls()
            rebuildControlsForTier(currentControlTier)
            return
        }
        if activeMediaKind == .image {
            attachImageAccessoryClusterToImageControls()
        }
    }

    private func attachImageAccessoryClusterToImageControls() {
        moveQueueButtonToImageAccessoryCluster()
        guard !imageControlsStack.arrangedSubviews.contains(imageAccessoryCluster) else { return }
        imageControlsStack.addArrangedSubview(imageAccessoryCluster)
    }

    private func detachImageAccessoryClusterFromImageControls() {
        guard imageControlsStack.arrangedSubviews.contains(imageAccessoryCluster) else { return }
        imageControlsStack.removeArrangedSubview(imageAccessoryCluster)
        imageAccessoryCluster.removeFromSuperview()
        moveQueueButtonToPlaybackAccessoryCluster()
    }

    private func updateQueueButtonState() {
        let hasListContent = currentMediaURL != nil || !queue.isEmpty
        queueButton.isEnabled = hasListContent
        queueButton.alphaValue = hasListContent ? 1 : 0.45
    }

    private func buildQueueListRows() -> [PlaybackQueueListRow] {
        var rows: [PlaybackQueueListRow] = []
        if let url = currentMediaURL {
            let kind = MediaKindDetector.kind(for: url)
            let kindLabel = kind == .image ? "Image" : "Video"
            rows.append(
                PlaybackQueueListRow(
                    sectionTitle: "Now Playing · \(kindLabel)",
                    fileName: url.lastPathComponent,
                    queueItem: nil
                )
            )
        }
        if queue.isEmpty, rows.isEmpty {
            rows.append(
                PlaybackQueueListRow(
                    sectionTitle: "Queue",
                    fileName: "No items queued",
                    queueItem: nil
                )
            )
        } else {
            for (index, item) in queue.enumerated() {
                let kindLabel = item.kind == .image ? "Image" : "Video"
                rows.append(
                    PlaybackQueueListRow(
                        sectionTitle: "Up Next \(index + 1) · \(kindLabel)",
                        fileName: item.url.lastPathComponent,
                        queueItem: item
                    )
                )
            }
        }
        return rows
    }

    private func playQueuedItem(_ item: PlaybackQueueItem) {
        let file = LibraryMediaFile(url: item.url, kind: item.kind)
        guard let index = queue.firstIndex(where: { $0 == item }) else {
            openQueuedMedia(file, replaceVideo: true)
            return
        }
        queue.removeSubrange(0...index)
        openQueuedMedia(file, replaceVideo: true)
        syncQueueChrome()
    }

    func toggleQueuePopover() {
        if queuePopover?.isShown == true {
            closeQueuePopover()
            return
        }
        showQueuePopover()
    }

    private func showQueuePopover() {
        closeQueuePopover()

        let listController = PlaybackQueueListViewController()
        listController.setRows(buildQueueListRows())
        listController.onSelectQueueItem = { [weak self] item in
            self?.playQueuedItem(item)
            self?.closeQueuePopover()
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = listController
        popover.show(relativeTo: queueButton.bounds, of: queueButton, preferredEdge: .maxY)

        queuePopover = popover
        queueListViewController = listController
        refreshImmersiveChromePinnedState()
    }

    private func closeQueuePopover() {
        queuePopover?.close()
        queuePopover = nil
        if usesImmersiveChrome {
            noteImmersiveChromePointerActivity()
        }
        queueListViewController = nil
    }

    private func refreshQueuePopoverIfNeeded() {
        guard queuePopover?.isShown == true, let listController = queueListViewController else { return }
        listController.setRows(buildQueueListRows())
    }

    @discardableResult
    private func handleDroppedURLs(_ urls: [URL], queueOnly: Bool) -> Bool {
        guard let first = urls.first else { return false }

        if queueOnly {
            appendToQueue(urls)
            queueDropZone.flashAccepted()
            return true
        }

        switch MediaKindDetector.kind(for: first) {
        case .video:
            dismissSidePanelsForFocusedPlayback()
            dismissLibraryChromeForPlayback()
            loadVideo(url: first, replaceCurrent: true)
            let rest = Array(urls.dropFirst())
            if !rest.isEmpty {
                appendToQueue(rest)
            }
            return true
        case .image:
            if urls.count > 1 {
                showCodecWarning("Only the first image was opened. Queue is for videos only.")
            }
            dismissSidePanelsForFocusedPlayback()
            loadImage(url: first)
            return true
        case .unsupported:
            showUnsupportedFileMessage("Unsupported file type. Drop a video or image.")
            return false
        }
    }

    func showEmptySurface() {
        activeMediaKind = .empty
        hideCompatibilityFailure()
        renderMonitor.reset()
        endSecurityScopedAccess()
        suspendPlayerOutputForStillOrEmpty()
        currentMediaURL = nil
        playbackSourceURL = nil
        activePlaybackFileURL = nil
        imageSurfaceView.clearImage()
        lastImageSize = nil
        lastVideoCodecFourCC = nil
        lastVideoSize = nil
        lastAudioSummary = "Unknown"
        lastVideoTrackSummary = "Unknown"
        updateVideoInfoLabels()
        imageSurfaceView.isHidden = true
        playerSurfaceView.isHidden = false
        controlsContainer.isHidden = true
        imageControlsContainer.isHidden = true
        openButton.isHidden = true
        hintLabel.isHidden = true
        playerSurfaceView.isHidden = true
        dragHostView.setPlaybackBackdropActive(false)
        hideSettingsSheet()
        showFullMediaLibrary()
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        raisePlaybackChromeToFront()
        syncPlayingWindowTitle()
        removeImmersivePointerMonitor()
        setImmersiveChromeVisible(true, animated: false)
        applyWindowAspectFromSettings()
    }

    private func showVideoChrome() {
        activeMediaKind = .video
        dismissLibraryChromeForPlayback()
        hideMediaLibrary()
        dragHostView.setPlaybackBackdropActive(true)
        imageSurfaceView.isHidden = true
        if !mpvBackendActive {
            connectPlayerToVideoSurfaces()
        }
        playerSurfaceView.isHidden = false
        imageControlsContainer.isHidden = true
        openButton.isHidden = true
        hintLabel.isHidden = true
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        raisePlaybackChromeToFront()
        updatePlaybackBarWidth()
        applyResponsiveControlsLayout()
        updatePlaybackVolumeChromeVisibility()
        syncQueueChrome()
        syncPlayingWindowTitle()
        syncPlaybackBarVisibilityForCurrentState()
        if !playbackPrepareActive && !fallbackInProgress {
            resetImmersiveChromeAfterMediaChange()
        }
    }

    private func dismissLibraryChromeForPlayback() {
        guard libraryChromeInstalled else { return }
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = true
        libraryBrowse.isHidden = true
        playbackMiniPreview.isHidden = true
    }

    private func showImageChrome() {
        activeMediaKind = .image
        hideMediaLibrary()
        dragHostView.setPlaybackBackdropActive(false)
        imageSurfaceView.isHidden = false
        playerSurfaceView.isHidden = true
        openButton.isHidden = true
        hintLabel.isHidden = true
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        raisePlaybackChromeToFront()
        updatePlaybackBarWidth()
        syncQueueChrome()
        syncPlayingWindowTitle()
        resetImmersiveChromeAfterMediaChange()
    }

    /// Queue drop target is shown only when something is already playing or queued.
    private var canAcceptQueueDrop: Bool {
        currentMediaURL != nil || !queue.isEmpty
    }

    private func setQueueDropZoneVisibleForDrag(_ visible: Bool) {
        let shouldShow = visible && canAcceptQueueDrop
        let shouldHide = !shouldShow
        guard queueDropZone.isHidden != shouldHide else { return }
        queueDropZone.isHidden = shouldHide
        if shouldShow {
            raisePlaybackChromeToFront()
        }
    }

    private func styleTitleBarChromeStrip() {
        ImmersiveWindowChrome.applyFrostedPanelStyle(to: titleBarChromeStrip, leadingShadow: false)
    }

    private func styleRightSettingsPanel() {
        ImmersiveWindowChrome.applyFrostedPanelStyle(to: rightSettingsSheet, leadingShadow: true)
    }

    private func configureSettingsTabsAppearance() {
        videoSettingsTabsRow.orientation = .horizontal
        videoSettingsTabsRow.alignment = .centerY
        videoSettingsTabsRow.distribution = .fillEqually
        videoSettingsTabsRow.spacing = 0
        imageSettingsTabsRow.orientation = .horizontal
        imageSettingsTabsRow.alignment = .centerY
        imageSettingsTabsRow.distribution = .fillEqually
        imageSettingsTabsRow.spacing = 0

        buildSettingsTabButtons(
            titlesAndSymbols: [("Video", "film"), ("Audio", "speaker.wave.2"), ("Subtitles", "captions.bubble")],
            in: videoSettingsTabsRow,
            storage: &videoSettingsTabButtons,
            headerStorage: &videoSettingsTabHeaders,
            action: #selector(videoSettingsTabPressed(_:))
        )
        buildSettingsTabButtons(
            titlesAndSymbols: [("Image", "slider.horizontal.3"), ("Fit & Zoom", "arrow.up.left.and.arrow.down.right")],
            in: imageSettingsTabsRow,
            storage: &imageSettingsTabButtons,
            headerStorage: &imageSettingsTabHeaders,
            action: #selector(imageSettingsTabPressed(_:))
        )
        applySettingsTabButtonState()
    }

    private func buildSettingsTabButtons(
        titlesAndSymbols: [(String, String)],
        in row: NSStackView,
        storage: inout [HoverTextButton],
        headerStorage: inout [SettingsTabHeaderItemView],
        action: Selector
    ) {
        row.arrangedSubviews.forEach { view in
            row.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        storage.removeAll()
        headerStorage.removeAll()

        for (index, payload) in titlesAndSymbols.enumerated() {
            let button = HoverTextButton()
            button.tabLabel = payload.0
            button.symbolName = payload.1
            button.tag = index
            button.target = self
            button.action = action
            button.onHoverChanged = { [weak self] _ in
                self?.applySettingsTabButtonState()
            }
            storage.append(button)
            let item = SettingsTabHeaderItemView(button: button, showsSeparator: index < titlesAndSymbols.count - 1)
            headerStorage.append(item)
            row.addArrangedSubview(item)
        }
    }

    private func applySettingsTabButtonState() {
        for (index, button) in videoSettingsTabButtons.enumerated() {
            let isActive = index == selectedVideoSettingsTabIndex
            let color: NSColor
            if isActive {
                color = LaughTheme.settingsTabActive
            } else if button.isHovered {
                color = LaughTheme.settingsTabHover
            } else {
                color = LaughTheme.settingsTabIdle
            }
            button.textColor = color
            button.needsDisplay = true
            if index < videoSettingsTabHeaders.count {
                videoSettingsTabHeaders[index].isActive = isActive
            }
        }

        for (index, button) in imageSettingsTabButtons.enumerated() {
            let isActive = index == selectedImageSettingsTabIndex
            let color: NSColor
            if isActive {
                color = LaughTheme.settingsTabActive
            } else if button.isHovered {
                color = LaughTheme.settingsTabHover
            } else {
                color = LaughTheme.settingsTabIdle
            }
            button.textColor = color
            button.needsDisplay = true
            if index < imageSettingsTabHeaders.count {
                imageSettingsTabHeaders[index].isActive = isActive
            }
        }
    }

    private func raiseSettingsSheetAbovePlaybackChrome() {
        view.addSubview(rightSettingsSheet, positioned: .above, relativeTo: controlsContainer)
        view.addSubview(rightSettingsSheet, positioned: .above, relativeTo: imageControlsContainer)
        view.addSubview(rightSettingsSheet, positioned: .above, relativeTo: queueDropZone)
        ensureSettingsTabRowsAboveContent()
    }

    private func raisePlaybackChromeToFront() {
        if !rightSettingsSheet.isHidden {
            raiseSettingsSheetAbovePlaybackChrome()
        } else {
            view.addSubview(controlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
            view.addSubview(imageControlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
            view.addSubview(queueDropZone, positioned: .above, relativeTo: rightSettingsSheet)
        }
        if libraryChromeInstalled {
            if !openButton.isHidden {
                view.addSubview(openButton, positioned: .above, relativeTo: libraryBrowse)
                view.addSubview(hintLabel, positioned: .above, relativeTo: libraryBrowse)
            }
            view.addSubview(librarySidebar, positioned: .above, relativeTo: playerSurfaceView)
            view.addSubview(libraryBrowse, positioned: .above, relativeTo: playerSurfaceView)
            view.addSubview(playbackMiniPreview, positioned: .above, relativeTo: libraryBrowse)
        }
        raiseTitleBarChromeToFront()
    }

    private func raiseTitleBarChromeToFront() {
        guard !titleBarChromeStrip.isHidden else { return }
        view.addSubview(titleBarChromeStrip, positioned: .above, relativeTo: libraryBrowse)
        view.addSubview(titleBarChromeStrip, positioned: .above, relativeTo: librarySidebar)
        view.addSubview(titleBarChromeStrip, positioned: .above, relativeTo: playbackMiniPreview)
        if !rightSettingsSheet.isHidden {
            view.addSubview(rightSettingsSheet, positioned: .above, relativeTo: titleBarChromeStrip)
        }
    }

    private func updateSettingsContentBottomInset() {
        let clearance = activeMediaKind == .empty ? settingsPanelInnerInset : settingsContentBottomClearance
        settingsContentBottomConstraint?.constant = -clearance
    }

    private func applyContextualSettingsTabs() {
        let isVideo = activeMediaKind == .video
        let isImage = activeMediaKind == .image
        videoSettingsTabsRow.isHidden = !isVideo
        imageSettingsTabsRow.isHidden = !isImage
        applySettingsTabButtonState()
        if isImage {
            updateSettingsTabVisibility()
        } else if isVideo {
            updateSettingsTabVisibility()
        }
    }

    private func beginSecurityScopedAccess(for url: URL) {
        if let previous = securityScopedMediaURL {
            previous.stopAccessingSecurityScopedResource()
            securityScopedMediaURL = nil
        }
        if url.startAccessingSecurityScopedResource() {
            securityScopedMediaURL = url
        }
    }

    private func endSecurityScopedAccess() {
        securityScopedMediaURL?.stopAccessingSecurityScopedResource()
        securityScopedMediaURL = nil
    }

    private func updateAspectRatio(asset: AVURLAsset) {
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else {
                    await MainActor.run {
                        self.showCompatibilityFailure(
                            "This file has no readable video track.\n\nThe container or codec may not be supported by native macOS playback."
                        )
                    }
                    return
                }
                let formatDescriptions = try await track.load(.formatDescriptions)
                if let formatDesc = formatDescriptions.first {
                    let codec = CMFormatDescriptionGetMediaSubType(formatDesc)
                    let fourCC = fourCCString(codec)
                    await MainActor.run {
                        print("[DEBUG-playback] video codec fourcc=\(fourCC)")
                        self.lastVideoCodecFourCC = fourCC
                        self.renderMonitor.videoCodecFourCC = fourCC
                        self.updateVideoInfoLabels()
                    }
                }
                let natural = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformed = natural.applying(transform)
                let width = abs(transformed.width)
                let height = abs(transformed.height)
                guard width > 0, height > 0 else { return }
                await MainActor.run {
                    self.lastVideoSize = CGSize(width: width, height: height)
                    self.lastVideoTrackSummary = "\(tracks.count) track\(tracks.count == 1 ? "" : "s")"
                    self.updateVideoInfoLabels()
                    self.applyWindowAspectFromSettings()
                }

                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                var audioSummary = "No audio track"
                if let audioTrack = audioTracks.first {
                    let audioFormats = try await audioTrack.load(.formatDescriptions)
                    if let first = audioFormats.first {
                        let audioCodec = self.fourCCString(CMFormatDescriptionGetMediaSubType(first))
                        audioSummary = "codec=\(audioCodec), tracks=\(audioTracks.count)"
                    } else {
                        audioSummary = "tracks=\(audioTracks.count)"
                    }
                }
                await MainActor.run {
                    self.lastAudioSummary = audioSummary
                    self.updateVideoInfoLabels()
                    self.applyWindowAspectFromSettings()
                }
            } catch {
                // Ignore bad metadata and keep current layout behavior.
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard playerInterfaceInstalled else { return }
        updateTitleBarChromeLayout()
        applyUIScaleIfNeeded()
        updatePlaybackBarWidth()
        updateMiniPreviewLayout()
        applyResponsiveControlsLayout()
    }

    private func uiScaleForCurrentViewport() -> CGFloat {
        let width = max(view.bounds.width, 1)
        switch width {
        case 0..<1400:
            return 1.0
        case 1400..<2200:
            return 1.12
        case 2200..<3200:
            return 1.25
        default:
            return 1.38
        }
    }

    private func applyUIScaleIfNeeded() {
        let scale = uiScaleForCurrentViewport()
        guard abs(scale - lastAppliedUIScale) > 0.01 else { return }
        lastAppliedUIScale = scale

        librarySidebarWidthConstraint?.constant = baseLibrarySidebarWidth * scale
        settingsPanelWidthConstraint?.constant = baseSettingsPanelWidth * scale

        let tabButtons = videoSettingsTabButtons + imageSettingsTabButtons
        tabButtons.forEach { $0.uiScale = scale }
    }

    private func fourCCString(_ code: FourCharCode) -> String {
        let n = code.bigEndian
        let chars: [CChar] = [
            CChar((n >> 24) & 0xff),
            CChar((n >> 16) & 0xff),
            CChar((n >> 8) & 0xff),
            CChar(n & 0xff),
            0
        ]
        return String(cString: chars)
    }

    private func shouldMonitorVideoRendering(codec: String?) -> Bool {
        guard let codec = codec?.lowercased() else { return false }
        if Self.optimisticFallbackCodecs.contains(codec) { return false }
        if Self.nativeVideoCodecs.contains(codec) { return false }
        return true
    }

    private func isNativeVideoCodec(_ codec: String?) -> Bool {
        guard let codec = codec?.lowercased() else { return false }
        return Self.nativeVideoCodecs.contains(codec)
    }

    private func detachCurrentPlayerItemObserver() {
        if let observedItem {
            observedItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            self.observedItem = nil
        }
    }

    private func isGeneratedFallbackURL(_ url: URL) -> Bool {
        url.path.contains("/LaughPlayerFallback/")
    }

    @objc private func openVideoPressed() {
        delegate?.playerViewControllerDidRequestOpenVideo(self)
    }

    private func showPlaybackError(_ message: String) {
        print("[DEBUG-playback] Error: \(message)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot play this video"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showCodecWarning(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Codec Compatibility Warning"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showCompatibilityFailure(_ message: String) {
        print("[DEBUG-playback] CompatibilityFailure: \(message)")
        compatibilityBanner.show(message: message)
        view.addSubview(compatibilityBanner, positioned: .above, relativeTo: rightSettingsSheet)
        raisePlaybackChromeToFront()
    }

    /// When bundled ffmpeg is available, remux and retry; otherwise show the user-facing explanation.
    private func handleNativePlaybackUnavailable(_ message: String) {
        guard PlaybackRuntime.canUseBundledCodecStack else {
            showCompatibilityFailure(message)
            return
        }
        guard let inputURL = currentMediaURL, !isGeneratedFallbackURL(inputURL) else {
            showCompatibilityFailure(message)
            return
        }
        if FFmpegVideoFallback.isAvailable() {
            attemptFFmpegFallbackIfNeeded()
        } else {
            showCompatibilityFailure(message)
        }
    }

    private func hideCompatibilityFailure() {
        compatibilityBanner.hideBanner()
    }

    private func handleRenderFailure(_ message: String) {
        if let url = currentMediaURL, isGeneratedFallbackURL(url) {
            print("[DEBUG-playback] render issue on compatibility file (no re-fallback): \(message)")
            return
        }
        if isNativeVideoCodec(lastVideoCodecFourCC) {
            print("[DEBUG-playback] render probe ignored for native codec=\(lastVideoCodecFourCC ?? "?") (no ffmpeg)")
            return
        }
        showCompatibilityFailure(message)
        attemptFFmpegFallbackIfNeeded()
    }

    private func attemptFFmpegFallbackIfNeeded(plannedRoute: Bool = false, generation: Int? = nil) {
        guard !fallbackInProgress else { return }
        guard let inputURL = currentMediaURL else { return }
        guard !isGeneratedFallbackURL(inputURL) else { return }

        let activeGeneration = generation ?? videoLoadGeneration

        guard FFmpegVideoFallback.isAvailable() else {
            let lookup = BundledCodecTools.diagnosticSummary(for: "ffmpeg")
            showCompatibilityFailure(
                "Native playback failed for this codec.\n\nBundled compatibility decoder is not available in this build.\n\nFFmpeg lookup:\n\(lookup)"
            )
            return
        }

        if !isMutedForSwitch {
            preparePlayerForVideoSwitch()
        }
        let mpvResumeSec = mpvBackendActive ? (activeSession?.currentTimeSec ?? 0) : nil
        stopMpvBackend()
        FFmpegVideoFallback.terminateRunningProcesses()
        clearPreviewPlaybackState(preserveSourceDuration: playbackPrepareActive)

        let resumeTime: CMTime
        if let mpvResumeSec, mpvResumeSec.isFinite, mpvResumeSec > 0 {
            resumeTime = CMTime(seconds: mpvResumeSec, preferredTimescale: 600)
        } else {
            resumeTime = currentPlayerItemMatchesSource(inputURL) ? player.currentTime() : .zero
        }
        let rawResumeTargetSec = CMTimeGetSeconds(resumeTime)

        if FFmpegVideoFallback.shouldPreferBlockingRemux(for: inputURL) {
            print("[DEBUG-fallback] blocking remux preferred (audio transcode)")
            runBlockingRemuxFallback(
                inputURL: inputURL,
                activeGeneration: activeGeneration,
                resumeTime: resumeTime,
                rawResumeTargetSec: rawResumeTargetSec,
                plannedRoute: plannedRoute
            )
            return
        }

        switch FFmpegVideoFallback.beginRemux(inputURL: inputURL) {
        case .cacheHit(let cachedURL):
            print("[DEBUG-fallback] cache hit path=\(cachedURL.path)")
            fallbackInProgress = true
            updateSeekBarPreparingState()
            if rawResumeTargetSec.isFinite && rawResumeTargetSec >= 0 {
                pendingStartTimeAfterLoad = resumeTime
            }
            resolveAndAttach(playableURL: cachedURL, sourceURL: inputURL, generation: activeGeneration)
            return
        case .failed:
            showCompatibilityFailure(PlaybackErrorFormatter.remuxFailedMessage(for: inputURL))
            return
        case .progressivePreview(let previewOutput, let fullTarget):
            startProgressivePreviewPlayback(
                previewURL: previewOutput,
                fullTargetURL: fullTarget,
                inputURL: inputURL,
                activeGeneration: activeGeneration,
                resumeTime: resumeTime,
                rawResumeTargetSec: rawResumeTargetSec,
                plannedRoute: plannedRoute
            )
            return
        }
    }

    private func startProgressivePreviewPlayback(
        previewURL: URL,
        fullTargetURL: URL,
        inputURL: URL,
        activeGeneration: Int,
        resumeTime: CMTime,
        rawResumeTargetSec: Double,
        plannedRoute: Bool
    ) {
        fallbackInProgress = true
        fallbackSessionToken += 1
        let sessionToken = fallbackSessionToken
        fallbackStartedAt = CFAbsoluteTimeGetCurrent()
        fallbackResumeTargetSec = rawResumeTargetSec.isFinite ? max(0, rawResumeTargetSec) : nil
        fallbackLastMethod = "remux-preview"
        updatePlayPauseButtonIcon()
        updateSeekBarPreparingState()

        print("[DEBUG-fallback] preview poll preview=\(previewURL.path) full=\(fullTargetURL.path)")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let sourceDuration = FFmpegVideoFallback.probeSourceDurationSec(for: inputURL)
            await MainActor.run {
                guard sessionToken == self.fallbackSessionToken else { return }
                self.activePreviewSourceDurationSec = sourceDuration
                self.updateSeekBarPreparingState()
            }

            var attachedPreview = false
            let pollIntervalNs: UInt64 = 100_000_000
            let maxWaitNs: UInt64 = 120 * 1_000_000_000
            var waited: UInt64 = 0

            while waited < maxWaitNs {
                if Task.isCancelled { return }

                let stillValid = await MainActor.run {
                    sessionToken == self.fallbackSessionToken
                        && activeGeneration == self.videoLoadGeneration
                }
                guard stillValid else { return }

                if FFmpegVideoFallback.isFullRemuxReady(at: fullTargetURL) {
                    await MainActor.run {
                        guard sessionToken == self.fallbackSessionToken else { return }
                        self.fallbackInProgress = false
                        self.updateSeekBarPreparingState()
                        self.fallbackLastMethod = "remux"
                        self.hideCompatibilityFailure()
                        self.clearPreviewPlaybackState()
                        if rawResumeTargetSec.isFinite && rawResumeTargetSec >= 0 {
                            self.pendingStartTimeAfterLoad = resumeTime
                        }
                        print("[DEBUG-fallback] full remux ready — attaching")
                        self.fallbackConvertedOutputPaths.insert(fullTargetURL.path)
                        self.resolveAndAttach(
                            playableURL: fullTargetURL,
                            sourceURL: inputURL,
                            generation: activeGeneration
                        )
                    }
                    return
                }

                if !attachedPreview,
                   await FFmpegVideoFallback.isPreviewReadableEnoughForPlayback(url: previewURL) {
                    attachedPreview = true
                    let waitedMs = Double(waited) / 1_000_000
                    await MainActor.run {
                        guard sessionToken == self.fallbackSessionToken else { return }
                        self.fallbackInProgress = false
                        self.updateSeekBarPreparingState()
                        self.fallbackLastMethod = "remux-preview"
                        self.fallbackConvertedOutputPaths.insert(previewURL.path)
                        self.hideCompatibilityFailure()
                        if rawResumeTargetSec.isFinite && rawResumeTargetSec >= 0 {
                            self.pendingStartTimeAfterLoad = resumeTime
                        }
                        print("[DEBUG-fallback] chunked preview start waitedMs=\(waitedMs) sourceDur=\(sourceDuration ?? 0)s")
                        self.activePreviewFullTargetURL = fullTargetURL
                        self.activePreviewSourceDurationSec = sourceDuration
                        self.activePlayableDurationSec = 0
                        self.resolveAndAttach(
                            playableURL: previewURL,
                            sourceURL: inputURL,
                            generation: activeGeneration
                        )
                        self.startProgressiveExtentMonitor(
                            previewURL: previewURL,
                            sessionToken: sessionToken
                        )
                        self.scheduleUpgradeToFullRemux(
                            previewURL: previewURL,
                            fullTargetURL: fullTargetURL,
                            sourceURL: inputURL,
                            generation: activeGeneration,
                            sessionToken: sessionToken
                        )
                    }
                    return
                }

                let previewRunning = FFmpegVideoFallback.isRemuxing(outputURL: previewURL)
                let fullRunning = FFmpegVideoFallback.isBackgroundFullRemuxing(outputURL: fullTargetURL)
                if !previewRunning && !fullRunning && waited > 2_000_000_000 {
                    break
                }

                try? await Task.sleep(nanoseconds: pollIntervalNs)
                waited += pollIntervalNs
            }

            let result = FFmpegVideoFallback.convertToPlayable(inputURL: inputURL)
            await MainActor.run {
                guard sessionToken == self.fallbackSessionToken else { return }
                self.fallbackInProgress = false
                guard let result else {
                    self.leavePlaybackPrepareUI()
                    if !plannedRoute {
                        self.showCompatibilityFailure(PlaybackErrorFormatter.remuxFailedMessage(for: inputURL))
                    }
                    self.fallbackStartedAt = nil
                    self.fallbackResumeTargetSec = nil
                    self.fallbackLastMethod = nil
                    return
                }
                self.fallbackLastMethod = result.method
                self.fallbackConvertedOutputPaths.insert(result.outputURL.path)
                self.hideCompatibilityFailure()
                self.clearPreviewPlaybackState()
                if rawResumeTargetSec.isFinite && rawResumeTargetSec >= 0 {
                    self.pendingStartTimeAfterLoad = resumeTime
                }
                self.resolveAndAttach(
                    playableURL: result.outputURL,
                    sourceURL: inputURL,
                    generation: activeGeneration
                )
            }
        }
    }

    private func clearPreviewPlaybackState(preserveSourceDuration: Bool = false) {
        activePreviewFullTargetURL = nil
        if !preserveSourceDuration {
            activePreviewSourceDurationSec = nil
        }
        activePlayableDurationSec = 0
        progressiveExtendInProgress = false
        progressiveExtentMonitorToken += 1
        updateSeekBarPreparingState()
    }

    private var isPreviewPlaybackActive: Bool {
        activePreviewFullTargetURL != nil
    }

    /// Re-open the growing fragmented MP4 when AVPlayer hits a ~36s fMP4 chunk boundary.
    private func extendProgressivePlaybackIfNeeded(force: Bool = false) -> Bool {
        guard isPreviewPlaybackActive,
              !progressiveExtendInProgress,
              let previewURL = observedItemPlayableURL,
              let sourceURL = playbackSourceURL ?? currentMediaURL,
              let sourceDuration = activePreviewSourceDurationSec,
              sourceDuration > 60 else { return false }

        let itemDuration = CMTimeGetSeconds(player.currentItem?.duration ?? .invalid)
        guard itemDuration.isFinite, itemDuration > 0 else { return false }

        let currentSec = CMTimeGetSeconds(player.currentTime())
        guard currentSec.isFinite, currentSec >= 0 else { return false }

        guard sourceDuration > itemDuration + 10 else { return false }

        let nearChunkEnd = force || currentSec >= itemDuration - 1.0
        guard nearChunkEnd else { return false }
        guard currentSec < sourceDuration - 5 else { return false }

        if !force, CFAbsoluteTimeGetCurrent() - lastProgressiveExtendWallTime < 1.0 { return false }

        let previewStillRemuxing = FFmpegVideoFallback.isRemuxing(outputURL: previewURL)
        let fullStillRemuxing = activePreviewFullTargetURL.map {
            FFmpegVideoFallback.isBackgroundFullRemuxing(outputURL: $0)
        } ?? false
        let playableGrew = activePlayableDurationSec > itemDuration + 2
        guard previewStillRemuxing || fullStillRemuxing || playableGrew || force else { return false }

        progressiveExtendInProgress = true
        lastProgressiveExtendWallTime = CFAbsoluteTimeGetCurrent()
        pendingStartTimeAfterLoad = player.currentTime()
        pendingResumePlayingAfterLoad = player.rate > 0
        print(String(
            format: "[DEBUG-fallback] extend chunk at %.1fs itemDur=%.1fs playable=%.1fs source=%.1fs",
            currentSec, itemDuration, activePlayableDurationSec, sourceDuration
        ))
        resolveAndAttach(
            playableURL: previewURL,
            sourceURL: sourceURL,
            generation: videoLoadGeneration
        )
        return true
    }

    private func startProgressiveExtentMonitor(previewURL: URL, sessionToken: Int) {
        progressiveExtentMonitorToken += 1
        let token = progressiveExtentMonitorToken
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let stillActive = await MainActor.run {
                    token == self.progressiveExtentMonitorToken
                        && sessionToken == self.fallbackSessionToken
                        && self.isPreviewPlaybackActive
                }
                guard stillActive else { return }

                let probed = FFmpegVideoFallback.remuxOutputDurationSec(at: previewURL) ?? 0
                if probed > 0 {
                    await MainActor.run {
                        guard token == self.progressiveExtentMonitorToken else { return }
                        if probed > self.activePlayableDurationSec {
                            self.activePlayableDurationSec = probed
                            self.updateSeekBarPreparingState()
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func scheduleUpgradeToFullRemux(
        previewURL: URL,
        fullTargetURL: URL,
        sourceURL: URL,
        generation: Int,
        sessionToken: Int
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let pollIntervalNs: UInt64 = 1_000_000_000
            while !Task.isCancelled {
                let stillValid = await MainActor.run {
                    sessionToken == self.fallbackSessionToken && generation == self.videoLoadGeneration
                }
                guard stillValid else { return }

                guard FFmpegVideoFallback.isFullRemuxReady(at: fullTargetURL) else {
                    try? await Task.sleep(nanoseconds: pollIntervalNs)
                    continue
                }

                await MainActor.run {
                    guard sessionToken == self.fallbackSessionToken else { return }
                    guard generation == self.videoLoadGeneration else { return }
                    guard self.observedItemPlayableURL?.standardizedFileURL == previewURL.standardizedFileURL else {
                        return
                    }

                    let resume = self.player.currentTime()
                    self.pendingStartTimeAfterLoad = resume
                    self.fallbackLastMethod = "remux"
                    self.fallbackConvertedOutputPaths.insert(fullTargetURL.path)
                    self.clearPreviewPlaybackState()
                    print("[DEBUG-fallback] upgrading preview → full remux at \(CMTimeGetSeconds(resume))s")
                    self.resolveAndAttach(
                        playableURL: fullTargetURL,
                        sourceURL: sourceURL,
                        generation: generation
                    )
                    try? FileManager.default.removeItem(at: previewURL)
                    Task { @MainActor in await self.refreshSubtitleSettings() }
                }
                return
            }
        }
    }

    private func runBlockingRemuxFallback(
        inputURL: URL,
        activeGeneration: Int,
        resumeTime: CMTime,
        rawResumeTargetSec: Double,
        plannedRoute: Bool
    ) {
        fallbackInProgress = true
        fallbackSessionToken += 1
        let sessionToken = fallbackSessionToken
        fallbackStartedAt = CFAbsoluteTimeGetCurrent()
        fallbackResumeTargetSec = rawResumeTargetSec.isFinite ? max(0, rawResumeTargetSec) : nil
        fallbackLastMethod = "remux-blocking"
        updatePlayPauseButtonIcon()
        updateSeekBarPreparingState()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result = FFmpegVideoFallback.convertToPlayable(inputURL: inputURL)
            await MainActor.run {
                guard sessionToken == self.fallbackSessionToken else { return }
                guard activeGeneration == self.videoLoadGeneration else { return }
                self.fallbackInProgress = false
                guard let result else {
                    self.leavePlaybackPrepareUI()
                    if !plannedRoute {
                        self.showCompatibilityFailure(PlaybackErrorFormatter.remuxFailedMessage(for: inputURL))
                    }
                    self.fallbackStartedAt = nil
                    self.fallbackResumeTargetSec = nil
                    self.fallbackLastMethod = nil
                    return
                }
                self.fallbackLastMethod = result.method
                self.fallbackConvertedOutputPaths.insert(result.outputURL.path)
                self.hideCompatibilityFailure()
                if rawResumeTargetSec.isFinite && rawResumeTargetSec >= 0 {
                    self.pendingStartTimeAfterLoad = resumeTime
                }
                print("[DEBUG-fallback] blocking remux finished method=\(result.method) elapsedMs=\(result.elapsedMs)")
                self.resolveAndAttach(
                    playableURL: result.outputURL,
                    sourceURL: inputURL,
                    generation: activeGeneration
                )
            }
        }
    }

    private func showUnsupportedFileMessage(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unsupported File"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func configureImageControls() {
        styleIconButton(imageZoomOutButton, symbol: "minus.magnifyingglass", label: "Zoom out")
        styleIconButton(imageZoomInButton, symbol: "plus.magnifyingglass", label: "Zoom in")
        styleIconButton(imageFitButton, symbol: "arrow.up.left.and.arrow.down.right", label: "Fit")
        imageZoomOutButton.target = self
        imageZoomInButton.target = self
        imageFitButton.target = self
        imageSettingsButton.target = self
        imageZoomOutButton.action = #selector(imageZoomOut)
        imageZoomInButton.action = #selector(imageZoomIn)
        imageFitButton.action = #selector(imageFit)
        imageSettingsButton.action = #selector(settingsPressed)

        imageControlsStack.alignment = .centerY
        imageControlsStack.distribution = .equalCentering
        imageControlsStack.spacing = 16
        imageControlsStack.addArrangedSubview(imageZoomOutButton)
        imageControlsStack.addArrangedSubview(imageZoomInButton)
        imageControlsStack.addArrangedSubview(imageFitButton)

        imageAccessoryCluster.orientation = .horizontal
        imageAccessoryCluster.alignment = .centerY
        imageAccessoryCluster.spacing = 0
        imageAccessoryCluster.translatesAutoresizingMaskIntoConstraints = false
        imageAccessoryCluster.addArrangedSubview(imageSettingsButton)
    }

    private func configurePlaybackAccessoryClusters() {
        playbackAccessoryCluster.orientation = .horizontal
        playbackAccessoryCluster.alignment = .centerY
        playbackAccessoryCluster.spacing = 0
        playbackAccessoryCluster.translatesAutoresizingMaskIntoConstraints = false
        playbackAccessoryCluster.setContentHuggingPriority(.required, for: .horizontal)
        playbackAccessoryCluster.setContentCompressionResistancePriority(.required, for: .horizontal)

        imageAccessoryCluster.setContentHuggingPriority(.required, for: .horizontal)
        imageAccessoryCluster.setContentCompressionResistancePriority(.required, for: .horizontal)

        moveQueueButtonToPlaybackAccessoryCluster()
    }

    private func moveQueueButtonToPlaybackAccessoryCluster() {
        if queueButton.superview === playbackAccessoryCluster { return }
        queueButton.removeFromSuperview()
        playbackAccessoryCluster.insertArrangedSubview(queueButton, at: 0)
        if !playbackAccessoryCluster.arrangedSubviews.contains(settingsButton) {
            playbackAccessoryCluster.addArrangedSubview(settingsButton)
        }
    }

    private func moveQueueButtonToImageAccessoryCluster() {
        if queueButton.superview === imageAccessoryCluster { return }
        queueButton.removeFromSuperview()
        imageAccessoryCluster.insertArrangedSubview(queueButton, at: 0)
        if !imageAccessoryCluster.arrangedSubviews.contains(imageSettingsButton) {
            imageAccessoryCluster.addArrangedSubview(imageSettingsButton)
        }
    }

    private func configureControls() {
        configurePlaybackAccessoryClusters()
        styleIconButton(queuePreviousButton, symbol: "backward.end.fill", label: "Previous in queue", pointSize: 13)
        styleIconButton(speedStepDownButton, symbol: "backward.fill", label: "Slower", pointSize: 13)
        styleIconButton(speedStepUpButton, symbol: "forward.fill", label: "Faster", pointSize: 13)
        styleIconButton(queueNextButton, symbol: "forward.end.fill", label: "Next in queue", pointSize: 13)
        configureTransportSpeedLabel(playbackSpeedSlowLabel, alignment: .right)
        configureTransportSpeedLabel(playbackSpeedFastLabel, alignment: .left)
        configurePlaybackBarAccessoryButton(libraryButton, symbol: "folder", label: "Library")
        configurePlaybackBarAccessoryButton(queueButton, symbol: "list.bullet", label: "Queue")
        configurePlaybackBarAccessoryButton(settingsButton, symbol: "gearshape", label: "Settings")
        configurePlaybackBarAccessoryButton(imageSettingsButton, symbol: "gearshape", label: "Settings")

        playPauseButton.bezelStyle = .accessoryBarAction
        playPauseButton.isBordered = false
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        playPauseButton.setButtonType(.momentaryPushIn)
        pinTransportIconButtonSize(playPauseButton, width: 32, height: 28)
        pinTransportIconButtonSize(queuePreviousButton)
        pinTransportIconButtonSize(speedStepDownButton)
        pinTransportIconButtonSize(speedStepUpButton)
        pinTransportIconButtonSize(queueNextButton)
        updatePlayPauseButtonIcon()

        queuePreviousButton.target = self
        speedStepDownButton.target = self
        speedStepUpButton.target = self
        queueNextButton.target = self
        queueButton.target = self
        settingsButton.target = self
        libraryButton.target = self
        queuePreviousButton.action = #selector(queuePreviousPressed)
        speedStepDownButton.action = #selector(speedStepDownPressed)
        speedStepUpButton.action = #selector(speedStepUpPressed)
        queueNextButton.action = #selector(queueNextPressed)
        queuePreviousButton.isHidden = true
        queueNextButton.isHidden = true
        queueButton.action = #selector(queuePressed)
        settingsButton.action = #selector(settingsPressed)
        libraryButton.action = #selector(libraryPressed)

        seekSlider.target = self
        seekSlider.action = #selector(seekSliderChanged)
        seekSlider.isContinuous = false
        seekSlider.controlSize = .mini
        seekSlider.useFlatBarAppearance(trackHeight: 3)

        volumeCluster.orientation = .horizontal
        volumeCluster.alignment = .centerY
        volumeCluster.spacing = 6
        volumeCluster.addArrangedSubview(volumeMuteButton)
        volumeCluster.addArrangedSubview(volumeSlider)

        volumeMuteButton.target = self
        volumeMuteButton.action = #selector(volumeMuteButtonPressed)
        styleIconButton(volumeMuteButton, symbol: "speaker.wave.2.fill", label: "Mute", pointSize: 13)
        pinTransportIconButtonSize(volumeMuteButton, width: 24, height: 24)

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged)
        volumeSlider.controlSize = .mini
        volumeSlider.useFlatBarAppearance(trackHeight: 3)
        volumeSliderWidthConstraint = volumeSlider.widthAnchor.constraint(equalToConstant: 58)
        volumeSliderWidthConstraint?.isActive = true
        volumeSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        volumeSlider.setContentHuggingPriority(.required, for: .horizontal)
        setupPlaybackTopRowLayout()
        player.volume = 1
        player.isMuted = false
        desiredPlaybackVolume = 1
        updateVolumeMuteButtonIcon()

        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        currentTimeLabel.textColor = .secondaryLabelColor
        currentTimeLabel.alignment = .right
        totalTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        totalTimeLabel.textColor = .secondaryLabelColor
        totalTimeLabel.alignment = .left
        currentTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        seekSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        configureVideoSettingsControls()
        preferredPlaybackRate = SettingsStore.shared.playbackSpeed
        player.defaultRate = preferredPlaybackRate
        updatePlaybackSpeedTransportLabels()
        applyVideoFitMode(SettingsStore.shared.videoFitMode)
        installPlayToEndObserver()
        updateVideoInfoLabels()
    }

    private func configureSettingsTabViews() {
        [videoTabView, audioTabView, subtitlesTabView].forEach { stack in
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.distribution = .fill
            stack.spacing = settingsStackSpacing
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }

        addSettingsSection(to: videoTabView, title: "Decode", isFirst: true) { card in
            card.addFinalRow(SettingsRowFactory.valueRow(title: "Path", control: playbackSourcePopUp))
        }
        addSettingsSection(to: videoTabView, title: "Playback") { card in
            card.addRow(makePlaybackSpeedSectionRow())
            card.addFinalRow(SettingsRowFactory.toggleRow(title: "Loop playback", control: loopPlaybackCheckbox))
        }
        addSettingsSection(to: videoTabView, title: "Display") { card in
            card.addRow(SettingsRowFactory.stackedRow(title: "Scale", control: videoFitModeControl))
            card.addRow(SettingsRowFactory.stackedRow(title: "Aspect", control: windowAspectControl))
            card.addFinalRow(
                SettingsRowFactory.toggleRow(title: "Lock window to video aspect", control: lockAspectCheckbox)
            )
        }

        configureAudioSettingsTab()
        configureSubtitlesSettingsTab()

        let imageTitle = NSTextField(labelWithString: "Image Settings")
        imageTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let imageHint = NSTextField(labelWithString: "Display and export options will appear here.")
        imageHint.textColor = .secondaryLabelColor
        imageHint.maximumNumberOfLines = 0
        imageTabView.addArrangedSubview(imageTitle)
        imageTabView.addArrangedSubview(imageHint)

        let fitTitle = NSTextField(labelWithString: "Fit & Zoom")
        fitTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let fitHint = NSTextField(labelWithString: "Use Fit and zoom controls in the playback bar.")
        fitHint.textColor = .secondaryLabelColor
        fitHint.maximumNumberOfLines = 0
        imageFitTabView.addArrangedSubview(fitTitle)
        imageFitTabView.addArrangedSubview(fitHint)

        [imageTabView, imageFitTabView].forEach { stack in
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = settingsStackSpacing
            stack.translatesAutoresizingMaskIntoConstraints = false
        }

        settingsContentContainer.addSubview(videoTabView)
        settingsContentContainer.addSubview(audioTabView)
        settingsContentContainer.addSubview(subtitlesTabView)
        settingsContentContainer.addSubview(imageTabView)
        settingsContentContainer.addSubview(imageFitTabView)

        [videoTabView, audioTabView, subtitlesTabView, imageTabView, imageFitTabView].forEach { tab in
            NSLayoutConstraint.activate([
                tab.leadingAnchor.constraint(equalTo: settingsContentContainer.leadingAnchor),
                tab.trailingAnchor.constraint(equalTo: settingsContentContainer.trailingAnchor),
                tab.topAnchor.constraint(equalTo: settingsContentContainer.topAnchor),
                tab.bottomAnchor.constraint(lessThanOrEqualTo: settingsContentContainer.bottomAnchor)
            ])
        }

        applySettingsPanelAccentChrome()
        updateSettingsTabVisibility()
    }

    private func applySettingsPanelAccentChrome() {
        LaughTheme.applySettingsAccentChrome(in: settingsContentContainer)
        applySettingsTabButtonState()
    }

    private func updateSettingsTabVisibility() {
        let videoTabs = [videoTabView, audioTabView, subtitlesTabView]
        let imageTabs = [imageTabView, imageFitTabView]
        (videoTabs + imageTabs).forEach { tab in
            tab.isHidden = true
            tab.alphaValue = 0
        }

        switch activeMediaKind {
        case .video:
            let index = max(0, min(selectedVideoSettingsTabIndex, videoTabs.count - 1))
            selectedVideoSettingsTabIndex = index
            let activeTab = videoTabs[index]
            activeTab.isHidden = false
            activeTab.alphaValue = 1
            settingsContentContainer.addSubview(activeTab, positioned: .above, relativeTo: nil)
        case .image:
            let index = max(0, min(selectedImageSettingsTabIndex, imageTabs.count - 1))
            selectedImageSettingsTabIndex = index
            let activeTab = imageTabs[index]
            activeTab.isHidden = false
            activeTab.alphaValue = 1
            settingsContentContainer.addSubview(activeTab, positioned: .above, relativeTo: nil)
        case .empty:
            break
        }
        settingsContentContainer.layoutSubtreeIfNeeded()
    }

    private func updateVideoInfoLabels() {
        refreshPlaybackSourceOptions()
    }

    private func configureVideoSettingsControls() {
        playbackSourcePopUp.target = self
        playbackSourcePopUp.action = #selector(playbackSourceChanged)
        playbackSourcePopUp.controlSize = .small
        playbackSourcePopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configureSettingsSegmentedControl(videoFitModeControl, action: #selector(videoFitChanged))
        configureSettingsSegmentedControl(windowAspectControl, action: #selector(windowAspectChanged))

        styleIconButton(playbackSpeedStepDownButton, symbol: "backward.fill", label: "Slower", pointSize: 11)
        styleIconButton(playbackSpeedStepUpButton, symbol: "forward.fill", label: "Faster", pointSize: 11)
        playbackSpeedStepDownButton.target = self
        playbackSpeedStepUpButton.target = self
        playbackSpeedStepDownButton.action = #selector(playbackSpeedStepDown)
        playbackSpeedStepUpButton.action = #selector(playbackSpeedStepUp)

        playbackSpeedSlider.minValue = 0
        playbackSpeedSlider.maxValue = Double(PlaybackSpeedSteps.rates.count - 1)
        playbackSpeedSlider.numberOfTickMarks = PlaybackSpeedSteps.rates.count
        playbackSpeedSlider.tickMarkPosition = .below
        playbackSpeedSlider.allowsTickMarkValuesOnly = true
        playbackSpeedSlider.isContinuous = false
        playbackSpeedSlider.controlSize = .small
        playbackSpeedSlider.target = self
        playbackSpeedSlider.action = #selector(playbackSpeedChanged)
        playbackSpeedValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        playbackSpeedValueLabel.textColor = .secondaryLabelColor
        playbackSpeedValueLabel.alignment = .right
        playbackSpeedValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        lockAspectCheckbox.target = self
        lockAspectCheckbox.action = #selector(lockAspectChanged)
        loopPlaybackCheckbox.target = self
        loopPlaybackCheckbox.action = #selector(loopPlaybackChanged)
        LaughTheme.applySettingsNeutralChrome(to: lockAspectCheckbox)
        LaughTheme.applySettingsNeutralChrome(to: loopPlaybackCheckbox)
        LaughTheme.applySettingsNeutralChrome(to: playbackSourcePopUp)

        syncVideoSettingsControlsFromStore()
    }

    private func syncVideoSettingsControlsFromStore() {
        let store = SettingsStore.shared
        videoFitModeControl.selectedSegment = store.videoFitMode == .fill ? 1 : 0
        if let aspectIndex = WindowAspectPreset.selectablePresets.firstIndex(of: store.windowAspectPreset) {
            windowAspectControl.selectedSegment = aspectIndex
        }
        applyPlaybackSpeed(store.playbackSpeed, persist: false)
        lockAspectCheckbox.state = store.lockAspectRatioEnabled ? .on : .off
        lockAspectCheckbox.toolTip = "When Aspect is Auto, lock the window to the video's detected ratio."
        loopPlaybackCheckbox.state = store.loopPlaybackEnabled ? .on : .off
        updateLockAspectControlAvailability()
        refreshPlaybackSourceOptions()
    }

    private func refreshPlaybackSourceOptions() {
        playbackSourcePopUp.removeAllItems()
        guard playbackSourceURL != nil || currentMediaURL != nil else {
            playbackSourcePopUp.addItem(withTitle: "—")
            playbackSourcePopUp.isEnabled = false
            return
        }

        let details = playbackSourceFormatDetails()
        let hasCompatibilityRemux = compatibilityRemuxURL(for: playbackSourceURL ?? currentMediaURL) != nil

        if hasCompatibilityRemux {
            playbackSourcePopUp.addItem(withTitle: "Native · \(details)")
            playbackSourcePopUp.addItem(withTitle: "Compatibility remux · \(details)")
        } else {
            playbackSourcePopUp.addItem(withTitle: "\(activeDecodePathLabel()) · \(details)")
        }

        playbackSourcePopUp.isEnabled = playbackSourcePopUp.numberOfItems > 1
        suppressPlaybackSourceAction = true
        let source = playbackSourceURL ?? currentMediaURL
        if isPlayingFromCompatibilityCopy(for: source) {
            playbackSourcePopUp.selectItem(at: min(1, playbackSourcePopUp.numberOfItems - 1))
        } else {
            playbackSourcePopUp.selectItem(at: 0)
        }
        suppressPlaybackSourceAction = false
    }

    /// Temp MP4 from **CompatibilityRemux** when FFmpeg already built one for this file.
    private func compatibilityRemuxURL(for source: URL?) -> URL? {
        guard let source else { return nil }
        guard let cached = FFmpegVideoFallback.cachedPlayableURL(for: source),
              cached.standardizedFileURL != source.standardizedFileURL,
              FileManager.default.fileExists(atPath: cached.path) else {
            return nil
        }
        return cached
    }

    private func activeDecodePathLabel() -> String {
        if isPlayingFromCompatibilityCopy(for: playbackSourceURL ?? currentMediaURL) {
            return "Compatibility remux"
        }
        if mpvBackendActive {
            return "Extended (mpv)"
        }
        return "Native (macOS)"
    }

    /// Codec / stream summary for the decode-path popup (no file path).
    private func playbackSourceFormatDetails() -> String {
        var parts: [String] = []
        if let codec = lastVideoCodecFourCC, !codec.isEmpty, codec != "—" {
            parts.append(codec)
        }
        if let size = lastVideoSize {
            parts.append("\(Int(size.width))×\(Int(size.height))")
            let ratio = size.width / max(size.height, 1)
            parts.append(formattedAspectRatioName(ratio))
        }
        if lastVideoTrackSummary != "Unknown" {
            parts.append(lastVideoTrackSummary)
        }
        if lastAudioSummary != "Unknown" {
            parts.append(lastAudioSummary)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func isPlayingFromCompatibilityCopy(for source: URL?) -> Bool {
        guard let source, let active = activePlaybackFileURL else { return false }
        if isGeneratedFallbackURL(active) { return true }
        if let cached = compatibilityRemuxURL(for: source) {
            return active.standardizedFileURL == cached.standardizedFileURL
        }
        return false
    }

    private func makePlaybackSpeedRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8

        let label = NSTextField(labelWithString: "Speed")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        playbackSpeedSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label)
        row.addArrangedSubview(playbackSpeedStepDownButton)
        row.addArrangedSubview(playbackSpeedSlider)
        row.addArrangedSubview(playbackSpeedStepUpButton)
        row.addArrangedSubview(playbackSpeedValueLabel)
        return row
    }

    private func formattedPlaybackSpeed(_ speed: Float) -> String {
        let rounded = (speed * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(format: "%.0f×", rounded)
        }
        return String(format: "%.2f×", rounded)
    }

    func applyPlaybackSpeed(_ speed: Float, persist: Bool = true) {
        let rate = PlaybackSpeedSteps.nearestRate(to: speed)
        let index = PlaybackSpeedSteps.index(for: rate)
        playbackSpeedSlider.integerValue = index
        playbackSpeedValueLabel.stringValue = formattedPlaybackSpeed(rate)
        preferredPlaybackRate = rate
        if persist {
            SettingsStore.shared.playbackSpeed = rate
        }
        if mpvBackendActive {
            activeSession?.setRate(rate)
        } else {
            player.defaultRate = rate
            if player.rate > 0 {
                player.rate = rate
            }
        }
        updatePlaybackSpeedTransportLabels()
    }

    func stepPlaybackSpeed(by delta: Int) {
        let index = PlaybackSpeedSteps.index(for: preferredPlaybackRate)
        let newIndex = max(0, min(index + delta, PlaybackSpeedSteps.rates.count - 1))
        guard newIndex != index else { return }
        applyPlaybackSpeed(PlaybackSpeedSteps.rates[newIndex])
    }

    private func updatePlaybackSpeedTransportLabels() {
        let index = PlaybackSpeedSteps.index(for: preferredPlaybackRate)
        let isNormalSpeed = abs(preferredPlaybackRate - 1.0) < 0.01
        let isSlowSpeed = preferredPlaybackRate < 0.99
        let isFastSpeed = preferredPlaybackRate > 1.01

        if isSlowSpeed {
            setTransportSpeedLabelText(
                formattedPlaybackSpeed(preferredPlaybackRate),
                on: playbackSpeedSlowLabel,
                alignment: .right
            )
            playbackSpeedSlowLabel.alphaValue = 1
        } else {
            clearTransportSpeedLabel(playbackSpeedSlowLabel)
            playbackSpeedSlowLabel.alphaValue = 0
        }

        if isFastSpeed {
            setTransportSpeedLabelText(
                formattedPlaybackSpeed(preferredPlaybackRate),
                on: playbackSpeedFastLabel,
                alignment: .left
            )
            playbackSpeedFastLabel.alphaValue = 1
        } else {
            clearTransportSpeedLabel(playbackSpeedFastLabel)
            playbackSpeedFastLabel.alphaValue = 0
        }

        speedStepDownButton.isEnabled = index > 0
        speedStepUpButton.isEnabled = index < PlaybackSpeedSteps.rates.count - 1

        if isNormalSpeed {
            speedStepDownButton.alphaValue = 1
            speedStepUpButton.alphaValue = 1
        }
    }

    private func configureAudioSettingsTab() {
        audioSettings.trackPopUp.target = self
        audioSettings.trackPopUp.action = #selector(audioTrackPopUpChanged)
        addSettingsSection(to: audioTabView, title: "Track", isFirst: true) { card in
            card.addFinalRow(SettingsRowFactory.valueRow(title: "Audio", control: audioSettings.trackPopUp))
        }

        audioSettings.eqPresetPopUp.target = self
        audioSettings.eqPresetPopUp.action = #selector(audioEQPresetChanged)
        for slider in audioSettings.eqBandSliders {
            slider.target = self
            slider.action = #selector(audioEQBandChanged)
        }
        addSettingsSection(to: audioTabView, title: "Equalizer") { card in
            card.addRow(SettingsRowFactory.valueRow(title: "Preset", control: audioSettings.eqPresetPopUp))
            card.addRow(SettingsRowFactory.fullWidthRow(audioSettings.eqUnavailableLabel))
            card.addFinalRow(SettingsRowFactory.fullWidthRow(audioSettings.eqBandsRow))
        }
        audioSettings.loadBandsFromStore()
        updateAudioEQAvailability()
    }

    private func configureSubtitlesSettingsTab() {
        let s = subtitlesSettings

        s.loadExternalButton.target = self
        s.loadExternalButton.action = #selector(loadExternalSubtitlePressed)
        s.extendedPlaybackButton.target = self
        s.extendedPlaybackButton.action = #selector(extendedPlaybackForSubtitlesPressed)

        let externalRow = NSStackView()
        externalRow.orientation = .horizontal
        externalRow.alignment = .centerY
        externalRow.spacing = 8
        externalRow.addArrangedSubview(s.loadExternalButton)
        externalRow.addArrangedSubview(s.externalFileLabel)

        addSettingsSection(to: subtitlesTabView, title: "Tracks", isFirst: true) { card in
            card.addRow(makeSettingsSubtitleTrackBlock(
                title: "Primary",
                toggle: s.primaryEnabledSwitch,
                popUp: s.primaryTrackPopUp
            ))
            card.addRow(makeSettingsSubtitleTrackBlock(
                title: "Secondary",
                toggle: s.secondaryEnabledSwitch,
                popUp: s.secondaryTrackPopUp
            ))
            card.addRow(SettingsRowFactory.fullWidthRow(externalRow))
            card.addRow(SettingsRowFactory.fullWidthRow(s.companionFilesLabel))
            card.addRow(SettingsRowFactory.fullWidthRow(s.extendedPlaybackButton))
            card.addFinalRow(SettingsRowFactory.fullWidthRow(s.extendedOnlyLabel))
        }

        addSettingsSection(to: subtitlesTabView, title: "Timing") { card in
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Delay",
                slider: s.delaySlider,
                valueLabel: s.delayValueLabel
            ))
        }

        addSettingsSection(to: subtitlesTabView, title: "Placement") { card in
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Position",
                slider: s.positionSlider,
                valueLabel: s.positionValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Scale",
                slider: s.scaleSlider,
                valueLabel: s.scaleValueLabel
            ))
        }

        addSettingsSection(to: subtitlesTabView, title: "Text style") { card in
            card.addRow(SettingsRowFactory.valueRow(title: "Font", control: s.fontFamilyLabel))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Size",
                slider: s.fontSizeSlider,
                valueLabel: s.fontSizeValueLabel
            ))
            card.addRow(SettingsRowFactory.valueRow(title: "Color", control: s.fontColorWell))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Border",
                slider: s.borderWidthSlider,
                valueLabel: s.borderWidthValueLabel
            ))
            card.addRow(SettingsRowFactory.valueRow(title: "Border color", control: s.borderColorWell))
            card.addRow(SettingsRowFactory.toggleRow(title: "Background", control: s.backgroundEnabledCheckbox))
            card.addFinalRow(SettingsRowFactory.valueRow(title: "Background color", control: s.backgroundColorWell))
        }

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .equalCentering
        s.resetAppearanceButton.target = self
        s.resetAppearanceButton.action = #selector(resetSubtitleAppearancePressed)
        footer.addArrangedSubview(s.resetAppearanceButton)
        subtitlesTabView.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: subtitlesTabView.widthAnchor).isActive = true

        s.primaryEnabledSwitch.target = self
        s.primaryEnabledSwitch.action = #selector(primarySubtitlesEnabledChanged)
        s.secondaryEnabledSwitch.target = self
        s.secondaryEnabledSwitch.action = #selector(secondarySubtitlesEnabledChanged)
        s.primaryTrackPopUp.target = self
        s.primaryTrackPopUp.action = #selector(primarySubtitleTrackChanged)
        s.secondaryTrackPopUp.target = self
        s.secondaryTrackPopUp.action = #selector(secondarySubtitleTrackChanged)
        s.delaySlider.target = self
        s.delaySlider.action = #selector(subtitleAppearanceChanged)
        s.positionSlider.target = self
        s.positionSlider.action = #selector(subtitleAppearanceChanged)
        s.scaleSlider.target = self
        s.scaleSlider.action = #selector(subtitleAppearanceChanged)
        s.fontSizeSlider.target = self
        s.fontSizeSlider.action = #selector(subtitleAppearanceChanged)
        s.borderWidthSlider.target = self
        s.borderWidthSlider.action = #selector(subtitleAppearanceChanged)
        s.backgroundEnabledCheckbox.target = self
        s.backgroundEnabledCheckbox.action = #selector(subtitleAppearanceChanged)

        let appearanceHandler: () -> Void = { [weak self] in
            self?.subtitleAppearanceChanged()
        }
        for well in [s.fontColorWell, s.borderColorWell, s.backgroundColorWell] {
            well.interactionDelegate = self
            well.onColorChanged = appearanceHandler
        }

        s.loadAppearanceFromStore()
        updateSubtitleControlsAvailability()
    }

    private func makePlaybackSpeedSectionRow() -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 8
        let title = NSTextField(labelWithString: "Speed")
        title.font = .systemFont(ofSize: 13)
        title.textColor = .labelColor
        playbackSpeedValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        playbackSpeedValueLabel.textColor = .secondaryLabelColor
        playbackSpeedValueLabel.alignment = .right
        header.addArrangedSubview(title)
        header.addArrangedSubview(playbackSpeedValueLabel)

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.distribution = .fill
        controls.spacing = 8
        playbackSpeedSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controls.addArrangedSubview(playbackSpeedStepDownButton)
        controls.addArrangedSubview(playbackSpeedSlider)
        controls.addArrangedSubview(playbackSpeedStepUpButton)

        column.addArrangedSubview(header)
        column.addArrangedSubview(controls)
        controls.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        controls.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        return SettingsRowFactory.fullWidthRow(column)
    }

    private func addSettingsSection(
        to stack: NSStackView,
        title: String,
        isFirst: Bool = false,
        configure: (SettingsSectionCard) -> Void
    ) {
        let block = SettingsSectionBuilder.sectionBlock(title: title, isFirst: isFirst, configure: configure)
        stack.addArrangedSubview(block)
        block.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeSettingsSubtitleTrackBlock(
        title: String,
        toggle: CompactTealToggle,
        popUp: NSPopUpButton
    ) -> NSView {
        toggle.setAccessibilityLabel("\(title) subtitles")
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(SettingsRowFactory.toggleRow(title: title, control: toggle))
        popUp.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(popUp)
        popUp.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        popUp.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        return SettingsRowFactory.fullWidthRow(column)
    }

    private func makeSettingsSubtitleTrackRow(
        enableSwitch: CompactTealToggle,
        title: String,
        popUp: NSPopUpButton
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        enableSwitch.setAccessibilityLabel("\(title) subtitles")

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        popUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popUp.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        enableSwitch.setContentHuggingPriority(.required, for: .horizontal)
        enableSwitch.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(popUp)
        row.addArrangedSubview(enableSwitch)

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            row.topAnchor.constraint(equalTo: wrapper.topAnchor),
            row.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func makeSettingsSliderRow(title: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func makeSettingsColorRow(title: String, well: NSColorWell) -> NSView {
        makeSettingsLabeledRow(title: title, control: well)
    }

    private func fetchMpvSubtitleTracks() async -> [SubtitleTrackInfo] {
        let controller = mpvController
        let delaysSec: [Double] = [0, 0.15, 0.4]
        for delay in delaysSec {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            let tracks = await Task.detached {
                controller.subtitleTracks()
            }.value
            if !tracks.isEmpty { return tracks }
        }
        return await Task.detached { controller.subtitleTracks() }.value
    }

    @MainActor
    private func refreshSubtitleSettings() async {
        guard activeMediaKind == .video else {
            populateSubtitleTrackPopUps(tracks: [], primarySelected: nil, secondarySelected: nil)
            updateSubtitleControlsAvailability()
            return
        }

        var tracks: [SubtitleTrackInfo] = []
        let sourceURL = playbackSourceURL ?? currentMediaURL
        if let sourceURL {
            cachedDiscoveredCompanions = CompanionSubtitleDiscovery.discover(for: sourceURL)
        } else {
            cachedDiscoveredCompanions = []
        }

        if mpvBackendActive, mpvPlaybackStarted {
            tracks = await fetchMpvSubtitleTracks()
            if let sourceURL {
                tracks = tracks.map { CompanionSubtitleDiscovery.enrich($0, mediaURL: sourceURL) }
            }
        } else if let item = nativeSubtitlePlayerItem() {
            do {
                tracks = try await SubtitleTrackCatalog.tracks(from: item.asset)
            } catch {
                tracks = []
            }
        } else if let url = playbackSourceURL ?? currentMediaURL {
            let asset = AVURLAsset(url: url)
            do {
                tracks = try await SubtitleTrackCatalog.tracks(from: asset)
            } catch {
                tracks = []
            }
        }

        cachedSubtitleTracks = tracks
        let uiPrimaryOn = subtitlesSettings.primaryEnabledSwitch.isOn
        let uiSecondaryOn = subtitlesSettings.secondaryEnabledSwitch.isOn
        if tracks.isEmpty {
            primarySubtitlesEnabled = false
            secondarySubtitlesEnabled = false
        } else {
            let enginePrimary = await isPrimarySubtitlesEnabled()
            primarySubtitlesEnabled = enginePrimary || uiPrimaryOn
            secondarySubtitlesEnabled = mpvBackendActive && mpvPlaybackStarted
                ? (await isSecondarySubtitlesEnabled() || uiSecondaryOn)
                : false
        }

        let primarySelected = primarySubtitlesEnabled ? await currentPrimarySubtitleTrack(in: tracks) : nil
        let secondarySelected = secondarySubtitlesEnabled ? await currentSecondarySubtitleTrack(in: tracks) : nil
        populateSubtitleTrackPopUps(
            tracks: tracks,
            primarySelected: primarySelected,
            secondarySelected: secondarySelected
        )
        updateCompanionSubtitlesUI()
        updateSubtitleControlsAvailability()
        applySubtitleAppearanceToActiveMpv()
        await syncSubtitleSelectionFromUI(tracks: tracks)
    }

    /// Active native item for subtitle track catalog / selection (matches what's playing, not the source MKV).
    private func nativeSubtitlePlayerItem() -> AVPlayerItem? {
        if let item = player.currentItem, isCurrentPlaybackItem(item) {
            return item
        }
        if let item = observedItem, item === player.currentItem {
            return item
        }
        if let item = player.currentItem, committedPlayerItemID == ObjectIdentifier(item) {
            return item
        }
        return nil
    }

    @MainActor
    private func syncSubtitleSelectionFromUI(tracks: [SubtitleTrackInfo]) async {
        guard !tracks.isEmpty else {
            if !mpvBackendActive {
                await applyPrimarySubtitleTrack(nil)
            }
            return
        }
        if primarySubtitlesEnabled {
            let popUpIndex = subtitlesSettings.primaryTrackPopUp.indexOfSelectedItem
            let track: SubtitleTrackInfo?
            if popUpIndex > 0, popUpIndex - 1 < tracks.count {
                track = tracks[popUpIndex - 1]
            } else {
                track = tracks.first
            }
            if let track {
                await applyPrimarySubtitleTrack(track)
            }
        } else if !mpvBackendActive {
            await applyPrimarySubtitleTrack(nil)
        }
        if mpvBackendActive, mpvPlaybackStarted {
            if secondarySubtitlesEnabled {
                let popUpIndex = subtitlesSettings.secondaryTrackPopUp.indexOfSelectedItem
                let track: SubtitleTrackInfo?
                if popUpIndex > 0, popUpIndex - 1 < tracks.count {
                    track = tracks[popUpIndex - 1]
                } else if tracks.count > 1 {
                    track = tracks[1]
                } else {
                    track = nil
                }
                await applySecondarySubtitleTrack(track)
            } else {
                await applySecondarySubtitleTrack(nil)
            }
        }
    }

    private func updateCompanionSubtitlesUI() {
        let s = subtitlesSettings
        var infoLines: [String] = []

        if !cachedDiscoveredCompanions.isEmpty {
            infoLines.append("Sidecar files found:")
            infoLines.append(contentsOf: cachedDiscoveredCompanions.map(\.menuTitle))
        }

        if cachedSubtitleTracks.isEmpty,
           let sourceURL = playbackSourceURL ?? currentMediaURL {
            let embedded = FFmpegVideoFallback.probeEmbeddedSubtitleStreams(for: sourceURL)
            if !embedded.isEmpty {
                infoLines.append("Embedded in file:")
                infoLines.append(contentsOf: embedded)
                if isPlayingFromCompatibilityCopy(for: sourceURL) {
                    let hasTextSubs = embedded.contains { line in
                        let lower = line.lowercased()
                        return ["subrip", "srt", "ass", "ssa", "mov_text", "webvtt"].contains { lower.contains($0) }
                    }
                    if hasTextSubs {
                        infoLines.append("Re-open the file if subtitles don’t appear (remux cache updated).")
                    } else {
                        infoLines.append("Bitmap (PGS) subtitles need extended playback (DirectMpv) or a sidecar .srt file.")
                    }
                }
            }
        }

        if infoLines.isEmpty {
            s.companionFilesLabel.isHidden = true
            s.companionFilesLabel.stringValue = ""
        } else {
            s.companionFilesLabel.isHidden = false
            s.companionFilesLabel.stringValue = infoLines.joined(separator: "\n")
        }

        let extendedActive = mpvBackendActive && mpvPlaybackStarted
        let mpvAvailable = MpvPlaybackController.isAvailable()
        let onRemux = isPlayingFromCompatibilityCopy(for: playbackSourceURL ?? currentMediaURL)
        let showExtendedButton = !extendedActive
            && mpvAvailable
            && (!cachedDiscoveredCompanions.isEmpty || onRemux)
        s.extendedPlaybackButton.isHidden = !showExtendedButton
        if onRemux, cachedDiscoveredCompanions.isEmpty {
            s.extendedPlaybackButton.title = "Retry extended playback for subtitles"
        } else {
            s.extendedPlaybackButton.title = "Use extended playback for subtitles"
        }
    }

    @objc private func extendedPlaybackForSubtitlesPressed() {
        guard MpvPlaybackController.isAvailable() else { return }
        guard let source = playbackSourceURL ?? currentMediaURL else { return }

        let resumeTime: CMTime
        if mpvBackendActive, let session = activeSession {
            resumeTime = CMTime(seconds: session.currentTimeSec, preferredTimescale: 600)
        } else {
            resumeTime = player.currentTime()
        }
        let wasPlaying: Bool
        if mpvBackendActive, let session = activeSession {
            wasPlaying = session.isPlaying
        } else {
            wasPlaying = player.rate > 0.01
        }

        pendingResumePlayingAfterLoad = wasPlaying
        primarySubtitlesEnabled = false
        secondarySubtitlesEnabled = false
        performLoadVideo(
            url: source,
            replaceCurrent: false,
            startAt: resumeTime,
            forceReload: true,
            forceDirectMpv: true
        )
    }

    @MainActor
    private func isPrimarySubtitlesEnabled() async -> Bool {
        if mpvBackendActive, mpvPlaybackStarted {
            return await Task.detached { [mpvController] in
                !mpvController.isSubtitleTrackDisabled(secondary: false)
            }.value
        }
        if let item = nativeSubtitlePlayerItem() {
            return !(await NativeSubtitleSelection.isSubtitlesDisabled(for: item))
        }
        return primarySubtitlesEnabled
    }

    @MainActor
    private func isSecondarySubtitlesEnabled() async -> Bool {
        guard mpvBackendActive, mpvPlaybackStarted else { return false }
        return await Task.detached { [mpvController] in
            !mpvController.isSubtitleTrackDisabled(secondary: true)
        }.value
    }

    @MainActor
    private func currentPrimarySubtitleTrack(in tracks: [SubtitleTrackInfo]) async -> SubtitleTrackInfo? {
        guard primarySubtitlesEnabled, !tracks.isEmpty else { return nil }
        if mpvBackendActive, mpvPlaybackStarted {
            let selectedID = await Task.detached { [mpvController] in
                mpvController.selectedSubtitleTrackID(secondary: false)
            }.value
            if let selectedID, let match = tracks.first(where: {
                if case .mpv(let id) = $0.backendID { return id == selectedID }
                if case .externalMpv(let id, _) = $0.backendID { return id == selectedID }
                return false
            }) {
                return match
            }
            return tracks.first
        }
        if let item = nativeSubtitlePlayerItem(),
           let index = await NativeSubtitleSelection.selectedOptionIndex(for: item) {
            if let match = tracks.first(where: {
                if case .avFoundation(let optionIndex) = $0.backendID { return optionIndex == index }
                return false
            }) {
                return match
            }
        }
        return tracks.first
    }

    @MainActor
    private func currentSecondarySubtitleTrack(in tracks: [SubtitleTrackInfo]) async -> SubtitleTrackInfo? {
        guard secondarySubtitlesEnabled, !tracks.isEmpty else { return nil }
        guard mpvBackendActive, mpvPlaybackStarted else { return nil }
        let selectedID = await Task.detached { [mpvController] in
            mpvController.selectedSubtitleTrackID(secondary: true)
        }.value
        if let selectedID {
            return tracks.first(where: {
                if case .mpv(let id) = $0.backendID { return id == selectedID }
                if case .externalMpv(let id, _) = $0.backendID { return id == selectedID }
                return false
            })
        }
        if tracks.count > 1 { return tracks[1] }
        return nil
    }

    private func populateSubtitleTrackPopUps(
        tracks: [SubtitleTrackInfo],
        primarySelected: SubtitleTrackInfo?,
        secondarySelected: SubtitleTrackInfo?
    ) {
        suppressSubtitlePopUpAction = true
        let s = subtitlesSettings
        for popUp in [s.primaryTrackPopUp, s.secondaryTrackPopUp] {
            popUp.removeAllItems()
            popUp.addItem(withTitle: SubtitleTrackPickerOption.noneMenuTitle)
            for track in tracks {
                popUp.addItem(withTitle: track.menuTitle)
            }
        }

        if tracks.isEmpty || !primarySubtitlesEnabled {
            s.primaryTrackPopUp.selectItem(at: 0)
        } else if let primarySelected, let index = tracks.firstIndex(of: primarySelected) {
            s.primaryTrackPopUp.selectItem(at: index + 1)
        } else {
            s.primaryTrackPopUp.selectItem(at: min(1, tracks.count))
        }

        if tracks.isEmpty || !secondarySubtitlesEnabled {
            s.secondaryTrackPopUp.selectItem(at: 0)
        } else if let secondarySelected, let index = tracks.firstIndex(of: secondarySelected) {
            s.secondaryTrackPopUp.selectItem(at: index + 1)
        } else {
            s.secondaryTrackPopUp.selectItem(at: tracks.count > 1 ? 2 : 0)
        }

        s.primaryEnabledSwitch.applySwitchState(primarySubtitlesEnabled)
        s.secondaryEnabledSwitch.applySwitchState(secondarySubtitlesEnabled)
        s.primaryTrackPopUp.isEnabled = primarySubtitlesEnabled && !tracks.isEmpty
        s.secondaryTrackPopUp.isEnabled = secondarySubtitlesEnabled && !tracks.isEmpty

        if let path = lastExternalSubtitlePath, !path.isEmpty {
            s.externalFileLabel.stringValue = (path as NSString).lastPathComponent
        } else {
            s.externalFileLabel.stringValue = "No external file"
        }
        suppressSubtitlePopUpAction = false
    }

    private func updateSubtitleControlsAvailability() {
        let extended = mpvBackendActive && mpvPlaybackStarted
        let nativeItem = nativeSubtitlePlayerItem()
        let nativeActive = activeMediaKind == .video && !mpvBackendActive && nativeItem != nil
        let canEditAppearance = activeMediaKind == .video && (extended || nativeActive)

        subtitlesSettings.setAppearanceControlsEnabled(canEditAppearance, delayEnabled: extended)
        subtitlesSettings.setMpvExclusiveControlsEnabled(extended)
        subtitlesSettings.updateExtendedHint(extendedActive: extended, nativePlayback: nativeActive)

        subtitlesSettings.primaryEnabledSwitch.isEnabled = !cachedSubtitleTracks.isEmpty
        subtitlesSettings.primaryTrackPopUp.isEnabled = primarySubtitlesEnabled && !cachedSubtitleTracks.isEmpty
        subtitlesSettings.secondaryEnabledSwitch.isEnabled = extended && !cachedSubtitleTracks.isEmpty
        subtitlesSettings.secondaryTrackPopUp.isEnabled = extended && secondarySubtitlesEnabled && !cachedSubtitleTracks.isEmpty
        updateCompanionSubtitlesUI()
        updatePlaybackSubtitleToggle()
    }

    func applySubtitleAppearanceToActiveMpv() {
        subtitlesSettings.saveAppearanceToStore()
        if mpvBackendActive, mpvPlaybackStarted {
            mpvController.applySubtitleAppearance(from: SettingsStore.shared)
        } else {
            syncNativeSubtitleOverlay()
        }
    }

    @MainActor
    private func syncNativeSubtitleOverlay() {
        guard !mpvBackendActive else { return }
        let store = SettingsStore.shared
        guard primarySubtitlesEnabled, let item = nativeSubtitlePlayerItem() else {
            nativeSubtitleOverlay.sync(item: nil, enabled: false, store: store)
            return
        }
        nativeSubtitleOverlay.sync(item: item, enabled: true, store: store)
    }

    private func updatePlaybackSubtitleToggle() {
        let show = activeMediaKind == .video
        playbackSubtitleToggle.isHidden = !show
        playbackSubtitleToggle.isEnabled = show && !cachedSubtitleTracks.isEmpty
        playbackSubtitleToggle.subtitlesActive = primarySubtitlesEnabled
        playbackSubtitleToggle.contentTintColor = MusicStylePlaybackBar.accessoryIconTintColor
        let state = primarySubtitlesEnabled ? "on" : "off"
        playbackSubtitleToggle.setAccessibilityLabel("Subtitles \(state)")
        playbackSubtitleToggle.toolTip = primarySubtitlesEnabled ? "Turn subtitles off" : "Turn subtitles on"
    }

    @objc private func playbackSubtitleTogglePressed() {
        guard activeMediaKind == .video, !cachedSubtitleTracks.isEmpty else { return }
        let enable = !primarySubtitlesEnabled
        subtitlesSettings.primaryEnabledSwitch.applySwitchState(enable)
        primarySubtitlesEnabledChanged()
    }

    @MainActor
    private func applyPrimarySubtitleTrack(_ track: SubtitleTrackInfo?) async {
        if mpvBackendActive, mpvPlaybackStarted {
            if let track, case .mpv(let id) = track.backendID {
                _ = await Task.detached { [mpvController] in
                    mpvController.setSubtitleTrackID(id, secondary: false)
                }.value
            } else if let track, case .externalMpv(let id, _) = track.backendID {
                _ = await Task.detached { [mpvController] in
                    mpvController.setSubtitleTrackID(id, secondary: false)
                }.value
            } else {
                _ = await Task.detached { [mpvController] in
                    mpvController.disableSubtitleTrack(secondary: false)
                }.value
            }
            return
        }
        guard let item = nativeSubtitlePlayerItem() else { return }
        if item.status != .readyToPlay {
            for _ in 0..<40 where item.status != .readyToPlay {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        guard item.status == .readyToPlay else { return }
        if let track {
            let applied = await NativeSubtitleSelection.select(track: track, on: item)
            if applied {
                nudgeNativeSubtitleDisplay()
            }
        } else {
            _ = await NativeSubtitleSelection.disableSubtitles(on: item)
        }
        syncNativeSubtitleOverlay()
    }

    private func nudgeNativeSubtitleDisplay() {
        let time = player.currentTime()
        guard time.isValid, !time.isIndefinite else { return }
        player.seek(
            to: time,
            toleranceBefore: CMTime(value: 1, timescale: 600),
            toleranceAfter: CMTime(value: 1, timescale: 600)
        )
    }

    @MainActor
    private func applySecondarySubtitleTrack(_ track: SubtitleTrackInfo?) async {
        guard mpvBackendActive, mpvPlaybackStarted else { return }
        if let track, case .mpv(let id) = track.backendID {
            _ = await Task.detached { [mpvController] in
                mpvController.setSubtitleTrackID(id, secondary: true)
            }.value
        } else if let track, case .externalMpv(let id, _) = track.backendID {
            _ = await Task.detached { [mpvController] in
                mpvController.setSubtitleTrackID(id, secondary: true)
            }.value
        } else {
            _ = await Task.detached { [mpvController] in
                mpvController.disableSubtitleTrack(secondary: true)
            }.value
        }
    }

    @objc private func primarySubtitlesEnabledChanged() {
        let enable = subtitlesSettings.primaryEnabledSwitch.isOn
        primarySubtitlesEnabled = enable
        if enable,
           !(mpvBackendActive && mpvPlaybackStarted),
           cachedSubtitleTracks.isEmpty,
           !cachedDiscoveredCompanions.isEmpty {
            primarySubtitlesEnabled = false
            subtitlesSettings.primaryEnabledSwitch.applySwitchState(false)
            let alert = NSAlert()
            alert.messageText = "Sidecar subtitles need extended playback"
            alert.informativeText = "This file’s subtitles are in separate files next to the video. Use extended playback to load them."
            alert.runModal()
            updateSubtitleControlsAvailability()
            return
        }
        updateSubtitleControlsAvailability()
        Task { @MainActor in
            await applyPrimarySubtitleFromUI(autoSelectDefault: enable, enabled: enable)
        }
    }

    @objc private func secondarySubtitlesEnabledChanged() {
        let enable = subtitlesSettings.secondaryEnabledSwitch.isOn
        secondarySubtitlesEnabled = enable
        updateSubtitleControlsAvailability()
        Task { @MainActor in
            await applySecondarySubtitleFromUI(autoSelectDefault: enable, enabled: enable)
        }
    }

    @objc private func primarySubtitleTrackChanged() {
        guard !suppressSubtitlePopUpAction else { return }
        Task { await applyPrimarySubtitleFromUI() }
    }

    @objc private func secondarySubtitleTrackChanged() {
        guard !suppressSubtitlePopUpAction else { return }
        Task { await applySecondarySubtitleFromUI() }
    }

    @MainActor
    private func applyPrimarySubtitleFromUI(autoSelectDefault: Bool = false, enabled: Bool? = nil) async {
        let isEnabled = enabled ?? primarySubtitlesEnabled
        guard isEnabled else {
            await applyPrimarySubtitleTrack(nil)
            updateSubtitleControlsAvailability()
            syncNativeSubtitleOverlay()
            return
        }

        var index = subtitlesSettings.primaryTrackPopUp.indexOfSelectedItem
        if index <= 0 {
            if autoSelectDefault, !cachedSubtitleTracks.isEmpty {
                index = 1
                suppressSubtitlePopUpAction = true
                subtitlesSettings.primaryTrackPopUp.selectItem(at: index)
                suppressSubtitlePopUpAction = false
            } else {
                await applyPrimarySubtitleTrack(nil)
                updateSubtitleControlsAvailability()
                return
            }
        }

        guard index - 1 < cachedSubtitleTracks.count else { return }
        subtitlesSettings.primaryEnabledSwitch.applySwitchState(true)
        await applyPrimarySubtitleTrack(cachedSubtitleTracks[index - 1])
        updateSubtitleControlsAvailability()
    }

    @MainActor
    private func applySecondarySubtitleFromUI(autoSelectDefault: Bool = false, enabled: Bool? = nil) async {
        let isEnabled = enabled ?? secondarySubtitlesEnabled
        guard isEnabled else {
            await applySecondarySubtitleTrack(nil)
            updateSubtitleControlsAvailability()
            return
        }

        var index = subtitlesSettings.secondaryTrackPopUp.indexOfSelectedItem
        if index <= 0 {
            if autoSelectDefault, cachedSubtitleTracks.count > 1 {
                index = 1
                suppressSubtitlePopUpAction = true
                subtitlesSettings.secondaryTrackPopUp.selectItem(at: index)
                suppressSubtitlePopUpAction = false
            } else {
                await applySecondarySubtitleTrack(nil)
                updateSubtitleControlsAvailability()
                return
            }
        }

        guard index - 1 < cachedSubtitleTracks.count else { return }
        subtitlesSettings.secondaryEnabledSwitch.applySwitchState(true)
        await applySecondarySubtitleTrack(cachedSubtitleTracks[index - 1])
        updateSubtitleControlsAvailability()
    }

    @objc private func loadExternalSubtitlePressed() {
        guard mpvBackendActive, mpvPlaybackStarted else {
            let alert = NSAlert()
            alert.messageText = "External subtitles"
            alert.informativeText = "Load external subtitle files when playing with extended playback (MKV/direct)."
            alert.runModal()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .mpeg4Movie, .quickTimeMovie]
        panel.allowsOtherFileTypes = true
        panel.title = "Open subtitle file"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        lastExternalSubtitlePath = url.path
        subtitlesSettings.externalFileLabel.stringValue = url.lastPathComponent
        _ = mpvController.addExternalSubtitle(url: url, select: true)
        primarySubtitlesEnabled = true
        subtitlesSettings.primaryEnabledSwitch.applySwitchState(true)
        Task { await refreshSubtitleSettings() }
    }

    @objc private func resetSubtitleAppearancePressed() {
        suppressSubtitleAppearanceCallback = true
        SettingsStore.shared.resetSubtitleAppearanceToDefaults()
        subtitlesSettings.applyDefaultsToControls()
        subtitlesSettings.saveAppearanceToStore()
        subtitlesSettings.updateValueLabels()
        suppressSubtitleAppearanceCallback = false

        applySubtitleAppearanceToActiveMpv()
        Task { @MainActor in
            await self.refreshPrimarySubtitleAfterAppearanceReset()
        }
    }

    /// Re-select the active track so native subs recover after appearance changes.
    @MainActor
    private func refreshPrimarySubtitleAfterAppearanceReset() async {
        guard !mpvBackendActive, primarySubtitlesEnabled, !cachedSubtitleTracks.isEmpty else { return }
        let popUpIndex = subtitlesSettings.primaryTrackPopUp.indexOfSelectedItem
        let trackIndex = popUpIndex > 0 ? popUpIndex - 1 : 0
        guard trackIndex < cachedSubtitleTracks.count else { return }
        await applyPrimarySubtitleTrack(cachedSubtitleTracks[trackIndex])
    }

    @objc private func subtitleAppearanceChanged() {
        guard !suppressSubtitleAppearanceCallback else { return }
        subtitlesSettings.updateValueLabels()
        subtitlesSettings.saveAppearanceToStore()
        applySubtitleAppearanceToActiveMpv()
    }

    @MainActor
    private func refreshAudioTrackPicker() async {
        guard activeMediaKind == .video else {
            populateAudioTrackPopUp(tracks: [], selected: nil)
            updateAudioEQAvailability()
            return
        }

        var tracks: [AudioTrackInfo] = []
        if mpvBackendActive, mpvPlaybackStarted {
            tracks = await Task.detached { [mpvController] in
                mpvController.audioTracks()
            }.value
        } else if let item = player.currentItem, committedPlayerItemID != nil {
            do {
                tracks = try await AudioTrackCatalog.tracks(from: item.asset)
            } catch {
                tracks = []
            }
        } else if let url = playbackSourceURL ?? currentMediaURL {
            let asset = AVURLAsset(url: url)
            do {
                tracks = try await AudioTrackCatalog.tracks(from: asset)
            } catch {
                tracks = []
            }
        }

        cachedAudioTracks = tracks
        if tracks.isEmpty {
            audioOutputEnabled = false
        } else {
            audioOutputEnabled = await isEngineAudioOutputEnabled()
        }
        let selected = audioOutputEnabled ? await currentSelectedAudioTrack(in: tracks) : nil
        populateAudioTrackPopUp(tracks: tracks, selected: selected)
        updatePlaybackVolumeChromeVisibility()
        updateAudioEQAvailability()
        await applyPendingAudioTrackSelectionIfNeeded()
    }

    @MainActor
    private func isEngineAudioOutputEnabled() async -> Bool {
        if mpvBackendActive, mpvPlaybackStarted {
            return await Task.detached { [mpvController] in
                !mpvController.isAudioTrackDisabled()
            }.value
        }
        if let item = player.currentItem, committedPlayerItemID != nil {
            return !(await NativeAudioTrackSelection.isAudioDisabled(for: item))
        }
        return audioOutputEnabled
    }

    @MainActor
    private func currentSelectedAudioTrack(in tracks: [AudioTrackInfo]) async -> AudioTrackInfo? {
        guard !tracks.isEmpty, audioOutputEnabled else { return nil }
        if mpvBackendActive, mpvPlaybackStarted {
            let selectedID = await Task.detached { [mpvController] in
                mpvController.selectedAudioTrackID()
            }.value
            if let selectedID, let match = tracks.first(where: {
                if case .mpv(let id) = $0.backendID { return id == selectedID }
                return false
            }) {
                return match
            }
            return tracks.first
        }
        if let item = player.currentItem, let index = await NativeAudioTrackSelection.selectedOptionIndex(for: item),
           index >= 0, index < tracks.count {
            return tracks[index]
        }
        return tracks.first
    }

    private func populateAudioTrackPopUp(tracks: [AudioTrackInfo], selected: AudioTrackInfo?) {
        suppressAudioTrackPopUpAction = true
        audioSettings.trackPopUp.removeAllItems()
        audioSettings.trackPopUp.addItem(withTitle: AudioTrackPickerOption.noneMenuTitle)
        for track in tracks {
            audioSettings.trackPopUp.addItem(withTitle: track.menuTitle)
        }

        if tracks.isEmpty || !audioOutputEnabled {
            audioSettings.trackPopUp.selectItem(at: 0)
        } else if let selected, let index = tracks.firstIndex(of: selected) {
            audioSettings.trackPopUp.selectItem(at: index + 1)
        } else {
            audioSettings.trackPopUp.selectItem(at: 1)
        }
        suppressAudioTrackPopUpAction = false
    }

    @MainActor
    private func applyPendingAudioTrackSelectionIfNeeded() async {
        guard let pending = pendingAudioTrackBackendID else { return }
        pendingAudioTrackBackendID = nil
        guard let track = cachedAudioTracks.first(where: { $0.backendID == pending }) else { return }
        audioOutputEnabled = true
        _ = await performAudioTrackHotSwap(track)
        restorePlaybackVolumeAfterAudioEnabled()
        updatePlaybackVolumeChromeVisibility()
        await refreshAudioTrackPicker()
    }

    @objc func audioTrackPopUpChanged(_ sender: NSPopUpButton) {
        guard !suppressAudioTrackPopUpAction else { return }
        let index = sender.indexOfSelectedItem
        guard index >= 0 else { return }
        if index == 0 {
            Task { await setAudioOutputEnabled(false) }
            return
        }
        let trackIndex = index - 1
        guard trackIndex < cachedAudioTracks.count else { return }
        let track = cachedAudioTracks[trackIndex]
        Task { await setAudioOutputEnabled(true, track: track) }
    }

    @MainActor
    private func setAudioOutputEnabled(_ enabled: Bool, track: AudioTrackInfo? = nil) async {
        audioOutputEnabled = enabled
        if enabled {
            if let track {
                if await performAudioTrackHotSwap(track) {
                    restorePlaybackVolumeAfterAudioEnabled()
                } else if let url = playbackSourceURL ?? currentMediaURL {
                    await reloadForAudioTrackChange(track: track, url: url)
                    return
                } else {
                    restorePlaybackVolumeAfterAudioEnabled()
                }
            } else {
                restorePlaybackVolumeAfterAudioEnabled()
            }
        } else {
            _ = await applyAudioOutputDisabled()
        }
        updatePlaybackVolumeChromeVisibility()
        let selectedTrack: AudioTrackInfo?
        if enabled {
            if let track {
                selectedTrack = track
            } else {
                selectedTrack = await currentSelectedAudioTrack(in: cachedAudioTracks)
            }
        } else {
            selectedTrack = nil
        }
        populateAudioTrackPopUp(tracks: cachedAudioTracks, selected: selectedTrack)
    }

    @MainActor
    private func reloadForAudioTrackChange(track: AudioTrackInfo, url: URL) async {
        let resumeSec = activeSession?.currentTimeSec ?? CMTimeGetSeconds(player.currentTime())
        let wasPlaying = mpvBackendActive
            ? (activeSession?.isPlaying == true)
            : (player.rate > 0)
        pendingAudioTrackBackendID = track.backendID
        pendingResumePlayingAfterLoad = wasPlaying
        pendingStartTimeAfterLoad = CMTime(
            seconds: resumeSec.isFinite && resumeSec >= 0 ? resumeSec : 0,
            preferredTimescale: 600
        )
        performLoadVideo(url: url, replaceCurrent: false, startAt: pendingStartTimeAfterLoad, forceReload: true)
    }

    @MainActor
    private func applyAudioOutputDisabled() async -> Bool {
        if mpvBackendActive, mpvPlaybackStarted {
            return await Task.detached { [mpvController] in
                mpvController.disableAudioTrack()
            }.value
        }
        if let item = player.currentItem, item.status == .readyToPlay {
            _ = await NativeAudioTrackSelection.disableAudio(on: item)
            player.isMuted = true
            player.volume = 0
            return true
        }
        player.isMuted = true
        player.volume = 0
        return false
    }

    private func restorePlaybackVolumeAfterAudioEnabled() {
        volumeSlider.doubleValue = Double(desiredPlaybackVolume)
        applyEffectivePlaybackVolume()
        updateVolumeMuteButtonIcon()
    }

    private func updatePlaybackVolumeChromeVisibility() {
        let showVolume = activeMediaKind == .video && audioOutputEnabled
        volumeCluster.isHidden = !showVolume
        playbackCenterToVolumeConstraint?.isActive = showVolume
        playbackCenterToEdgeConstraint?.isActive = !showVolume
        if showVolume, playbackTopRowLayoutConfigured {
            let tier = currentControlTier
            volumeSliderWidthConstraint?.constant = volumeSliderWidth(for: tier)
        }
        if showVolume {
            updateVolumeMuteButtonIcon()
        }
    }

    private func effectivePlaybackVolume() -> Float {
        isUserVolumeMuted ? 0 : desiredPlaybackVolume
    }

    func applyEffectivePlaybackVolume() {
        guard audioOutputEnabled, !isMutedForSwitch else { return }
        let volume = effectivePlaybackVolume()
        if mpvBackendActive {
            activeSession?.setVolume(volume)
        } else {
            player.isMuted = volume < 0.01
            player.volume = volume
        }
    }

    private func volumeSpeakerSymbolName() -> String {
        if isUserVolumeMuted {
            return "speaker.slash.fill"
        }
        if desiredPlaybackVolume < 0.05 {
            return "speaker.fill"
        }
        if desiredPlaybackVolume < 0.34 {
            return "speaker.wave.1.fill"
        }
        if desiredPlaybackVolume < 0.67 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    func updateVolumeMuteButtonIcon() {
        let symbol = volumeSpeakerSymbolName()
        let label = isUserVolumeMuted ? "Unmute" : "Mute"
        styleIconButton(volumeMuteButton, symbol: symbol, label: label, pointSize: 13)
    }

    @objc func volumeMuteButtonPressed() {
        guard audioOutputEnabled, !isMutedForSwitch else { return }
        if isUserVolumeMuted {
            isUserVolumeMuted = false
            desiredPlaybackVolume = max(0.05, volumeLevelBeforeUserMute)
            volumeSlider.doubleValue = Double(desiredPlaybackVolume)
        } else {
            volumeLevelBeforeUserMute = max(desiredPlaybackVolume, 0.05)
            isUserVolumeMuted = true
        }
        applyEffectivePlaybackVolume()
        updateVolumeMuteButtonIcon()
    }

    @MainActor
    private func performAudioTrackHotSwap(_ track: AudioTrackInfo) async -> Bool {
        if mpvBackendActive, mpvPlaybackStarted, case .mpv(let trackID) = track.backendID {
            return await Task.detached { [mpvController] in
                mpvController.setAudioTrackID(trackID)
            }.value
        }
        if let item = player.currentItem, item.status == .readyToPlay {
            return await NativeAudioTrackSelection.select(track: track, on: item)
        }
        return false
    }

    private func updateAudioEQAvailability() {
        let available = mpvBackendActive && mpvPlaybackStarted
        audioSettings.setEQControlsEnabled(available)
    }

    func applyPlaybackEQToActiveMpv() {
        guard mpvBackendActive, mpvPlaybackStarted else { return }
        let bands = SettingsStore.shared.playbackEQBands
        mpvController.applyPlaybackEQ(gains: bands)
    }

    @objc private func audioEQPresetChanged() {
        guard let raw = audioSettings.eqPresetPopUp.selectedItem?.representedObject as? String,
              let preset = PlaybackEQPreset(rawValue: raw) else { return }
        SettingsStore.shared.playbackEQPreset = preset
        if preset != .manual {
            SettingsStore.shared.playbackEQBands = preset.bandGains
            audioSettings.loadBandsFromStore()
        }
        applyPlaybackEQToActiveMpv()
    }

    @objc private func audioEQBandChanged() {
        SettingsStore.shared.playbackEQPreset = .manual
        if let item = audioSettings.eqPresetPopUp.itemArray.first(where: {
            ($0.representedObject as? String) == PlaybackEQPreset.manual.rawValue
        }) {
            audioSettings.eqPresetPopUp.select(item)
        }
        SettingsStore.shared.playbackEQBands = audioSettings.bandsFromSliders()
        applyPlaybackEQToActiveMpv()
    }

    private func makeSettingsSectionHeader(_ title: String, isFirst: Bool = false) -> NSView {
        let field = NSTextField(labelWithString: title.uppercased())
        field.font = .systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .tertiaryLabelColor

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        if !isFirst {
            let gap = NSView()
            gap.translatesAutoresizingMaskIntoConstraints = false
            gap.heightAnchor.constraint(equalToConstant: settingsSectionExtraGap).isActive = true
            container.addArrangedSubview(gap)
        }
        container.addArrangedSubview(field)
        return container
    }

    private func configureSettingsSegmentedControl(_ control: NSSegmentedControl, action: Selector) {
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.target = self
        control.action = action
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        LaughTheme.installTealSegmentedCell(on: control)
    }

    private func makeSettingsCheckboxRow(title: String, checkbox: NSButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        checkbox.title = ""
        checkbox.attributedTitle = NSAttributedString(string: "")
        checkbox.setAccessibilityLabel(title)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(checkbox)
        row.addArrangedSubview(label)
        return row
    }

    private func makeSettingsSegmentedRow(title: String, control: NSSegmentedControl) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private func formattedAspectRatioName(_ ratio: CGFloat) -> String {
        let presets: [(String, CGFloat)] = [
            ("16:9", 16.0 / 9.0),
            ("4:3", 4.0 / 3.0),
            ("21:9", 21.0 / 9.0),
            ("1:1", 1.0)
        ]
        for preset in presets where abs(ratio - preset.1) < 0.04 {
            return preset.0
        }
        return String(format: "%.2f:1", ratio)
    }

    func refreshWindowAspectFromSettings() {
        applyWindowAspectFromSettings()
        syncVideoSettingsControlsFromStore()
    }

    func applyWindowAspectFromSettings() {
        delegate?.playerViewController(self, didRequestWindowAspectRatio: resolvedWindowAspectRatio())
    }

    /// Aspect ratio to enforce on the main window, or nil when the library/empty UI should resize freely.
    func resolvedWindowAspectRatio() -> CGFloat? {
        guard activeMediaKind == .video || activeMediaKind == .image else { return nil }

        let store = SettingsStore.shared
        switch store.windowAspectPreset {
        case .auto:
            guard store.lockAspectRatioEnabled else { return nil }
            guard let mediaRatio = currentMediaAspectRatio(), mediaRatio > 0 else { return nil }
            return mediaRatio
        case .widescreen, .standard, .ultrawide, .square:
            return store.windowAspectPreset.aspectRatio
        }
    }

    func updateLockAspectControlAvailability() {
        let isAuto = SettingsStore.shared.windowAspectPreset == .auto
        lockAspectCheckbox.isEnabled = isAuto
        lockAspectCheckbox.alphaValue = isAuto ? 1 : 0.5
        if !isAuto {
            lockAspectCheckbox.toolTip = "Available when Aspect is set to Auto."
        } else {
            lockAspectCheckbox.toolTip = "Lock the window to the video's detected aspect ratio."
        }
    }

    private func makeSettingsLabeledRow(title: String, control: NSControl) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    func applyVideoFitMode(_ mode: VideoFitMode) {
        playerSurfaceView.videoGravity = mode == .fill ? .resizeAspectFill : .resizeAspect
    }

    private func startPlaybackAtPreferredRate() {
        if mpvBackendActive {
            activeSession?.setRate(preferredPlaybackRate)
            activeSession?.play()
            return
        }
        player.play()
        if preferredPlaybackRate != 1.0 {
            player.rate = preferredPlaybackRate
        }
    }

    private func installPlayToEndObserver() {
        guard playToEndObserver == nil else { return }
        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePlaybackEnded(notification)
        }
    }

    private func handlePlaybackEnded(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem, item === player.currentItem else { return }

        if extendProgressivePlaybackIfNeeded(force: true) {
            return
        }

        if !queue.isEmpty {
            playNextInQueue()
            return
        }

        guard SettingsStore.shared.loopPlaybackEnabled else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.startPlaybackAtPreferredRate()
            self?.updatePlayPauseButtonIcon()
        }
    }

    @objc private func videoFitChanged() {
        let mode: VideoFitMode = videoFitModeControl.selectedSegment == 1 ? .fill : .fit
        SettingsStore.shared.videoFitMode = mode
        applyVideoFitMode(mode)
        videoFitModeControl.needsDisplay = true
    }

    @objc private func windowAspectChanged() {
        let index = windowAspectControl.selectedSegment
        let presets = WindowAspectPreset.selectablePresets
        guard index >= 0, index < presets.count else { return }
        SettingsStore.shared.windowAspectPreset = presets[index]
        updateLockAspectControlAvailability()
        applyWindowAspectFromSettings()
        windowAspectControl.needsDisplay = true
    }

    @objc private func playbackSpeedChanged() {
        let index = max(0, min(Int(playbackSpeedSlider.integerValue), PlaybackSpeedSteps.rates.count - 1))
        applyPlaybackSpeed(PlaybackSpeedSteps.rates[index])
    }

    @objc private func playbackSpeedStepDown() {
        let index = PlaybackSpeedSteps.index(for: preferredPlaybackRate)
        guard index > 0 else { return }
        applyPlaybackSpeed(PlaybackSpeedSteps.rates[index - 1])
    }

    @objc private func playbackSpeedStepUp() {
        let index = PlaybackSpeedSteps.index(for: preferredPlaybackRate)
        guard index < PlaybackSpeedSteps.rates.count - 1 else { return }
        applyPlaybackSpeed(PlaybackSpeedSteps.rates[index + 1])
    }

    @objc func playbackSourceChanged() {
        guard !suppressPlaybackSourceAction else { return }
        guard playbackSourcePopUp.isEnabled else { return }
        guard let source = playbackSourceURL ?? currentMediaURL else { return }

        let resumeTime: CMTime
        if mpvBackendActive, let session = activeSession {
            resumeTime = CMTime(seconds: session.currentTimeSec, preferredTimescale: 600)
        } else {
            resumeTime = player.currentTime()
        }
        let wantsCompatibility = playbackSourcePopUp.indexOfSelectedItem == 1

        if wantsCompatibility {
            guard let cached = FFmpegVideoFallback.cachedPlayableURL(for: source) else { return }
            if activePlaybackFileURL?.standardizedFileURL == cached.standardizedFileURL { return }
            pendingStartTimeAfterLoad = resumeTime
            videoLoadGeneration += 1
            resolveAndAttach(playableURL: cached, sourceURL: source, generation: videoLoadGeneration)
            return
        }

        if activePlaybackFileURL?.standardizedFileURL == source.standardizedFileURL { return }
        loadVideo(url: source, replaceCurrent: false, startAt: resumeTime)
    }

    @objc private func lockAspectChanged() {
        let enabled = lockAspectCheckbox.state == .on
        SettingsStore.shared.lockAspectRatioEnabled = enabled
        applyWindowAspectFromSettings()
    }

    @objc private func loopPlaybackChanged() {
        SettingsStore.shared.loopPlaybackEnabled = loopPlaybackCheckbox.state == .on
    }

    private func ensureSettingsTabRowsAboveContent() {
        rightSettingsSheet.addSubview(videoSettingsTabsRow, positioned: .above, relativeTo: settingsScrollView)
        rightSettingsSheet.addSubview(imageSettingsTabsRow, positioned: .above, relativeTo: settingsScrollView)
    }

    func showSettingsSheet() {
        guard activeMediaKind != .empty else { return }
        guard playbackLibraryOverlay == .closed else { return }
        guard rightSettingsSheet.isHidden else { return }
        rightSettingsSheet.isHidden = false
        refreshImmersiveChromePinnedState()
        ensureSettingsTabRowsAboveContent()
        updateSettingsTabVisibility()
        applySettingsPanelAccentChrome()
        syncVideoSettingsControlsFromStore()
        updateVideoInfoLabels()
        raiseSettingsSheetAbovePlaybackChrome()
        installOutsideClickMonitor()
        Task { await refreshSubtitleSettings() }
    }

    func currentMediaAspectRatio() -> CGFloat? {
        if let size = lastVideoSize, size.height > 0 {
            return size.width / size.height
        }
        if let size = lastImageSize, size.height > 0 {
            return size.width / size.height
        }
        return nil
    }

    func hideSettingsSheet() {
        guard !rightSettingsSheet.isHidden else { return }
        rightSettingsSheet.isHidden = true
        if usesImmersiveChrome {
            noteImmersiveChromePointerActivity()
        }
        raisePlaybackChromeToFront()
        removeOutsideClickMonitorIfNoSheetsVisible()
    }

    func showFullMediaLibrary() {
        installLibraryChromeIfNeeded()
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = false
        libraryBrowse.isHidden = false
        playbackMiniPreview.isHidden = true
        librarySidebar.reloadRoots()
        // Grid scan can be slow for large folders — keep UI responsive at launch.
        switch mediaLibraryController.sidebarMode {
        case .root where mediaLibraryController.currentDirectoryURL != nil,
             .recentHeader:
            libraryBrowse.reloadContent()
        case .none, .root:
            libraryBrowse.refresh()
        }
        playerSurfaceView.isHidden = true
        openButton.isHidden = true
        hintLabel.isHidden = true
        raisePlaybackChromeToFront()
        relayoutLibraryChromeForTitleBar()
    }

    func showPlaybackLibrarySidebarOnly() {
        guard activeMediaKind != .empty else {
            showFullMediaLibrary()
            return
        }
        hideSettingsSheet()
        playbackLibraryOverlay = .sidebarOnly
        librarySidebar.isHidden = false
        libraryBrowse.isHidden = true
        librarySidebar.reloadRoots()
        showPlaybackMiniPreview()
        playerSurfaceView.isHidden = true
        imageSurfaceView.isHidden = true
        controlsContainer.isHidden = true
        imageControlsContainer.isHidden = true
        installOutsideClickMonitor()
        raisePlaybackChromeToFront()
        refreshImmersiveChromePinnedState()
    }

    private func expandPlaybackLibraryBrowse() {
        guard activeMediaKind != .empty else { return }
        hideSettingsSheet()
        playbackLibraryOverlay = .sidebarAndBrowse
        libraryBrowse.isHidden = false
        libraryBrowse.reloadContent()
        raisePlaybackChromeToFront()
    }

    private func collapsePlaybackLibraryBrowseOnly() {
        guard playbackLibraryOverlay == .sidebarAndBrowse else { return }
        playbackLibraryOverlay = .sidebarOnly
        libraryBrowse.isHidden = true
    }

    func collapsePlaybackLibraryOverlay() {
        guard activeMediaKind != .empty else { return }
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = true
        libraryBrowse.isHidden = true
        playbackMiniPreview.isHidden = true
        restoreMainPlaybackSurface()
        removeOutsideClickMonitorIfNoSheetsVisible()
        raisePlaybackChromeToFront()
        if usesImmersiveChrome {
            noteImmersiveChromePointerActivity()
        } else {
            refreshImmersiveChromePinnedState()
        }
    }

    func hideMediaLibrary() {
        if activeMediaKind == .empty { return }
        collapsePlaybackLibraryOverlay()
    }

    private func restoreMainPlaybackSurface() {
        switch activeMediaKind {
        case .empty:
            break
        case .video:
            playerSurfaceView.isHidden = false
            applyPlaybackBarVisible(immersiveChromeVisible, animated: false)
        case .image:
            imageSurfaceView.isHidden = false
            applyPlaybackBarVisible(immersiveChromeVisible, animated: false)
        }
    }

    private func showPlaybackMiniPreview() {
        updateMiniPreviewLayout()
        switch activeMediaKind {
        case .video:
            playbackMiniPreview.showVideo(player: player)
        case .image:
            playbackMiniPreview.showImage(imageSurfaceView.image)
        case .empty:
            playbackMiniPreview.isHidden = true
            return
        }
        playbackMiniPreview.isHidden = false
    }

    private func updateMiniPreviewLayout() {
        guard libraryChromeInstalled else { return }
        let size = PlaybackMiniPreviewMetrics.preferredSize(forContentWidth: max(view.bounds.width, 1))
        miniPreviewWidthConstraint?.constant = size.width
        miniPreviewHeightConstraint?.constant = size.height
        playbackMiniPreview.applyLayoutScale(forWidth: size.width)
    }

    private func closePlaybackFromMiniPreview() {
        playbackMiniPreview.isHidden = true
        playbackMiniPreview.detachVideoPlayer()
        showEmptySurface()
    }

    private func syncPlaybackLibraryBrowseExpansion() {
        guard activeMediaKind != .empty else { return }

        switch mediaLibraryController.sidebarMode {
        case .root, .recentHeader:
            if playbackLibraryOverlay == .sidebarOnly {
                expandPlaybackLibraryBrowse()
            }
        case .none:
            if playbackLibraryOverlay == .sidebarAndBrowse {
                collapsePlaybackLibraryBrowseOnly()
            }
        }
    }

    private func dismissSidePanelsForFocusedPlayback() {
        hideSettingsSheet()
        hideMediaLibrary()
    }

    func mediaLibraryDidSelectMedia(url: URL, kind: DroppedMediaKind) {
        queue.removeAll()
        playbackHistory.removeAll()
        switch kind {
        case .video:
            loadVideo(url: url, replaceCurrent: true)
        case .image:
            loadImage(url: url)
        case .unsupported:
            showUnsupportedFileMessage("Unsupported file type.")
        }
    }

    private func isTransientMenuWindow(_ window: NSWindow?) -> Bool {
        guard let window, window !== view.window else { return false }
        if window.level == .popUpMenu { return true }
        let name = String(describing: type(of: window))
        return name.contains("Menu") || name.contains("Popup")
    }

    private func shouldKeepSettingsSheetOpen(for event: NSEvent) -> Bool {
        if suppressSettingsDismissForColorPicker { return true }
        let pointInView = view.convert(event.locationInWindow, from: nil)
        if rightSettingsSheet.frame.contains(pointInView) { return true }
        if settingsButton.frame.contains(pointInView) || imageSettingsButton.frame.contains(pointInView) {
            return true
        }
        if isTransientMenuWindow(event.window) { return true }
        if isColorPickerAuxiliaryWindow(event.window) { return true }
        return false
    }

    private func isColorPickerAuxiliaryWindow(_ window: NSWindow?) -> Bool {
        guard let window, window !== view.window else { return false }
        let name = String(describing: type(of: window)).lowercased()
        return name.contains("popover") || name.contains("colorpanel") || name.contains("colorpicker")
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard self.view.window != nil else { return event }
            let pointInView = self.view.convert(event.locationInWindow, from: nil)

            if !self.rightSettingsSheet.isHidden {
                if self.shouldKeepSettingsSheetOpen(for: event) {
                    return event
                }
                self.hideSettingsSheet()
            }

            if self.playbackLibraryOverlay != .closed, self.activeMediaKind != .empty {
                if self.librarySidebar.frame.contains(pointInView)
                    || self.libraryBrowse.frame.contains(pointInView)
                    || self.playbackMiniPreview.frame.contains(pointInView) {
                    return event
                }
                if self.libraryButton.frame.contains(pointInView) {
                    return event
                }
                self.collapsePlaybackLibraryOverlay()
            }

            return event
        }
    }

    private func removeOutsideClickMonitorIfNoSheetsVisible() {
        if rightSettingsSheet.isHidden, playbackLibraryOverlay == .closed {
            removeOutsideClickMonitor()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func handleMouseMoved(_ point: NSPoint) {
        guard view.bounds.contains(point) else {
            cancelEdgePanelHoverTimers()
            handlePointerLeftContentView()
            return
        }
        noteImmersiveChromePointerActivity()
        guard !dragSessionActive else {
            cancelEdgePanelHoverTimers()
            return
        }

        let hotZoneWidth: CGFloat = 42
        let isInLeftHotZone = point.x <= hotZoneWidth
        let isInRightHotZone = point.x >= (view.bounds.width - hotZoneWidth)

        if isInLeftHotZone, activeMediaKind != .empty, playbackLibraryOverlay == .closed {
            scheduleLeftEdgePanelOpen()
        } else {
            cancelLeftEdgePanelOpen()
        }

        if activeMediaKind != .empty, isInRightHotZone, playbackLibraryOverlay == .closed, rightSettingsSheet.isHidden {
            scheduleRightEdgePanelOpen()
        } else {
            cancelRightEdgePanelOpen()
        }
    }

    private func scheduleLeftEdgePanelOpen() {
        guard pendingLeftEdgePanelOpen == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingLeftEdgePanelOpen = nil
            guard self.activeMediaKind != .empty, self.playbackLibraryOverlay == .closed else { return }
            self.showPlaybackLibrarySidebarOnly()
        }
        pendingLeftEdgePanelOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.edgePanelOpenDelay, execute: work)
    }

    private func cancelLeftEdgePanelOpen() {
        pendingLeftEdgePanelOpen?.cancel()
        pendingLeftEdgePanelOpen = nil
    }

    private func scheduleRightEdgePanelOpen() {
        guard pendingRightEdgePanelOpen == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRightEdgePanelOpen = nil
            guard self.activeMediaKind != .empty,
                  self.playbackLibraryOverlay == .closed,
                  self.rightSettingsSheet.isHidden else { return }
            self.showSettingsSheet()
        }
        pendingRightEdgePanelOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.edgePanelOpenDelay, execute: work)
    }

    private func cancelRightEdgePanelOpen() {
        pendingRightEdgePanelOpen?.cancel()
        pendingRightEdgePanelOpen = nil
    }

    private func cancelEdgePanelHoverTimers() {
        cancelLeftEdgePanelOpen()
        cancelRightEdgePanelOpen()
    }

    private func handlePointerLeftContentView() {
        cancelEdgePanelHoverTimers()
        scheduleImmersiveChromeHide()
        restoreImmersivePlaybackCursor()
        // Settings stays open for in-panel interaction; outside-click monitor dismisses it.
        guard rightSettingsSheet.isHidden else { return }
        hideSettingsSheet()
    }

    // MARK: - Immersive window chrome (auto-hide title bar + playback bar)

    private var usesImmersiveChrome: Bool {
        activeMediaKind == .video || activeMediaKind == .image
    }

    /// Library-only main view: title bar + traffic lights stay visible (no auto-hide).
    private var titleBarChromeAlwaysVisible: Bool {
        activeMediaKind == .empty
    }

    private var isTitleBarChromeShowing: Bool {
        titleBarChromeAlwaysVisible || immersiveChromeVisible || immersiveChromePinnedVisible
    }

    private var immersiveChromePinnedVisible: Bool {
        dragSessionActive
            || playbackLibraryOverlay != .closed
            || !rightSettingsSheet.isHidden
            || queuePopover?.isShown == true
    }

    private func currentPlayingDisplayTitle() -> String? {
        currentMediaURL?.deletingPathExtension().lastPathComponent
    }

    func playingTitleForWindow() -> String? {
        currentPlayingDisplayTitle()
    }

    var usesImmersiveChromeForWindow: Bool {
        usesImmersiveChrome
    }

    private func syncPlayingWindowTitle() {
        delegate?.playerViewController(self, setImmersiveChromeVisible: isTitleBarChromeShowing, animated: false)
    }

    private func syncPlaybackBarVisibilityForCurrentState() {
        guard activeMediaKind == .video || activeMediaKind == .image else { return }
        let keepBarVisible = playbackPrepareActive || (fallbackInProgress && committedPlayerItemID == nil)
        if keepBarVisible {
            applyPlaybackBarVisible(true, animated: false)
            if usesImmersiveChrome {
                immersiveChromeVisible = true
            }
            return
        }
        if usesImmersiveChrome {
            applyPlaybackBarVisible(immersiveChromeVisible, animated: false)
        } else {
            applyPlaybackBarVisible(true, animated: false)
        }
    }

    private func resetImmersiveChromeAfterMediaChange() {
        immersiveChromeHideWorkItem?.cancel()
        immersiveChromeHideWorkItem = nil
        installImmersivePointerMonitorIfNeeded()
        setImmersiveChromeVisible(false, animated: false)
    }

    private func installImmersivePointerMonitorIfNeeded() {
        removeImmersivePointerMonitor()
        guard usesImmersiveChrome else { return }
        immersivePointerMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, let window = self.view.window, event.window === window else { return event }
            let point = self.view.convert(event.locationInWindow, from: nil)
            self.restoreImmersivePlaybackCursor()
            if self.view.bounds.contains(point) {
                self.noteImmersiveChromePointerActivity()
                self.handleMouseMoved(point)
            } else {
                self.handlePointerLeftContentView()
            }
            return event
        }
    }

    private func removeImmersivePointerMonitor() {
        if let immersivePointerMonitor {
            NSEvent.removeMonitor(immersivePointerMonitor)
            self.immersivePointerMonitor = nil
        }
    }

    private func noteImmersiveChromePointerActivity() {
        guard usesImmersiveChrome else { return }
        restoreImmersivePlaybackCursor()
        immersiveChromeHideWorkItem?.cancel()
        immersiveChromeHideWorkItem = nil
        setImmersiveChromeVisible(true, animated: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.immersiveChromeHideWorkItem = nil
            guard !self.immersiveChromePinnedVisible else {
                self.scheduleImmersiveChromeHide()
                return
            }
            self.setImmersiveChromeVisible(false, animated: true)
        }
        immersiveChromeHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ImmersiveWindowChrome.hideDelay, execute: work)
    }

    private func scheduleImmersiveChromeHide() {
        guard usesImmersiveChrome, !immersiveChromePinnedVisible else { return }
        immersiveChromeHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.setImmersiveChromeVisible(false, animated: true)
        }
        immersiveChromeHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func setImmersiveChromeVisible(_ visible: Bool, animated: Bool) {
        let shouldShowTitleBar = titleBarChromeAlwaysVisible || visible || immersiveChromePinnedVisible
        let shouldShowPlaybackBar = usesImmersiveChrome && (visible || immersiveChromePinnedVisible)
        guard shouldShowTitleBar != isTitleBarChromeShowing else {
            if shouldShowTitleBar {
                delegate?.playerViewController(self, setImmersiveChromeVisible: true, animated: animated)
                updateTitleBarChromeStrip(visible: true, animated: animated)
                relayoutLibraryChromeForTitleBar()
            }
            if usesImmersiveChrome, shouldShowPlaybackBar != immersiveChromeVisible {
                immersiveChromeVisible = shouldShowPlaybackBar
                applyPlaybackBarVisible(shouldShowPlaybackBar, animated: animated)
            }
            syncImmersivePlaybackCursor()
            return
        }
        immersiveChromeVisible = shouldShowPlaybackBar
        if usesImmersiveChrome {
            applyPlaybackBarVisible(shouldShowPlaybackBar, animated: animated)
        }
        delegate?.playerViewController(self, setImmersiveChromeVisible: shouldShowTitleBar, animated: animated)
        updateTitleBarChromeStrip(visible: shouldShowTitleBar, animated: animated)
        relayoutLibraryChromeForTitleBar()
        syncImmersivePlaybackCursor()
    }

    /// Hides the pointer when playback chrome auto-hides; restores on movement (same idle timing as bars).
    private func syncImmersivePlaybackCursor() {
        guard usesImmersiveChrome else {
            restoreImmersivePlaybackCursor()
            return
        }
        let chromeVisible = isTitleBarChromeShowing || immersiveChromeVisible
        if chromeVisible || immersiveChromePinnedVisible {
            restoreImmersivePlaybackCursor()
        } else {
            hideImmersivePlaybackCursorUntilMouseMoves()
        }
    }

    private func hideImmersivePlaybackCursorUntilMouseMoves() {
        guard !immersiveCursorHiddenUntilMove else { return }
        immersiveCursorHiddenUntilMove = true
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func restoreImmersivePlaybackCursor() {
        guard immersiveCursorHiddenUntilMove else { return }
        immersiveCursorHiddenUntilMove = false
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    private func installImmersiveCursorWindowObserversIfNeeded() {
        guard immersiveCursorWindowObservers.isEmpty, let window = view.window else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didResignKeyNotification
        ]
        immersiveCursorWindowObservers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                guard let self else { return }
                self.restoreImmersivePlaybackCursor()
                switch notification.name {
                case NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification,
                     NSWindow.willExitFullScreenNotification:
                    self.revealImmersiveChromeAfterDisplayChange()
                default:
                    break
                }
            }
        }
    }

    /// Show title/playback chrome after fullscreen or layout jumps (pointer may not move).
    func prepareImmersiveChromeForFullscreenToggle() {
        revealImmersiveChromeAfterDisplayChange()
    }

    private func revealImmersiveChromeAfterDisplayChange() {
        guard usesImmersiveChrome else { return }
        updatePlaybackBarWidth()
        updateMiniPreviewLayout()
        noteImmersiveChromePointerActivity()
    }

    private func removeImmersiveCursorWindowObservers() {
        let center = NotificationCenter.default
        for token in immersiveCursorWindowObservers {
            center.removeObserver(token)
        }
        immersiveCursorWindowObservers.removeAll()
    }

    private func updateTitleBarChromeLayout() {
        titleBarChromeHeightConstraint?.constant = ImmersiveWindowChrome.titleBarChromeStripHeight(for: view.window)
        if isTitleBarChromeShowing {
            relayoutLibraryChromeForTitleBar()
        }
    }

    private func updateTitleBarChromeStrip(visible: Bool, animated: Bool = false) {
        guard playerInterfaceInstalled else { return }
        updateTitleBarChromeLayout()
        let apply = {
            self.titleBarChromeStrip.alphaValue = visible ? 1 : 0
            self.titleBarChromeStrip.isHidden = !visible
            if visible {
                self.raiseTitleBarChromeToFront()
            }
        }
        guard animated else {
            apply()
            return
        }
        if visible {
            titleBarChromeStrip.isHidden = false
            raiseTitleBarChromeToFront()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ImmersiveWindowChrome.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.titleBarChromeStrip.animator().alphaValue = visible ? 1 : 0
        } completionHandler: {
            if !visible {
                self.titleBarChromeStrip.isHidden = true
            }
        }
    }

    private func relayoutLibraryChromeForTitleBar() {
        guard libraryChromeInstalled else { return }
        librarySidebar.syncTitleBarContentInset(chromeVisible: isTitleBarChromeShowing)
        libraryBrowse.syncTitleBarContentInset(chromeVisible: isTitleBarChromeShowing)
    }

    private func applyPlaybackBarVisible(_ visible: Bool, animated: Bool = false) {
        let bar = activeMediaKind == .image ? imageControlsContainer : controlsContainer
        guard activeMediaKind == .video || activeMediaKind == .image else { return }
        let apply = {
            bar.alphaValue = visible ? 1 : 0
            bar.isHidden = !visible
        }
        guard animated else {
            apply()
            return
        }
        if visible {
            bar.isHidden = false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ImmersiveWindowChrome.animationDuration
            bar.animator().alphaValue = visible ? 1 : 0
        } completionHandler: {
            if !visible {
                bar.isHidden = true
            }
        }
    }

    private func refreshImmersiveChromePinnedState() {
        if immersiveChromePinnedVisible {
            setImmersiveChromeVisible(true, animated: true)
        }
    }

    private func setupPlaybackTopRowLayout() {
        guard !playbackTopRowLayoutConfigured else { return }
        playbackTopRowLayoutConfigured = true

        playbackTopRowView.translatesAutoresizingMaskIntoConstraints = false
        playbackCenterClusterStack.translatesAutoresizingMaskIntoConstraints = false
        volumeCluster.translatesAutoresizingMaskIntoConstraints = false

        playbackTopRowView.addSubview(playbackCenterClusterStack)
        playbackTopRowView.addSubview(volumeCluster)

        playbackCenterToVolumeConstraint = playbackCenterClusterStack.trailingAnchor.constraint(
            lessThanOrEqualTo: volumeCluster.leadingAnchor,
            constant: -playbackControlClusterSpacing
        )
        playbackCenterToEdgeConstraint = playbackCenterClusterStack.trailingAnchor.constraint(
            lessThanOrEqualTo: playbackTopRowView.trailingAnchor
        )

        NSLayoutConstraint.activate([
            playbackTopRowView.heightAnchor.constraint(equalToConstant: 28),

            volumeCluster.trailingAnchor.constraint(equalTo: playbackTopRowView.trailingAnchor),
            volumeCluster.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            playbackCenterClusterStack.centerXAnchor.constraint(equalTo: playbackTopRowView.centerXAnchor),
            playbackCenterClusterStack.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),
            playbackCenterClusterStack.leadingAnchor.constraint(greaterThanOrEqualTo: playbackTopRowView.leadingAnchor),
            playbackCenterToVolumeConstraint!,
            playbackCenterToEdgeConstraint!
        ])
        playbackCenterToEdgeConstraint?.isActive = false
        updatePlaybackVolumeChromeVisibility()
    }

    private func configureTransportSpeedClusterSpacer(_ spacer: NSView) {
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private static let transportControlRowHeight: CGFloat = 28

    private func configureTransportSpeedLabel(_ label: NSTextField, alignment: NSTextAlignment) {
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.alphaValue = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: Self.transportSpeedLabelReservedWidth).isActive = true
        label.heightAnchor.constraint(equalToConstant: Self.transportControlRowHeight).isActive = true
    }

    private func setTransportSpeedLabelText(_ text: String, on label: NSTextField, alignment: NSTextAlignment) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.minimumLineHeight = Self.transportControlRowHeight
        style.maximumLineHeight = Self.transportControlRowHeight
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
        )
    }

    private func clearTransportSpeedLabel(_ label: NSTextField) {
        label.attributedStringValue = NSAttributedString()
        label.stringValue = ""
    }

    /// Fixed slot so transport controls do not shift when a speed label appears.
    private static let transportSpeedLabelReservedWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let samples = PlaybackSpeedSteps.rates.map { rate -> String in
            let rounded = (rate * 100).rounded() / 100
            if rounded == rounded.rounded() {
                return String(format: "%.0f×", rounded)
            }
            return String(format: "%.2f×", rounded)
        }
        let width = samples.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 28
        return ceil(width) + 2
    }()

    private static let playbackBarAccessoryButtonSize = NSSize(width: 24, height: 24)
    private static let playbackBarAccessoryIconPointSize: CGFloat = 12

    private func configurePlaybackBarAccessoryButton(_ button: NSButton, symbol: String, label: String) {
        styleIconButton(
            button,
            symbol: symbol,
            label: label,
            pointSize: Self.playbackBarAccessoryIconPointSize
        )
        pinTransportIconButtonSize(
            button,
            width: Self.playbackBarAccessoryButtonSize.width,
            height: Self.playbackBarAccessoryButtonSize.height
        )
        button.imagePosition = .imageOnly
    }

    private func styleIconButton(_ button: NSButton, symbol: String, label: String, pointSize: CGFloat = 15) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.title = ""
        button.toolTip = label
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func updatePlaybackBarWidth() {
        let contentWidth = view.bounds.width
        playbackBarWidthConstraint?.constant = MusicStylePlaybackBar.preferredBarWidth(
            forContentWidthPoints: contentWidth
        )
        imageBarWidthConstraint?.constant = MusicStylePlaybackBar.preferredBarWidth(
            forContentWidthPoints: contentWidth
        )
        let bottomInset = MusicStylePlaybackBar.preferredBarBottomInset(forContentWidthPoints: contentWidth)
        playbackBarBottomConstraint?.constant = -bottomInset
        imageBarBottomConstraint?.constant = -bottomInset
    }

    private func applyResponsiveControlsLayout() {
        guard activeMediaKind == .video else { return }
        updatePlaybackBarWidth()
        let start = CFAbsoluteTimeGetCurrent()
        let width = view.bounds.width
        let newTier: ControlDensityTier
        if width < 700 {
            newTier = .compact
        } else if width <= 1200 {
            newTier = .regular
        } else {
            newTier = .spacious
        }

        guard newTier != currentControlTier || controlsStack.arrangedSubviews.isEmpty else { return }
        currentControlTier = newTier
        rebuildControlsForTier(newTier)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[DEBUG-ui] controls tier=%@ layout=%.2fms", String(describing: newTier), elapsedMs))
    }

    private func rebuildControlsForTier(_ tier: ControlDensityTier) {
        controlsStack.arrangedSubviews.forEach { view in
            controlsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        topControlsStack.arrangedSubviews.forEach { view in
            topControlsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        playbackCenterClusterStack.arrangedSubviews.forEach { view in
            playbackCenterClusterStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bottomLeftControlsStack.arrangedSubviews.forEach { view in
            bottomLeftControlsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bottomRightControlsStack.arrangedSubviews.forEach { view in
            bottomRightControlsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bottomControlsStack.arrangedSubviews.forEach { view in
            bottomControlsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch tier {
        case .compact:
            controlsContainer.constraints.first { $0.firstAttribute == .height }?.constant = 72
        case .regular:
            controlsContainer.constraints.first { $0.firstAttribute == .height }?.constant = 76
        case .spacious:
            controlsContainer.constraints.first { $0.firstAttribute == .height }?.constant = 80
        }

        controlsStack.addArrangedSubview(topControlsStack)
        controlsStack.addArrangedSubview(bottomControlsStack)

        detachImageAccessoryClusterFromImageControls()
        moveQueueButtonToPlaybackAccessoryCluster()

        transportClusterStack.arrangedSubviews.forEach {
            transportClusterStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        transportClusterStack.addArrangedSubview(queuePreviousButton)
        transportClusterStack.addArrangedSubview(transportSpeedLeftCluster)
        transportClusterStack.addArrangedSubview(playPauseButton)
        transportClusterStack.addArrangedSubview(transportSpeedRightCluster)
        transportClusterStack.addArrangedSubview(queueNextButton)
        updatePlaybackSpeedTransportLabels()
        updateQueueTransportButtons()

        playbackCenterClusterStack.addArrangedSubview(playbackSubtitleToggle)
        MusicStylePlaybackBar.configureSubtitleToggleButton(playbackSubtitleToggle)
        playbackSubtitleToggle.target = self
        playbackSubtitleToggle.action = #selector(playbackSubtitleTogglePressed)
        playbackCenterClusterStack.addArrangedSubview(libraryButton)
        playbackCenterClusterStack.addArrangedSubview(transportClusterStack)
        playbackCenterClusterStack.addArrangedSubview(playbackAccessoryCluster)
        updateQueueButtonState()

        if playbackTopRowView.superview != topControlsStack {
            topControlsStack.addArrangedSubview(playbackTopRowView)
            playbackTopRowView.widthAnchor.constraint(equalTo: topControlsStack.widthAnchor).isActive = true
        }
        playbackTopRowView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        bottomLeftControlsStack.addArrangedSubview(currentTimeLabel)
        bottomRightControlsStack.addArrangedSubview(totalTimeLabel)

        bottomControlsStack.addArrangedSubview(bottomLeftControlsStack)
        bottomControlsStack.addArrangedSubview(seekSlider)
        bottomControlsStack.addArrangedSubview(bottomRightControlsStack)

        currentTimeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        totalTimeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        updatePlaybackVolumeChromeVisibility()
        bottomControlsStack.widthAnchor.constraint(equalTo: controlsStack.widthAnchor).isActive = true
    }

    private func volumeSliderWidth(for tier: ControlDensityTier) -> CGFloat {
        switch tier {
        case .compact: return 48
        case .regular: return 58
        case .spacious: return 68
        }
    }

    private func pinTransportIconButtonSize(_ button: NSButton, width: CGFloat = 28, height: CGFloat = 28) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: height).isActive = true
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func updatePlayPauseButtonIcon() {
        let playing = mpvBackendActive ? (activeSession?.isPlaying == true) : (player.rate > 0)
        let symbol = playing ? "pause.fill" : "play.fill"
        let label = playing ? "Pause" : "Play"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            playPauseButton.image = image.withSymbolConfiguration(config)
            playPauseButton.image?.isTemplate = true
        }
        playPauseButton.title = ""
    }

    private func updateTimelineUI() {
        guard !isSeekingFromUI else { return }
        if mpvBackendActive, let session = activeSession {
            let durationSec = session.durationSec
            let currentSec = session.currentTimeSec
            if durationSec.isFinite, durationSec > 0 {
                seekSlider.maxValue = durationSec
                seekSlider.doubleValue = max(0, min(currentSec, durationSec))
                currentTimeLabel.stringValue = formatTime(currentSec)
                totalTimeLabel.stringValue = formatTime(durationSec)
            }
            updateSeekBarPreparingState()
            return
        }
        guard let currentItem = player.currentItem else {
            updateSeekBarPreparingState()
            return
        }
        logBufferStateChanges(item: currentItem)
        let itemDurationSec = CMTimeGetSeconds(currentItem.duration)
        let currentSec = CMTimeGetSeconds(player.currentTime())
        let durationSec: Double
        if isPreviewPlaybackActive, let sourceDuration = activePreviewSourceDurationSec, sourceDuration > 0 {
            durationSec = sourceDuration
        } else if itemDurationSec.isFinite && itemDurationSec > 0 {
            durationSec = itemDurationSec
        } else {
            updateSeekBarPreparingState()
            return
        }
        if durationSec.isFinite && durationSec > 0 {
            seekSlider.maxValue = durationSec
            if !isSeekBarPreparing {
                seekSlider.doubleValue = max(0, min(currentSec, durationSec))
            }
            currentTimeLabel.stringValue = formatTime(currentSec)
            totalTimeLabel.stringValue = formatTime(durationSec)
        }
        updateSeekBarPreparingState()
    }

    /// True only while waiting for the first playable frame — not during background full remux.
    private var isSeekBarPreparing: Bool {
        playbackPrepareActive || (fallbackInProgress && committedPlayerItemID == nil)
    }

    private func updateSeekBarPreparingState() {
        let preparing = isSeekBarPreparing
        seekSlider.flatBarCell?.isPreparing = preparing

        if preparing {
            if seekBarPrepareTimer == nil {
                seekBarPrepareTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    self?.tickSeekBarPreparingAnimation()
                }
            }
            if (fallbackInProgress || playbackPrepareActive) && player.currentItem == nil {
                seekSlider.isEnabled = false
                currentTimeLabel.stringValue = "···"
                if let sourceDuration = activePreviewSourceDurationSec, sourceDuration > 0 {
                    seekSlider.maxValue = sourceDuration
                    totalTimeLabel.stringValue = formatTime(sourceDuration)
                } else {
                    totalTimeLabel.stringValue = "--:--"
                }
            } else {
                seekSlider.isEnabled = true
            }
        } else {
            seekBarPrepareTimer?.invalidate()
            seekBarPrepareTimer = nil
            seekSlider.isEnabled = true
        }
        seekSlider.needsDisplay = true
        syncPlaybackBarVisibilityForCurrentState()
    }

    private func tickSeekBarPreparingAnimation() {
        guard isSeekBarPreparing, let flat = seekSlider.flatBarCell else {
            updateSeekBarPreparingState()
            return
        }
        let cycle = sin(CACurrentMediaTime() * 2.4)
        flat.preparingPhase = CGFloat((cycle + 1) / 2)
        seekSlider.needsDisplay = true
    }

    private func stopSeekBarPreparingAnimation() {
        seekBarPrepareTimer?.invalidate()
        seekBarPrepareTimer = nil
        seekSlider.flatBarCell?.isPreparing = false
        seekSlider.isEnabled = true
        seekSlider.needsDisplay = true
    }

    private func formatTime(_ sec: Double) -> String {
        guard sec.isFinite, sec >= 0 else { return "00:00" }
        let total = Int(sec.rounded(.down))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func logBufferStateChanges(item: AVPlayerItem) {
        let likely = item.isPlaybackLikelyToKeepUp
        let empty = item.isPlaybackBufferEmpty
        let full = item.isPlaybackBufferFull

        if lastLikelyToKeepUp != likely || lastBufferEmpty != empty || lastBufferFull != full {
            lastLikelyToKeepUp = likely
            lastBufferEmpty = empty
            lastBufferFull = full
            print("[DEBUG-qos] buffer_state keepUp=\(likely) empty=\(empty) full=\(full)")
        }
    }

    private func logPlaybackHealthSnapshot(reason: String, item: AVPlayerItem) {
        let keepUp = item.isPlaybackLikelyToKeepUp
        let empty = item.isPlaybackBufferEmpty
        let full = item.isPlaybackBufferFull

        if let event = item.accessLog()?.events.last {
            print(String(
                format: "[DEBUG-qos] %@ keepUp=%@ empty=%@ full=%@ bitrate=%.0f indicated=%.0f droppedFrames=%ld stalls=%ld transfer=%.3fs",
                reason,
                keepUp.description,
                empty.description,
                full.description,
                event.observedBitrate,
                event.indicatedBitrate,
                event.numberOfDroppedVideoFrames,
                event.numberOfStalls,
                event.transferDuration
            ))
        } else {
            print("[DEBUG-qos] \(reason) keepUp=\(keepUp) empty=\(empty) full=\(full) (no access log events yet)")
        }
    }

    private func logErrorLogSnapshot(reason: String, item: AVPlayerItem) {
        guard let event = item.errorLog()?.events.last else {
            print("[DEBUG-qos] \(reason) no error log events")
            return
        }
        print(
            "[DEBUG-qos] \(reason) domain=\(event.errorDomain) code=\(event.errorStatusCode) comment=\(event.errorComment ?? "none") uri=\(event.uri ?? "none") server=\(event.serverAddress ?? "none")"
        )
    }

    @objc func togglePlayPause() {
        let start = CFAbsoluteTimeGetCurrent()
        if mpvBackendActive, let session = activeSession {
            if session.isPlaying {
                session.pause()
            } else {
                startPlaybackAtPreferredRate()
            }
        } else if player.rate > 0 {
            player.pause()
        } else {
            startPlaybackAtPreferredRate()
        }
        updatePlayPauseButtonIcon()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[DEBUG-ui] playPause=%.2fms", elapsedMs))
    }

    @objc private func seekSliderChanged() {
        let start = CFAbsoluteTimeGetCurrent()
        let targetSec = seekSlider.doubleValue
        if isPreviewPlaybackActive,
           targetSec > activePlayableDurationSec - 5,
           let sourceDuration = activePreviewSourceDurationSec,
           targetSec < sourceDuration - 5 {
            performProgressiveSeek(to: targetSec)
            return
        }
        let target = CMTime(seconds: targetSec, preferredTimescale: 600)
        performCooperativeSeek(to: target) { _ in
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print(String(format: "[DEBUG-ui] seek=%.2fms", elapsedMs))
        }
    }

    private func performProgressiveSeek(to targetSec: Double) {
        guard let previewURL = observedItemPlayableURL,
              let sourceURL = playbackSourceURL ?? currentMediaURL else { return }
        let wasPlaying = player.rate > 0
        player.pause()
        showCompatibilityFailure("Buffering seek…")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let pollIntervalNs: UInt64 = 2_000_000_000
            let maxWaitNs: UInt64 = 120 * 1_000_000_000
            var waited: UInt64 = 0

            while waited < maxWaitNs {
                if Task.isCancelled { return }

                if let fullTarget = await MainActor.run(body: { self.activePreviewFullTargetURL }),
                   FFmpegVideoFallback.isFullRemuxReady(at: fullTarget) {
                    await MainActor.run {
                        self.hideCompatibilityFailure()
                        self.pendingStartTimeAfterLoad = CMTime(seconds: targetSec, preferredTimescale: 600)
                        self.pendingResumePlayingAfterLoad = wasPlaying
                        self.clearPreviewPlaybackState()
                        self.fallbackConvertedOutputPaths.insert(fullTarget.path)
                        self.resolveAndAttach(
                            playableURL: fullTarget,
                            sourceURL: sourceURL,
                            generation: self.videoLoadGeneration
                        )
                    }
                    return
                }

                let playable = FFmpegVideoFallback.remuxOutputDurationSec(at: previewURL) ?? 0
                if playable >= targetSec - 2 {
                    await MainActor.run {
                        self.hideCompatibilityFailure()
                        self.activePlayableDurationSec = max(self.activePlayableDurationSec, playable)
                        self.pendingStartTimeAfterLoad = CMTime(seconds: targetSec, preferredTimescale: 600)
                        self.pendingResumePlayingAfterLoad = wasPlaying
                        self.progressiveExtendInProgress = true
                        self.resolveAndAttach(
                            playableURL: previewURL,
                            sourceURL: sourceURL,
                            generation: self.videoLoadGeneration
                        )
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: pollIntervalNs)
                waited += pollIntervalNs
            }

            await MainActor.run {
                self.hideCompatibilityFailure()
                self.showCompatibilityFailure("Seek target is not remuxed yet. Try again shortly.")
            }
        }
    }

    @objc private func volumeSliderChanged() {
        guard audioOutputEnabled else { return }
        let start = CFAbsoluteTimeGetCurrent()
        desiredPlaybackVolume = Float(volumeSlider.doubleValue)
        if desiredPlaybackVolume < 0.01 {
            isUserVolumeMuted = true
        } else {
            isUserVolumeMuted = false
            volumeLevelBeforeUserMute = desiredPlaybackVolume
        }
        applyEffectivePlaybackVolume()
        updateVolumeMuteButtonIcon()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[DEBUG-ui] volume=%.2fms", elapsedMs))
    }

    /// Pause and mute Laugh only (not system output) before swapping items.
    private func preparePlayerForVideoSwitch() {
        volumeRampToken += 1
        isMutedForSwitch = true
        if mpvBackendActive {
            activeSession?.pause()
        }
        player.pause()
        player.isMuted = true
        print("[DEBUG-playback] paused Laugh for video switch (player muted, volume unchanged)")
    }

    /// Stop Laugh audio/video output without `replaceCurrentItem(nil)` — that call can reset Core Audio for all apps.
    private func suspendPlayerOutputForStillOrEmpty() {
        stopMpvBackend()
        volumeRampToken += 1
        isMutedForSwitch = true
        renderMonitor.reset()
        detachCurrentPlayerItemObserver()
        lastPlaybackStartedItemID = nil
        player.pause()
        player.isMuted = true
        player.volume = 0
        disconnectPlayerFromVideoSurfaces()
        print("[DEBUG-playback] suspended AVPlayer output (still image / empty — no item teardown)")
    }

    private func connectPlayerToVideoSurfaces() {
        guard !mpvBackendActive else { return }
        playerSurfaceView.setMpvEmbeddingActive(false)
        if !isMutedForSwitch {
            player.isMuted = false
        }
        if playerSurfaceView.player !== player {
            playerSurfaceView.player = player
        }
    }

    private func disconnectPlayerFromVideoSurfaces() {
        if playerSurfaceView.player != nil {
            playerSurfaceView.player = nil
        }
        playbackMiniPreview.detachVideoPlayer()
    }

    private func restoreAudioAfterSwitchSmoothly() {
        guard audioOutputEnabled else {
            isMutedForSwitch = false
            return
        }
        isMutedForSwitch = false
        applyEffectivePlaybackVolume()
        updateVolumeMuteButtonIcon()
        print(String(format: "[DEBUG-playback] restored Laugh volume=%.2f muted=%@", effectivePlaybackVolume(), isUserVolumeMuted.description))
    }

    /// Safety net after playback has actually started — never during an in-flight switch.
    private func ensureLaughVolumeIfPlaying() {
        guard activeMediaKind == .video else { return }
        guard audioOutputEnabled else { return }
        guard !isMutedForSwitch else { return }
        guard !isUserVolumeMuted, desiredPlaybackVolume > 0.01 else { return }
        if mpvBackendActive {
            guard mpvPlaybackStarted, activeSession?.isPlaying == true else { return }
            guard effectivePlaybackVolume() > 0.01 else { return }
            activeSession?.setVolume(effectivePlaybackVolume())
            return
        }
        guard lastPlaybackStartedItemID != nil else { return }
        guard player.rate > 0, player.currentItem != nil else { return }
        guard player.volume < 0.01 || player.isMuted else { return }
        applyEffectivePlaybackVolume()
        print(String(format: "[DEBUG-playback] volume safety restore=%.2f", effectivePlaybackVolume()))
    }

    @objc private func queuePreviousPressed() {
        playPreviousInQueue()
    }

    @objc private func queueNextPressed() {
        playNextInQueue()
    }

    @objc private func speedStepDownPressed() {
        stepPlaybackSpeed(by: -1)
    }

    @objc private func speedStepUpPressed() {
        stepPlaybackSpeed(by: 1)
    }

    @objc private func queuePressed() {
        toggleQueuePopover()
    }

    @objc private func settingsPressed() {
        guard activeMediaKind != .empty, playbackLibraryOverlay == .closed else { return }
        if rightSettingsSheet.isHidden {
            showSettingsSheet()
        } else {
            hideSettingsSheet()
        }
    }

    @objc private func libraryPressed() {
        if activeMediaKind == .empty {
            librarySidebar.reloadRoots()
            libraryBrowse.reloadContent()
            return
        }
        if playbackLibraryOverlay != .closed {
            collapsePlaybackLibraryOverlay()
        } else {
            showPlaybackLibrarySidebarOnly()
        }
    }

    @objc private func videoSettingsTabPressed(_ sender: NSButton) {
        let index = videoSettingsTabButtons.firstIndex(where: { $0 === sender }) ?? sender.tag
        selectVideoSettingsTab(index: index)
    }

    func selectVideoSettingsTab(index: Int) {
        guard activeMediaKind == .video else { return }
        selectedVideoSettingsTabIndex = max(0, min(index, 2))
        applySettingsTabButtonState()
        updateSettingsTabVisibility()
        if selectedVideoSettingsTabIndex == 1 {
            updateAudioEQAvailability()
            Task { await refreshAudioTrackPicker() }
        }
    }

    @objc private func imageSettingsTabPressed(_ sender: NSButton) {
        let index = imageSettingsTabButtons.firstIndex(where: { $0 === sender }) ?? sender.tag
        guard activeMediaKind == .image else { return }
        selectedImageSettingsTabIndex = max(0, min(index, 1))
        applySettingsTabButtonState()
        updateSettingsTabVisibility()
    }

    @objc func imageZoomIn() {
        imageSurfaceView.setZoomScale(min(imageSurfaceView.zoomScale * 1.15, 8.0))
    }

    @objc func imageZoomOut() {
        imageSurfaceView.setZoomScale(max(imageSurfaceView.zoomScale / 1.15, 0.2))
    }

    @objc func imageFit() {
        imageSurfaceView.resetZoom()
    }
}

extension PlayerViewController: SettingsColorWellInteractionDelegate {
    func colorWellDidBeginInteraction(_ colorWell: SettingsColorWell) {
        suppressSettingsDismissForColorPicker = true
    }

    func colorWellDidEndInteraction(_ colorWell: SettingsColorWell) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.suppressSettingsDismissForColorPicker = false
        }
    }
}

// MARK: - Shortcut command funnel

extension PlayerViewController {
    private static let standardSeekSeconds: Double = 10
    private static let fineSeekSeconds: Double = 1
    private static let volumeStep: Float = 0.05

    func installVideoDoubleClickFullscreenMonitor() {
        guard videoDoubleClickMonitor == nil else { return }
        videoDoubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            guard event.clickCount == 2, self.activeMediaKind == .video else { return event }
            guard self.shouldToggleFullscreenForVideoDoubleClick(at: event.locationInWindow) else { return event }
            self.revealImmersiveChromeAfterDisplayChange()
            self.view.window?.toggleFullScreen(nil)
            return event
        }
    }

    private func shouldToggleFullscreenForVideoDoubleClick(at windowLocation: NSPoint) -> Bool {
        guard !playerSurfaceView.isHidden else { return false }
        let pointInSurface = playerSurfaceView.convert(windowLocation, from: nil)
        guard playerSurfaceView.bounds.contains(pointInSurface) else { return false }
        return !isPointOverVideoChrome(windowLocation)
    }

    private func isPointOverVideoChrome(_ windowLocation: NSPoint) -> Bool {
        let chrome: [NSView] = [
            controlsContainer,
            rightSettingsSheet,
            librarySidebar,
            libraryBrowse,
            compatibilityBanner,
            queueDropZone,
            openButton,
            hintLabel,
            playbackMiniPreview
        ]
        for view in chrome where !view.isHidden {
            let local = view.convert(windowLocation, from: nil)
            if view.bounds.contains(local) {
                return true
            }
        }
        return false
    }

    func installKeyboardShortcutMonitor() {
        guard keyboardShortcutMonitor == nil else { return }
        keyboardShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.view.window?.isKeyWindow == true else { return event }
            if self.handleKeyboardEvent(event) {
                return nil
            }
            return event
        }
    }

    func commandToggleLibraryPanel() {
        if activeMediaKind == .empty {
            librarySidebar.reloadRoots()
            libraryBrowse.reloadContent()
            if playbackLibraryOverlay == .closed {
                showFullMediaLibrary()
            } else {
                hideMediaLibrary()
            }
            return
        }
        if playbackLibraryOverlay != .closed {
            collapsePlaybackLibraryOverlay()
        } else {
            showPlaybackLibrarySidebarOnly()
        }
    }

    func commandToggleSettingsInspector() {
        guard activeMediaKind != .empty, playbackLibraryOverlay == .closed else { return }
        if rightSettingsSheet.isHidden {
            showSettingsSheet()
        } else {
            hideSettingsSheet()
        }
    }

    func commandSelectSettingsTab(_ index: Int) {
        guard activeMediaKind == .video else { return }
        if rightSettingsSheet.isHidden, playbackLibraryOverlay == .closed {
            showSettingsSheet()
        }
        selectVideoSettingsTab(index: index)
    }

    func commandStopAndClose() {
        guard activeMediaKind != .empty else { return }
        showEmptySurface()
    }

    func commandHandleEscapeKey() {
        guard activeMediaKind != .empty else { return }
        switch activeMediaKind {
        case .video:
            if isVideoPlaying {
                commandTogglePlayPause()
            } else {
                showEmptySurface()
            }
        case .image:
            showEmptySurface()
        case .empty:
            break
        }
    }

    func commandTogglePlayPause() {
        guard activeMediaKind == .video else { return }
        togglePlayPause()
    }

    func commandSeek(bySeconds seconds: Double) {
        guard activeMediaKind == .video else { return }
        let current: Double
        if mpvBackendActive, let session = activeSession {
            current = session.currentTimeSec
        } else {
            current = CMTimeGetSeconds(player.currentTime())
        }
        guard current.isFinite else { return }
        let maxSec = max(seekSlider.maxValue, 0)
        let targetSec = min(max(current + seconds, 0), maxSec > 0 ? maxSec : .greatestFiniteMagnitude)
        performCooperativeSeek(to: CMTime(seconds: targetSec, preferredTimescale: 600))
    }

    func commandSeekToStart() {
        guard activeMediaKind == .video else { return }
        performCooperativeSeek(to: .zero)
    }

    func commandSeekToEnd() {
        guard activeMediaKind == .video else { return }
        let end = seekSlider.maxValue
        guard end > 0 else { return }
        performCooperativeSeek(to: CMTime(seconds: end, preferredTimescale: 600))
    }

    func commandAdjustVolume(by delta: Float) {
        guard activeMediaKind == .video, audioOutputEnabled else { return }
        isUserVolumeMuted = false
        desiredPlaybackVolume = min(1, max(0, desiredPlaybackVolume + delta))
        volumeSlider.doubleValue = Double(desiredPlaybackVolume)
        applyEffectivePlaybackVolume()
        updateVolumeMuteButtonIcon()
    }

    func commandToggleMute() {
        guard activeMediaKind == .video else { return }
        volumeMuteButtonPressed()
    }

    func commandPlaybackQueuePrevious() {
        guard activeMediaKind == .video || activeMediaKind == .image else { return }
        guard !playbackHistory.isEmpty else { return }
        playPreviousInQueue()
    }

    func commandPlaybackQueueNext() {
        guard activeMediaKind == .video || activeMediaKind == .image else { return }
        playNextInQueue()
    }

    func commandStepPlaybackSpeed(by delta: Int) {
        guard activeMediaKind == .video else { return }
        stepPlaybackSpeed(by: delta)
    }

    func commandResetPlaybackSpeed() {
        guard activeMediaKind == .video else { return }
        applyPlaybackSpeed(1.0)
    }

    func commandToggleLoopPlayback() {
        guard activeMediaKind == .video else { return }
        let store = SettingsStore.shared
        store.loopPlaybackEnabled.toggle()
        loopPlaybackCheckbox.state = store.loopPlaybackEnabled ? .on : .off
    }

    func commandToggleVideoFitMode() {
        guard activeMediaKind == .video else { return }
        let store = SettingsStore.shared
        let next: VideoFitMode = store.videoFitMode == .fill ? .fit : .fill
        store.videoFitMode = next
        videoFitModeControl.selectedSegment = next == .fill ? 1 : 0
        applyVideoFitMode(next)
    }

    func commandCycleWindowAspectPreset() {
        guard activeMediaKind == .video else { return }
        let presets = WindowAspectPreset.selectablePresets
        let current = SettingsStore.shared.windowAspectPreset
        let nextIndex = (presets.firstIndex(of: current).map { $0 + 1 } ?? 0) % presets.count
        SettingsStore.shared.windowAspectPreset = presets[nextIndex]
        windowAspectControl.selectedSegment = nextIndex
        updateLockAspectControlAvailability()
        applyWindowAspectFromSettings()
    }

    func commandToggleLockAspect() {
        guard activeMediaKind == .video else { return }
        let store = SettingsStore.shared
        store.lockAspectRatioEnabled.toggle()
        lockAspectCheckbox.state = store.lockAspectRatioEnabled ? .on : .off
        applyWindowAspectFromSettings()
    }

    func commandTogglePlaybackSource() {
        guard activeMediaKind == .video else { return }
        guard playbackSourcePopUp.isEnabled, playbackSourcePopUp.numberOfItems > 1 else { return }
        let next = playbackSourcePopUp.indexOfSelectedItem == 0 ? 1 : 0
        playbackSourcePopUp.selectItem(at: next)
        playbackSourceChanged()
    }

    func commandStepAudioTrack(forward: Bool) {
        guard activeMediaKind == .video else { return }
        let count = audioSettings.trackPopUp.numberOfItems
        guard count > 2 else { return }
        var index = audioSettings.trackPopUp.indexOfSelectedItem
        if index < 0 { index = 1 }
        if forward {
            index = min(index + 1, count - 1)
        } else {
            index = max(index - 1, 1)
        }
        audioSettings.trackPopUp.selectItem(at: index)
        audioTrackPopUpChanged(audioSettings.trackPopUp)
    }

    func commandCycleEQPreset() {
        guard activeMediaKind == .video, mpvBackendActive, mpvPlaybackStarted else { return }
        let presets = PlaybackEQPreset.allCases
        let current = SettingsStore.shared.playbackEQPreset
        guard let idx = presets.firstIndex(of: current) else { return }
        let next = presets[(idx + 1) % presets.count]
        SettingsStore.shared.playbackEQPreset = next
        if next != .manual {
            SettingsStore.shared.playbackEQBands = next.bandGains
            audioSettings.loadBandsFromStore()
        }
        if let item = audioSettings.eqPresetPopUp.itemArray.first(where: {
            ($0.representedObject as? String) == next.rawValue
        }) {
            audioSettings.eqPresetPopUp.select(item)
        }
        applyPlaybackEQToActiveMpv()
    }

    func commandImageZoomIn() {
        guard activeMediaKind == .image else { return }
        imageZoomIn()
    }

    func commandImageZoomOut() {
        guard activeMediaKind == .image else { return }
        imageZoomOut()
    }

    func commandImageResetZoom() {
        guard activeMediaKind == .image else { return }
        imageFit()
    }

    func commandLibraryBrowseBack() {
        guard playbackLibraryOverlay == .sidebarAndBrowse else { return }
        mediaLibraryController.goBack()
    }

    func commandLibraryBrowseForward() {
        guard playbackLibraryOverlay == .sidebarAndBrowse else { return }
        mediaLibraryController.goForward()
    }

    func toggleQueuePopoverFromShortcut() {
        guard activeMediaKind == .video || activeMediaKind == .image else { return }
        toggleQueuePopover()
    }

    @discardableResult
    func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 {
            if keyboardFocusBlocksTransportShortcuts { return false }
            commandHandleEscapeKey()
            return activeMediaKind != .empty
        }

        if flags.contains(.command), event.charactersIgnoringModifiers == "." {
            commandStopAndClose()
            return true
        }

        if keyboardFocusBlocksTransportShortcuts, !flags.contains(.command) {
            return false
        }

        if flags == .command, event.charactersIgnoringModifiers == "l" {
            commandToggleLibraryPanel()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "i" {
            commandToggleSettingsInspector()
            return true
        }
        if flags == .command, let ch = event.charactersIgnoringModifiers, ch.count == 1, let tab = Int(String(ch)), (1...3).contains(tab) {
            commandSelectSettingsTab(tab - 1)
            return true
        }

        if flags == [.command, .option] {
            switch event.keyCode {
            case 123:
                if playbackLibraryOverlay == .sidebarAndBrowse {
                    commandLibraryBrowseBack()
                    return true
                }
                if activeMediaKind == .video {
                    commandStepAudioTrack(forward: false)
                    return true
                }
            case 124:
                if playbackLibraryOverlay == .sidebarAndBrowse {
                    commandLibraryBrowseForward()
                    return true
                }
                if activeMediaKind == .video {
                    commandStepAudioTrack(forward: true)
                    return true
                }
            default:
                break
            }
        }

        if flags == [.command, .option], event.charactersIgnoringModifiers == "e" {
            commandCycleEQPreset()
            return true
        }

        if flags == [.command, .shift], event.charactersIgnoringModifiers == "l" {
            commandToggleLoopPlayback()
            return true
        }
        if flags == [.command, .shift], event.charactersIgnoringModifiers == "u" {
            guard activeMediaKind == .video || activeMediaKind == .image else { return false }
            toggleQueuePopover()
            return true
        }
        if flags == [.command, .shift], event.charactersIgnoringModifiers == "k" {
            commandToggleLockAspect()
            return true
        }
        if flags == [.command, .shift], event.charactersIgnoringModifiers == "s" {
            commandTogglePlaybackSource()
            return true
        }

        if flags == [.control, .command], event.charactersIgnoringModifiers == "a" {
            commandCycleWindowAspectPreset()
            return true
        }

        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "=", "+":
                if activeMediaKind == .image {
                    commandImageZoomIn()
                    return true
                }
                if activeMediaKind == .video {
                    commandStepPlaybackSpeed(by: 1)
                    return true
                }
            case "-":
                if activeMediaKind == .image {
                    commandImageZoomOut()
                    return true
                }
                if activeMediaKind == .video {
                    commandStepPlaybackSpeed(by: -1)
                    return true
                }
            case "0":
                if activeMediaKind == .image {
                    commandImageResetZoom()
                    return true
                }
                if activeMediaKind == .video {
                    commandResetPlaybackSpeed()
                    return true
                }
            default:
                break
            }
        }

        if flags == .option, event.charactersIgnoringModifiers == "m" {
            commandToggleMute()
            return true
        }

        if flags.isEmpty {
            switch event.keyCode {
            case 49:
                if activeMediaKind == .video {
                    commandTogglePlayPause()
                    return true
                }
            case 123:
                if activeMediaKind == .video {
                    commandSeek(bySeconds: -Self.standardSeekSeconds)
                    return true
                }
            case 124:
                if activeMediaKind == .video {
                    commandSeek(bySeconds: Self.standardSeekSeconds)
                    return true
                }
            case 126:
                if activeMediaKind == .video {
                    commandAdjustVolume(by: Self.volumeStep)
                    return true
                }
            case 125:
                if activeMediaKind == .video {
                    commandAdjustVolume(by: -Self.volumeStep)
                    return true
                }
            case 115:
                if activeMediaKind == .video {
                    commandSeekToStart()
                    return true
                }
            case 119:
                if activeMediaKind == .video {
                    commandSeekToEnd()
                    return true
                }
            case 3:
                if activeMediaKind == .video {
                    commandToggleVideoFitMode()
                    return true
                }
            default:
                break
            }
        }

        if flags == .option {
            switch event.keyCode {
            case 123:
                if activeMediaKind == .video {
                    commandSeek(bySeconds: -Self.fineSeekSeconds)
                    return true
                }
            case 124:
                if activeMediaKind == .video {
                    commandSeek(bySeconds: Self.fineSeekSeconds)
                    return true
                }
            default:
                break
            }
        }

        return false
    }

    var keyboardFocusBlocksTransportShortcuts: Bool {
        guard let responder = view.window?.firstResponder else { return false }
        if responder is NSSlider || responder is NSTextField || responder is NSPopUpButton || responder is NSTextView {
            return true
        }
        return false
    }

    var isVideoPlaying: Bool {
        guard activeMediaKind == .video else { return false }
        if mpvBackendActive {
            return activeSession?.isPlaying == true
        }
        return player.rate > 0
    }
}

final class ImageSurfaceView: NSView {
    private let imageView = NSImageView()
    private(set) var naturalPixelSize: CGSize = .zero
    private(set) var zoomScale: CGFloat = 1.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var image: NSImage? {
        imageView.image
    }

    func setImage(_ image: NSImage, naturalSize: CGSize) {
        naturalPixelSize = naturalSize
        imageView.image = image
        zoomScale = 1.0
        needsLayout = true
    }

    func clearImage() {
        imageView.image = nil
        naturalPixelSize = .zero
        zoomScale = 1.0
        needsLayout = true
    }

    func resetZoom() {
        zoomScale = 1.0
        needsLayout = true
    }

    func setZoomScale(_ scale: CGFloat) {
        zoomScale = scale
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard naturalPixelSize.width > 0, naturalPixelSize.height > 0 else {
            imageView.frame = bounds
            return
        }

        let viewWidth = bounds.width
        let viewHeight = bounds.height
        guard viewWidth > 0, viewHeight > 0 else { return }

        let imageAspect = naturalPixelSize.width / naturalPixelSize.height
        let viewAspect = viewWidth / viewHeight

        var fitWidth: CGFloat
        var fitHeight: CGFloat
        if imageAspect > viewAspect {
            fitWidth = viewWidth
            fitHeight = viewWidth / imageAspect
        } else {
            fitHeight = viewHeight
            fitWidth = viewHeight * imageAspect
        }

        fitWidth *= zoomScale
        fitHeight *= zoomScale

        imageView.frame = NSRect(
            x: (viewWidth - fitWidth) / 2,
            y: (viewHeight - fitHeight) / 2,
            width: fitWidth,
            height: fitHeight
        )
    }
}

private enum PlaybackMiniPreviewMetrics {
    static let aspectRatio: CGFloat = 16 / 9
    static let compactWidth: CGFloat = 264
    static let mediumWidth: CGFloat = 336
    static let largeWidth: CGFloat = 432
    static let mediumBreakpoint: CGFloat = 1200
    static let largeBreakpoint: CGFloat = 1440

    static func preferredSize(forContentWidth width: CGFloat) -> NSSize {
        let previewWidth: CGFloat
        if width < mediumBreakpoint {
            previewWidth = compactWidth
        } else if width < largeBreakpoint {
            let progress = (width - mediumBreakpoint) / (largeBreakpoint - mediumBreakpoint)
            previewWidth = compactWidth + (mediumWidth - compactWidth) * progress
        } else {
            previewWidth = largeWidth
        }
        return NSSize(width: previewWidth, height: round(previewWidth / aspectRatio))
    }
}

final class PlaybackMiniPreviewView: NSView {
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?

    private let videoSurface = MiniPlayerSurfaceView()
    private let imageSurface = NSImageView()
    private let expandBackdrop = NSView()
    private let expandButton = NSButton()
    private let closeBackdrop = NSView()
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.black.cgColor

        videoSurface.translatesAutoresizingMaskIntoConstraints = false
        imageSurface.translatesAutoresizingMaskIntoConstraints = false
        imageSurface.imageScaling = .scaleProportionallyUpOrDown
        imageSurface.isHidden = true

        styleChromeBackdrop(expandBackdrop)
        styleChromeBackdrop(closeBackdrop)

        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.bezelStyle = .accessoryBarAction
        expandButton.isBordered = false
        expandButton.toolTip = "Return to full playback"
        expandButton.setButtonType(.momentaryPushIn)
        expandButton.target = self
        expandButton.action = #selector(expandClicked)
        if let image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Return to full playback") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            expandButton.image = image.withSymbolConfiguration(config)
            expandButton.contentTintColor = .white
        }

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.isBordered = false
        closeButton.toolTip = "Stop playback"
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Stop playback") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            closeButton.image = image.withSymbolConfiguration(config)
            closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        }

        addSubview(videoSurface)
        addSubview(imageSurface)
        addSubview(expandBackdrop)
        addSubview(expandButton)
        addSubview(closeBackdrop)
        addSubview(closeButton)

        videoSurface.onDoubleClick = { [weak self] in
            self?.expandClicked()
        }
        let imageDoubleClick = NSClickGestureRecognizer(target: self, action: #selector(expandClicked))
        imageDoubleClick.numberOfClicksRequired = 2
        imageSurface.addGestureRecognizer(imageDoubleClick)

        NSLayoutConstraint.activate([
            videoSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoSurface.topAnchor.constraint(equalTo: topAnchor),
            videoSurface.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageSurface.topAnchor.constraint(equalTo: topAnchor),
            imageSurface.bottomAnchor.constraint(equalTo: bottomAnchor),

            expandBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            expandBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            expandBackdrop.widthAnchor.constraint(equalToConstant: 26),
            expandBackdrop.heightAnchor.constraint(equalToConstant: 26),

            expandButton.centerXAnchor.constraint(equalTo: expandBackdrop.centerXAnchor),
            expandButton.centerYAnchor.constraint(equalTo: expandBackdrop.centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 26),
            expandButton.heightAnchor.constraint(equalToConstant: 26),

            closeBackdrop.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            closeBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeBackdrop.widthAnchor.constraint(equalToConstant: 26),
            closeBackdrop.heightAnchor.constraint(equalToConstant: 26),

            closeButton.centerXAnchor.constraint(equalTo: closeBackdrop.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: closeBackdrop.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 26),
            closeButton.heightAnchor.constraint(equalToConstant: 26)
        ])

        videoSurface.toolTip = "Double-click to return to full playback"
        imageSurface.toolTip = "Double-click to return to full playback"
    }

    private func styleChromeBackdrop(_ backdrop: NSView) {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 13
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        backdrop.layer?.borderWidth = 0.5
        backdrop.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === closeButton || hit === closeBackdrop {
            return closeButton
        }
        if hit === expandButton || hit === expandBackdrop {
            return expandButton
        }
        return hit
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showVideo(player: AVPlayer) {
        videoSurface.isHidden = false
        imageSurface.isHidden = true
        videoSurface.player = player
    }

    func detachVideoPlayer() {
        videoSurface.player = nil
    }

    func showImage(_ image: NSImage?) {
        videoSurface.isHidden = true
        videoSurface.player = nil
        imageSurface.isHidden = false
        imageSurface.image = image
    }

    func applyLayoutScale(forWidth width: CGFloat) {
        let scale = max(1, width / PlaybackMiniPreviewMetrics.compactWidth)
        layer?.cornerRadius = min(14, 10 * scale)
    }

    @objc private func expandClicked() {
        onExpand?()
    }

    @objc private func closeClicked(_ sender: Any?) {
        _ = sender
        onClose?()
    }
}

private final class HoverTextButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?
    var tabLabel: String = "" {
        didSet { updateTabAppearance() }
    }
    var uiScale: CGFloat = 1 {
        didSet { updateTabAppearance() }
    }
    var symbolName: String = "" {
        didSet { updateTabAppearance() }
    }
    var textColor: NSColor = .secondaryLabelColor {
        didSet { updateTabAppearance() }
    }
    private(set) var isHovered = false {
        didSet { onHoverChanged?(isHovered) }
    }

    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .inline
        imagePosition = .imageLeading
        imageHugsTitle = true
        alignment = .center
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 12, weight: .medium)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateTabAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private func updateTabAppearance() {
        let baseFont = NSFont.systemFont(ofSize: 12 * uiScale, weight: .medium)
        // Thin space between SF Symbol and label when imageHugsTitle groups them.
        let titleWithGap = "\u{2009}" + tabLabel
        title = titleWithGap
        attributedTitle = NSAttributedString(
            string: titleWithGap,
            attributes: [
                .foregroundColor: textColor,
                .font: baseFont
            ]
        )
        setAccessibilityLabel(tabLabel)
        contentTintColor = textColor
        imageHugsTitle = true
        imagePosition = .imageLeading
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: tabLabel) {
            let config = NSImage.SymbolConfiguration(pointSize: 11 * uiScale, weight: .medium)
            image = symbol.withSymbolConfiguration(config)
            image?.isTemplate = true
        } else {
            image = nil
        }
    }
}

private final class SettingsTabHeaderItemView: NSView {
    private static let activeUnderlineGap: CGFloat = 6

    private let tabButton: HoverTextButton
    private let activeUnderline = NSView()

    var isActive = false {
        didSet { activeUnderline.isHidden = !isActive }
    }

    init(button: HoverTextButton, showsSeparator: Bool) {
        tabButton = button
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        activeUnderline.translatesAutoresizingMaskIntoConstraints = false
        activeUnderline.wantsLayer = true
        activeUnderline.layer?.backgroundColor = LaughTheme.accent.cgColor
        activeUnderline.isHidden = true
        addSubview(activeUnderline)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            button.bottomAnchor.constraint(equalTo: activeUnderline.topAnchor, constant: -Self.activeUnderlineGap),
            activeUnderline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            activeUnderline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            activeUnderline.bottomAnchor.constraint(equalTo: bottomAnchor),
            activeUnderline.heightAnchor.constraint(equalToConstant: 2)
        ])

        if showsSeparator {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separator, positioned: .below, relativeTo: button)
            NSLayoutConstraint.activate([
                separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                separator.centerYAnchor.constraint(equalTo: centerYAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
                separator.heightAnchor.constraint(equalToConstant: 14)
            ])
        }
    }

    override func mouseDown(with event: NSEvent) {
        tabButton.performClick(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class MiniPlayerSurfaceView: NSView {
    var onDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyLetterboxBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        }
        super.mouseDown(with: event)
    }

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
            applyLetterboxBackground()
        }
    }

    private var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer backing layer.")
        }
        return layer
    }

    private func applyLetterboxBackground() {
        playerLayer.backgroundColor = NSColor.black.cgColor
    }
}

final class DragHostView: NSView {
    var readURLs: ((NSDraggingInfo) -> [URL])?
    var onPerformDrop: (([URL], NSPoint) -> Bool)?
    var onDragSessionActive: ((Bool) -> Void)?
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseEnteredView: (() -> Void)?
    var onMouseExitedView: (() -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var activeDragSessions = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyChromeBackdrop()
        registerForDraggedTypes([.fileURL])
    }

    func setPlaybackBackdropActive(_ active: Bool) {
        layer?.backgroundColor = active ? NSColor.black.cgColor : NSColor.windowBackgroundColor.cgColor
    }

    private func applyChromeBackdrop() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let urls = readURLs?(sender), !urls.isEmpty else { return [] }
        if activeDragSessions == 0 {
            onDragSessionActive?(true)
        }
        activeDragSessions += 1
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        endDragSessionIfNeeded()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        endDragSessionIfNeeded()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = readURLs?(sender) else { return false }
        return !urls.isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = readURLs?(sender), !urls.isEmpty else { return false }
        let locationInView = convert(sender.draggingLocation, from: nil)
        let accepted = onPerformDrop?(urls, locationInView) ?? false
        endDragSessionIfNeeded()
        return accepted
    }

    private func endDragSessionIfNeeded() {
        guard activeDragSessions > 0 else { return }
        activeDragSessions = 0
        onDragSessionActive?(false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnteredView?()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedView?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
}

final class PlayerSurfaceView: NSView {
    var onMpvLayoutChanged: (() -> Void)?
    private var mpvEmbeddingActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyLetterboxBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    override func layout() {
        super.layout()
        if mpvEmbeddingActive {
            onMpvLayoutChanged?()
        }
    }

    /// Cocoa `--wid` expects an `NSView` pointer encoded as intptr_t.
    var mpvEmbeddingWindowID: Int {
        guard mpvEmbeddingActive else { return 0 }
        return Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    }

    func setMpvEmbeddingActive(_ active: Bool) {
        mpvEmbeddingActive = active
        if active {
            playerLayer.player = nil
            layer?.opacity = 0.001
        } else {
            layer?.opacity = 1
        }
        applyLetterboxBackground()
    }

    var player: AVPlayer? {
        get { mpvEmbeddingActive ? nil : playerLayer.player }
        set {
            guard !mpvEmbeddingActive else { return }
            playerLayer.player = newValue
        }
    }

    var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set { playerLayer.videoGravity = newValue }
    }

    private var playerLayer: AVPlayerLayer {
        guard let layer = self.layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer backing layer.")
        }
        return layer
    }

    private func applyLetterboxBackground() {
        playerLayer.backgroundColor = NSColor.black.cgColor
    }
}

private enum PlaybackSpeedSteps {
    /// Quarter-step speeds from 0.5× through 2× (seven stops).
    static let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    static func index(for rate: Float) -> Int {
        nearestRateIndex(to: rate)
    }

    static func rate(for index: Int) -> Float {
        rates[max(0, min(index, rates.count - 1))]
    }

    static func nearestRate(to speed: Float) -> Float {
        rates[nearestRateIndex(to: speed)]
    }

    private static func nearestRateIndex(to speed: Float) -> Int {
        var bestIndex = 0
        var bestDelta = Float.greatestFiniteMagnitude
        for (index, candidate) in rates.enumerated() {
            let delta = abs(candidate - speed)
            if delta < bestDelta {
                bestDelta = delta
                bestIndex = index
            }
        }
        return bestIndex
    }
}

final class QueueDropZoneView: NSView {
    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "Drop Here To Queue")
        field.alignment = .center
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.textColor = .secondaryLabelColor
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor

        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func flashAccepted() {
        guard let layer else { return }
        let oldColor = layer.backgroundColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            layer.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.35).cgColor
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                layer.backgroundColor = oldColor
            }
        }
    }
}

