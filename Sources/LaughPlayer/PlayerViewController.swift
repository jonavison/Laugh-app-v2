import AppKit
import AVKit
import AVFoundation
import CoreMedia

protocol PlayerViewControllerDelegate: AnyObject {
    func playerViewController(_ controller: PlayerViewController, didRequestWindowAspectRatio ratio: CGFloat?)
    func playerViewControllerDidRequestOpenVideo(_ controller: PlayerViewController)
    func playerViewControllerDidRequestOpenSettings(_ controller: PlayerViewController)
}

final class PlayerViewController: NSViewController, MediaLibraryDelegate {
    private static let optimisticFallbackCodecs: Set<String> = ["1veh", "hev1"]
    /// Codecs macOS plays natively — do not run black-frame probes or ffmpeg on these.
    private static let nativeVideoCodecs: Set<String> = [
        "avc1", "h264", "x264", "1cva", "mp4v", "hvc1", "1cvh", "hev1", "1dvh"
    ]

    weak var delegate: PlayerViewControllerDelegate?

    private let player = AVPlayer()
    private let playerSurfaceView = PlayerSurfaceView()
    private let queueDropZone = QueueDropZoneView()
    private let dragHostView = DragHostView()
    private let openButton = NSButton(title: "Open Media", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "Drop video or image to open. Drop video in bottom-right to queue.")
    private let imageSurfaceView = ImageSurfaceView()
    private let controlsContainer = NSVisualEffectView()
    private let imageControlsContainer = NSVisualEffectView()
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
    private var imageBarWidthConstraint: NSLayoutConstraint?
    private let transportSpeedLeftCluster = NSStackView()
    private let transportSpeedLeftSpacer = NSView()
    private let playbackSpeedSlowLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton(title: "Previous", target: nil, action: nil)
    private let playPauseButton = NSButton(title: "Play", target: nil, action: nil)
    private let transportSpeedRightCluster = NSStackView()
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let playbackSpeedFastLabel = NSTextField(labelWithString: "")
    private let transportSpeedRightSpacer = NSView()
    private let queueButton = NSButton(title: "Queue", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let libraryButton = NSButton(title: "Library", target: nil, action: nil)
    private let mediaLibraryController = MediaLibraryController()
    private lazy var librarySidebar = LibrarySidebarView(controller: mediaLibraryController)
    private lazy var libraryBrowse = LibraryBrowseView(controller: mediaLibraryController)
    private let playbackMiniPreview = PlaybackMiniPreviewView()
    private let rightSettingsSheet = NSVisualEffectView()
    private let videoSettingsTabsRow = NSStackView()
    private let imageSettingsTabsRow = NSStackView()
    private var videoSettingsTabButtons: [HoverTextButton] = []
    private var imageSettingsTabButtons: [HoverTextButton] = []
    private var selectedVideoSettingsTabIndex = 0
    private var selectedImageSettingsTabIndex = 0
    private let settingsContentContainer = NSView()
    private let videoTabView = NSStackView()
    private let audioTabView = NSStackView()
    private let subtitlesTabView = NSStackView()
    private let imageTabView = NSStackView()
    private let imageFitTabView = NSStackView()
    private var activeMediaKind: ActiveMediaKind = .empty
    private let seekSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let currentTimeLabel = NSTextField(labelWithString: "00:00")
    private let totalTimeLabel = NSTextField(labelWithString: "00:00")
    private let videoFormatLabel = NSTextField(labelWithString: "Format: --")
    private let aspectRatioLabel = NSTextField(labelWithString: "Aspect: --")
    private let videoTrackLabel = NSTextField(labelWithString: "Tracks: --")
    private let audioInfoLabel = NSTextField(labelWithString: "Audio: --")
    private let sourceFileLabel = NSTextField(labelWithString: "File: --")
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
    private var queue: [URL] = []
    private var playbackHistory: [URL] = []
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
    private var fallbackSessionToken: Int = 0
    private var lastLoadRequestURL: String?
    private var lastLoadRequestAt: CFAbsoluteTime = 0
    private var lastLikelyToKeepUp: Bool?
    private var lastBufferEmpty: Bool?
    private var lastBufferFull: Bool?
    private var desiredPlaybackVolume: Float = 1.0
    private var volumeRampToken: Int = 0
    private var isMutedForSwitch: Bool = false
    private var pendingVideoLoadWorkItem: DispatchWorkItem?
    private var committedPlayerItemID: ObjectIdentifier?
    private let baseSettingsPanelWidth: CGFloat = 320
    private let baseLibrarySidebarWidth: CGFloat = LibrarySidebarView.width
    private var librarySidebarWidthConstraint: NSLayoutConstraint?
    private var settingsPanelWidthConstraint: NSLayoutConstraint?
    private var volumeSliderWidthConstraint: NSLayoutConstraint?
    private var playbackTopRowLayoutConfigured = false
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
    private let settingsContentBottomClearance: CGFloat = 108

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
        prepareInterfaceForDisplay()
    }

    /// Ensures the library empty state is laid out once the window has a real size.
    func prepareInterfaceForDisplay() {
        guard view.window != nil else { return }
        installPlayerInterfaceIfNeeded()
        installLibraryChromeIfNeeded()
        if activeMediaKind == .empty {
            showFullMediaLibrary()
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
        player.actionAtItemEnd = .pause
        if #available(macOS 12.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        playerSurfaceView.videoGravity = .resizeAspect
        playerSurfaceView.translatesAutoresizingMaskIntoConstraints = false
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

        settingsContentContainer.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(settingsContentContainer)

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
        transportSpeedLeftCluster.addArrangedSubview(previousButton)

        transportSpeedRightCluster.orientation = .horizontal
        transportSpeedRightCluster.alignment = .centerY
        transportSpeedRightCluster.spacing = 1
        transportSpeedRightCluster.addArrangedSubview(nextButton)
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
        playbackCenterClusterStack.distribution = .equalSpacing
        playbackCenterClusterStack.spacing = playbackControlClusterSpacing

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

        let initialBarWidth = MusicStylePlaybackBar.preferredBarWidth(forContentWidthPoints: 960)
        playbackBarWidthConstraint = controlsContainer.widthAnchor.constraint(equalToConstant: initialBarWidth)
        imageBarWidthConstraint = imageControlsContainer.widthAnchor.constraint(equalToConstant: min(420, initialBarWidth))
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
            controlsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -MusicStylePlaybackBar.barBottomInset),
            controlsContainer.heightAnchor.constraint(equalToConstant: 76),
            playbackBarWidthConstraint!,

            imageControlsContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageControlsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -MusicStylePlaybackBar.barBottomInset),
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

            videoSettingsTabsRow.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor, constant: settingsPanelInnerInset + 4),
            videoSettingsTabsRow.centerXAnchor.constraint(equalTo: rightSettingsSheet.centerXAnchor),
            videoSettingsTabsRow.leadingAnchor.constraint(greaterThanOrEqualTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset + 2),
            videoSettingsTabsRow.trailingAnchor.constraint(lessThanOrEqualTo: rightSettingsSheet.trailingAnchor, constant: -(settingsPanelInnerInset + 2)),

            imageSettingsTabsRow.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor, constant: settingsPanelInnerInset + 4),
            imageSettingsTabsRow.centerXAnchor.constraint(equalTo: rightSettingsSheet.centerXAnchor),
            imageSettingsTabsRow.leadingAnchor.constraint(greaterThanOrEqualTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset + 2),
            imageSettingsTabsRow.trailingAnchor.constraint(lessThanOrEqualTo: rightSettingsSheet.trailingAnchor, constant: -(settingsPanelInnerInset + 2)),

            settingsContentContainer.topAnchor.constraint(equalTo: videoSettingsTabsRow.bottomAnchor, constant: settingsPanelInnerInset + 14),
            settingsContentContainer.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset),
            settingsContentContainer.trailingAnchor.constraint(equalTo: rightSettingsSheet.trailingAnchor, constant: -settingsPanelInnerInset)
        ])

        settingsContentBottomConstraint = settingsContentContainer.bottomAnchor.constraint(
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
            let shouldQueue = self.queueDropZone.frame.contains(locationInView)
            return self.handleDroppedURLs(urls, queueOnly: shouldQueue)
        }
        dragHostView.onDragSessionActive = { [weak self] active in
            self?.setQueueDropZoneVisibleForDrag(active)
        }
        dragHostView.onMouseMoved = { [weak self] point in
            self?.handleMouseMoved(point)
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
                self.updateTimelineUI()
            }
        }

        updateSettingsContentBottomInset()
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
        playbackMiniPreview.isHidden = true
        playbackMiniPreview.translatesAutoresizingMaskIntoConstraints = false
        playbackMiniPreview.onExpand = { [weak self] in
            self?.collapsePlaybackLibraryOverlay()
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

            playbackMiniPreview.widthAnchor.constraint(equalToConstant: 264),
            playbackMiniPreview.heightAnchor.constraint(equalToConstant: 148),
            playbackMiniPreview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playbackMiniPreview.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        raisePlaybackChromeToFront()
    }

    func loadVideo(url: URL, replaceCurrent: Bool = true, startAt: CMTime? = nil) {
        pendingVideoLoadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performLoadVideo(url: url, replaceCurrent: replaceCurrent, startAt: startAt)
        }
        pendingVideoLoadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func performLoadVideo(url: URL, replaceCurrent: Bool, startAt: CMTime?) {
        let now = CFAbsoluteTimeGetCurrent()
        let samePath = lastLoadRequestURL == url.path
        if samePath, (now - lastLoadRequestAt) < 0.35 {
            print("[DEBUG-playback] skipped duplicate load request path=\(url.path)")
            return
        }
        if fallbackInProgress, currentMediaURL?.standardizedFileURL == url.standardizedFileURL {
            print("[DEBUG-fallback] ignored load; conversion already running for \(url.lastPathComponent)")
            return
        }
        if !isGeneratedFallbackURL(url), isActivelyPlayingSource(url) {
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
            FFmpegVideoFallback.terminateRunningProcesses()
            print("[DEBUG-fallback] invalidated due to switch to \(url.lastPathComponent)")
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

        if replaceCurrent, let previousMediaURL, !isGeneratedFallbackURL(previousMediaURL) {
            playbackHistory.append(previousMediaURL)
        }

        preparePlayerForVideoSwitch()

        Task {
            let result = await VideoAssetLoader.resolvePlayableAsset(for: url)
            let preflightCodec = await Self.probePrimaryVideoFourCC(assetResult: result)
            await MainActor.run {
                guard generation == self.videoLoadGeneration else { return }
                switch result {
                case .success(let asset):
                    if self.shouldPreferOptimisticFallback(codec: preflightCodec),
                       !self.isGeneratedFallbackURL(url) {
                        if let cached = FFmpegVideoFallback.cachedPlayableURL(for: url) {
                            print("[DEBUG-fallback] optimistic cache hit path=\(url.path)")
                            self.resolveAndAttach(playableURL: cached, sourceURL: url, generation: generation)
                            return
                        }
                        if let preflightCodec {
                            print("[DEBUG-fallback] optimistic route codec=\(preflightCodec) path=\(url.path)")
                            self.showCompatibilityFailure(
                                "Detected codec \(preflightCodec). Routing directly to bundled compatibility decoder."
                            )
                        }
                        self.attemptFFmpegFallbackIfNeeded()
                        return
                    }
                    self.attachResolvedVideo(asset: asset, url: url, generation: generation)
                case .failure(let failure):
                    print("[DEBUG-playback] open failed: \(failure.debugDetails)")
                    self.showCompatibilityFailure(failure.userMessage)
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
        showVideoChrome(hideOpenHint: false)
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
        showVideoChrome(hideOpenHint: true)

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
                self.startPlaybackAtPreferredRate()
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
                self.updateTimelineUI()
                if self.shouldMonitorVideoRendering(codec: self.lastVideoCodecFourCC) {
                    self.renderMonitor.videoCodecFourCC = self.lastVideoCodecFourCC
                    self.renderMonitor.beginMonitoring(player: self.player, item: item) { [weak self] message in
                        self?.handleRenderFailure(message)
                    }
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
    private func performCooperativeSeek(
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
        if let currentMediaURL {
            playbackHistory.append(currentMediaURL)
        }
        currentMediaURL = url
        playbackSourceURL = nil
        activePlaybackFileURL = nil
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
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let timeString = currentTime.isFinite ? String(format: "%.2fs", currentTime) : "Unknown"
        let rateString = String(format: "%.2f", player.rate)
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
        renderMonitor.reset()
        endSecurityScopedAccess()
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
                    message += "\n\nThis MKV may use a codec macOS cannot decode natively (common with HEVC 10-bit). Try remuxing to MP4 with ffmpeg -c copy -tag:v hvc1."
                }
                self.showCompatibilityFailure(message)
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func appendToQueue(_ urls: [URL]) {
        let videos = MediaKindDetector.filterVideos(urls)
        let skipped = urls.count - videos.count
        if videos.isEmpty {
            showUnsupportedFileMessage("Queue accepts videos only. Drop images in the main area.")
            return
        }
        if skipped > 0 {
            showCodecWarning("Skipped \(skipped) non-video file(s). Queue is video-only.")
        }
        queue.append(contentsOf: videos)
        if activeMediaKind == .video {
            rebuildControlsForTier(currentControlTier)
        }
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

    private func showEmptySurface() {
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
        hideSettingsSheet()
        showFullMediaLibrary()
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        raisePlaybackChromeToFront()
    }

    private func showVideoChrome(hideOpenHint: Bool) {
        activeMediaKind = .video
        hideMediaLibrary()
        imageSurfaceView.isHidden = true
        connectPlayerToVideoSurfaces()
        playerSurfaceView.isHidden = false
        controlsContainer.isHidden = false
        imageControlsContainer.isHidden = true
        openButton.isHidden = hideOpenHint
        hintLabel.isHidden = hideOpenHint
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        raisePlaybackChromeToFront()
        updatePlaybackBarWidth()
        applyResponsiveControlsLayout()
    }

    private func showImageChrome() {
        activeMediaKind = .image
        hideMediaLibrary()
        imageSurfaceView.isHidden = false
        playerSurfaceView.isHidden = true
        controlsContainer.isHidden = true
        imageControlsContainer.isHidden = false
        openButton.isHidden = true
        hintLabel.isHidden = true
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        raisePlaybackChromeToFront()
        updatePlaybackBarWidth()
    }

    private func setQueueDropZoneVisibleForDrag(_ visible: Bool) {
        let shouldHide = !visible
        guard queueDropZone.isHidden != shouldHide else { return }
        queueDropZone.isHidden = shouldHide
        if visible {
            raisePlaybackChromeToFront()
        }
    }

    private func styleRightSettingsPanel() {
        rightSettingsSheet.material = .menu
        rightSettingsSheet.blendingMode = .behindWindow
        rightSettingsSheet.state = .active
        rightSettingsSheet.wantsLayer = true
        rightSettingsSheet.layer?.cornerRadius = 0
        rightSettingsSheet.layer?.masksToBounds = false
        rightSettingsSheet.layer?.borderWidth = 0
        rightSettingsSheet.layer?.borderColor = nil
        rightSettingsSheet.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor
        rightSettingsSheet.layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        rightSettingsSheet.layer?.shadowOpacity = 1
        rightSettingsSheet.layer?.shadowRadius = 16
        rightSettingsSheet.layer?.shadowOffset = NSSize(width: -3, height: 0)
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
            action: #selector(videoSettingsTabPressed(_:))
        )
        buildSettingsTabButtons(
            titlesAndSymbols: [("Image", "slider.horizontal.3"), ("Fit & Zoom", "arrow.up.left.and.arrow.down.right")],
            in: imageSettingsTabsRow,
            storage: &imageSettingsTabButtons,
            action: #selector(imageSettingsTabPressed(_:))
        )
        applySettingsTabButtonState()
    }

    private func buildSettingsTabButtons(
        titlesAndSymbols: [(String, String)],
        in row: NSStackView,
        storage: inout [HoverTextButton],
        action: Selector
    ) {
        row.arrangedSubviews.forEach { view in
            row.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        storage.removeAll()

        for (index, payload) in titlesAndSymbols.enumerated() {
            let button = HoverTextButton()
            button.title = payload.0
            button.symbolName = payload.1
            button.tag = index
            button.target = self
            button.action = action
            button.onHoverChanged = { [weak self] _ in
                self?.applySettingsTabButtonState()
            }
            storage.append(button)
            let item = SettingsTabHeaderItemView(button: button, showsSeparator: index < titlesAndSymbols.count - 1)
            row.addArrangedSubview(item)
        }
    }

    private func applySettingsTabButtonState() {
        let baseColor = NSColor.secondaryLabelColor
        let hoverColor = NSColor.labelColor.withAlphaComponent(0.78)
        let activeColor = NSColor.labelColor

        for (index, button) in videoSettingsTabButtons.enumerated() {
            let color = index == selectedVideoSettingsTabIndex ? activeColor : (button.isHovered ? hoverColor : baseColor)
            button.textColor = color
            button.fontWeight = index == selectedVideoSettingsTabIndex ? .semibold : .medium
        }

        for (index, button) in imageSettingsTabButtons.enumerated() {
            let color = index == selectedImageSettingsTabIndex ? activeColor : (button.isHovered ? hoverColor : baseColor)
            button.textColor = color
            button.fontWeight = index == selectedImageSettingsTabIndex ? .semibold : .medium
        }
    }

    private func raisePlaybackChromeToFront() {
        view.addSubview(controlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
        view.addSubview(imageControlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
        view.addSubview(queueDropZone, positioned: .above, relativeTo: rightSettingsSheet)
        if libraryChromeInstalled {
            if !openButton.isHidden {
                view.addSubview(openButton, positioned: .above, relativeTo: libraryBrowse)
                view.addSubview(hintLabel, positioned: .above, relativeTo: libraryBrowse)
            }
            view.addSubview(librarySidebar, positioned: .above, relativeTo: playerSurfaceView)
            view.addSubview(libraryBrowse, positioned: .above, relativeTo: playerSurfaceView)
            view.addSubview(playbackMiniPreview, positioned: .above, relativeTo: libraryBrowse)
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
        applyUIScaleIfNeeded()
        updatePlaybackBarWidth()
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

    private static func probePrimaryVideoFourCC(assetResult: VideoAssetLoader.ResolveResult) async -> String? {
        guard case .success(let asset) = assetResult else { return nil }
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let formatDesc = formatDescriptions.first else { return nil }
            let code = CMFormatDescriptionGetMediaSubType(formatDesc)
            return fourCCStringStatic(code)
        } catch {
            return nil
        }
    }

    private static func fourCCStringStatic(_ code: FourCharCode) -> String {
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

    private func shouldPreferOptimisticFallback(codec: String?) -> Bool {
        guard let codec else { return false }
        return Self.optimisticFallbackCodecs.contains(codec.lowercased())
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

    private func attemptFFmpegFallbackIfNeeded() {
        guard !fallbackInProgress else { return }
        guard let inputURL = currentMediaURL else { return }
        guard !isGeneratedFallbackURL(inputURL) else { return }
        if let cached = FFmpegVideoFallback.cachedPlayableURL(for: inputURL) {
            print("[DEBUG-fallback] using cached remux path=\(cached.path)")
            let generation = videoLoadGeneration
            resolveAndAttach(playableURL: cached, sourceURL: inputURL, generation: generation)
            return
        }
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
        FFmpegVideoFallback.terminateRunningProcesses()
        fallbackInProgress = true
        fallbackSessionToken += 1
        let sessionToken = fallbackSessionToken
        let resumeTime = currentPlayerItemMatchesSource(inputURL) ? player.currentTime() : .zero
        let rawResumeTargetSec = CMTimeGetSeconds(resumeTime)
        let resumeTargetSec = rawResumeTargetSec.isFinite ? max(0, rawResumeTargetSec) : 0
        fallbackStartedAt = CFAbsoluteTimeGetCurrent()
        fallbackResumeTargetSec = rawResumeTargetSec.isFinite ? max(0, rawResumeTargetSec) : nil
        fallbackLastMethod = nil
        updatePlayPauseButtonIcon()
        showCompatibilityFailure("Trying compatibility fallback decoder...\n\nConverting this file for playback.")
        print(String(format: "[DEBUG-fallback] started for %@ at %.3fs", inputURL.path, resumeTargetSec))

        Task.detached(priority: .userInitiated) {
            let result = FFmpegVideoFallback.convertToPlayable(inputURL: inputURL)
            await MainActor.run {
                guard sessionToken == self.fallbackSessionToken else {
                    print("[DEBUG-fallback] ignored stale conversion result (session mismatch)")
                    return
                }
                self.fallbackInProgress = false
                guard let result else {
                    print("[DEBUG-fallback] conversion failed for \(inputURL.path)")
                    self.showCompatibilityFailure(
                        "Native playback failed and fast remux fallback could not convert this file.\n\nHeavy transcode is disabled by default to avoid high CPU spikes."
                    )
                    self.fallbackStartedAt = nil
                    self.fallbackResumeTargetSec = nil
                    self.fallbackLastMethod = nil
                    return
                }
                self.fallbackLastMethod = result.method
                print(String(format: "[DEBUG-fallback] conversion succeeded method=%@ conversion=%.2fms output=%@", result.method, result.elapsedMs, result.outputURL.path))
                self.fallbackConvertedOutputPaths.insert(result.outputURL.path)
                self.showCompatibilityFailure("Opened with compatibility fallback (\(result.method)).")
                if rawResumeTargetSec.isFinite && rawResumeTargetSec >= 0 {
                    self.pendingStartTimeAfterLoad = resumeTime
                }
                let generation = self.videoLoadGeneration
                self.resolveAndAttach(
                    playableURL: result.outputURL,
                    sourceURL: inputURL,
                    generation: generation
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
        styleIconButton(imageSettingsButton, symbol: "gearshape", label: "Settings")
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
        imageControlsStack.addArrangedSubview(imageSettingsButton)
    }

    private func configureControls() {
        styleIconButton(previousButton, symbol: "backward.fill", label: "Slower", pointSize: 13)
        styleIconButton(nextButton, symbol: "forward.fill", label: "Faster", pointSize: 13)
        configureTransportSpeedLabel(playbackSpeedSlowLabel, alignment: .right)
        configureTransportSpeedLabel(playbackSpeedFastLabel, alignment: .left)
        styleIconButton(queueButton, symbol: "list.bullet", label: "Queue")
        styleIconButton(settingsButton, symbol: "gearshape", label: "Settings")
        styleIconButton(libraryButton, symbol: "folder", label: "Library")
        queueButton.isHidden = true

        playPauseButton.bezelStyle = .accessoryBarAction
        playPauseButton.isBordered = false
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        playPauseButton.setButtonType(.momentaryPushIn)
        pinTransportIconButtonSize(playPauseButton, width: 32, height: 28)
        pinTransportIconButtonSize(previousButton)
        pinTransportIconButtonSize(nextButton)
        updatePlayPauseButtonIcon()

        previousButton.target = self
        nextButton.target = self
        queueButton.target = self
        settingsButton.target = self
        libraryButton.target = self
        previousButton.action = #selector(previousPressed)
        nextButton.action = #selector(nextPressed)
        queueButton.action = #selector(queuePressed)
        settingsButton.action = #selector(settingsPressed)
        libraryButton.action = #selector(libraryPressed)

        seekSlider.target = self
        seekSlider.action = #selector(seekSliderChanged)
        seekSlider.isContinuous = false
        seekSlider.controlSize = .mini

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged)
        volumeSlider.controlSize = .mini
        volumeSliderWidthConstraint = volumeSlider.widthAnchor.constraint(equalToConstant: 58)
        volumeSliderWidthConstraint?.isActive = true
        volumeSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        volumeSlider.setContentHuggingPriority(.required, for: .horizontal)
        setupPlaybackTopRowLayout()
        player.volume = 1
        player.isMuted = false
        desiredPlaybackVolume = 1

        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        currentTimeLabel.textColor = .secondaryLabelColor
        currentTimeLabel.alignment = .right
        totalTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        totalTimeLabel.textColor = .secondaryLabelColor
        totalTimeLabel.alignment = .left
        currentTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        seekSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for label in [videoFormatLabel, aspectRatioLabel, videoTrackLabel, audioInfoLabel, sourceFileLabel] {
            styleSettingsInfoLabel(label)
        }
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
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
        }

        videoTabView.addArrangedSubview(makeSettingsSectionHeader("Source"))
        videoTabView.addArrangedSubview(makeSettingsLabeledRow(title: "Play from", control: playbackSourcePopUp))
        sourceFileLabel.lineBreakMode = .byTruncatingMiddle
        sourceFileLabel.maximumNumberOfLines = 2
        videoTabView.addArrangedSubview(sourceFileLabel)
        videoTabView.addArrangedSubview(videoFormatLabel)
        videoTabView.addArrangedSubview(aspectRatioLabel)
        videoTabView.addArrangedSubview(videoTrackLabel)
        videoTabView.addArrangedSubview(audioInfoLabel)

        videoTabView.addArrangedSubview(makeSettingsSectionHeader("Playback"))
        videoTabView.addArrangedSubview(makePlaybackSpeedRow())
        videoTabView.addArrangedSubview(loopPlaybackCheckbox)

        videoTabView.addArrangedSubview(makeSettingsSectionHeader("Display"))
        videoTabView.addArrangedSubview(makeSettingsSegmentedRow(title: "Scale", control: videoFitModeControl))
        videoTabView.addArrangedSubview(makeSettingsSegmentedRow(title: "Aspect", control: windowAspectControl))
        videoTabView.addArrangedSubview(lockAspectCheckbox)

        let audioTitle = NSTextField(labelWithString: "Audio Settings")
        audioTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let audioHint = NSTextField(labelWithString: "Track selection and output options will appear here.")
        audioHint.textColor = .secondaryLabelColor
        audioHint.maximumNumberOfLines = 0
        audioTabView.addArrangedSubview(audioTitle)
        audioTabView.addArrangedSubview(audioHint)

        let subtitlesTitle = NSTextField(labelWithString: "Subtitles Settings")
        subtitlesTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let subtitlesHint = NSTextField(labelWithString: "Subtitle track and style options will appear here.")
        subtitlesHint.textColor = .secondaryLabelColor
        subtitlesHint.maximumNumberOfLines = 0
        subtitlesTabView.addArrangedSubview(subtitlesTitle)
        subtitlesTabView.addArrangedSubview(subtitlesHint)

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
            stack.spacing = 10
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

        updateSettingsTabVisibility()
    }

    private func updateSettingsTabVisibility() {
        videoTabView.isHidden = true
        audioTabView.isHidden = true
        subtitlesTabView.isHidden = true
        imageTabView.isHidden = true
        imageFitTabView.isHidden = true

        switch activeMediaKind {
        case .video:
            let index = selectedVideoSettingsTabIndex
            videoTabView.isHidden = index != 0
            audioTabView.isHidden = index != 1
            subtitlesTabView.isHidden = index != 2
        case .image:
            let index = selectedImageSettingsTabIndex
            imageTabView.isHidden = index != 0
            imageFitTabView.isHidden = index != 1
        case .empty:
            break
        }
    }

    private func updateVideoInfoLabels() {
        if let source = playbackSourceURL ?? currentMediaURL {
            sourceFileLabel.stringValue = source.path
        } else {
            sourceFileLabel.stringValue = "—"
        }
        refreshPlaybackSourceOptions()

        let codec = lastVideoCodecFourCC ?? "—"
        if let size = lastVideoSize {
            videoFormatLabel.stringValue = "\(codec) · \(Int(size.width))×\(Int(size.height))"
            let ratio = size.width / max(size.height, 1)
            aspectRatioLabel.stringValue = "Detected: \(formattedAspectRatioName(ratio))"
        } else {
            videoFormatLabel.stringValue = codec
            aspectRatioLabel.stringValue = "Detected: —"
        }

        videoTrackLabel.stringValue = "Video: \(lastVideoTrackSummary)"
        audioInfoLabel.stringValue = "Audio: \(lastAudioSummary)"
    }

    private func configureVideoSettingsControls() {
        playbackSourcePopUp.target = self
        playbackSourcePopUp.action = #selector(playbackSourceChanged)
        playbackSourcePopUp.controlSize = .small

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
        guard let source = playbackSourceURL ?? currentMediaURL else {
            playbackSourcePopUp.addItem(withTitle: "—")
            playbackSourcePopUp.isEnabled = false
            return
        }

        playbackSourcePopUp.addItem(withTitle: "Original file")
        if let cached = FFmpegVideoFallback.cachedPlayableURL(for: source),
           cached.standardizedFileURL != source.standardizedFileURL,
           FileManager.default.fileExists(atPath: cached.path) {
            playbackSourcePopUp.addItem(withTitle: "Compatibility copy")
        }

        playbackSourcePopUp.isEnabled = playbackSourcePopUp.numberOfItems > 1
        suppressPlaybackSourceAction = true
        if isPlayingFromCompatibilityCopy(for: source) {
            playbackSourcePopUp.selectItem(at: min(1, playbackSourcePopUp.numberOfItems - 1))
        } else {
            playbackSourcePopUp.selectItem(at: 0)
        }
        suppressPlaybackSourceAction = false
    }

    private func isPlayingFromCompatibilityCopy(for source: URL) -> Bool {
        guard let active = activePlaybackFileURL else { return false }
        if isGeneratedFallbackURL(active) { return true }
        if let cached = FFmpegVideoFallback.cachedPlayableURL(for: source) {
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

    private func applyPlaybackSpeed(_ speed: Float, persist: Bool = true) {
        let rate = PlaybackSpeedSteps.nearestRate(to: speed)
        let index = PlaybackSpeedSteps.index(for: rate)
        playbackSpeedSlider.integerValue = index
        playbackSpeedValueLabel.stringValue = formattedPlaybackSpeed(rate)
        preferredPlaybackRate = rate
        player.defaultRate = rate
        if persist {
            SettingsStore.shared.playbackSpeed = rate
        }
        if player.rate > 0 {
            player.rate = rate
        }
        updatePlaybackSpeedTransportLabels()
    }

    private func stepPlaybackSpeed(by delta: Int) {
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
            playbackSpeedSlowLabel.stringValue = formattedPlaybackSpeed(preferredPlaybackRate)
            playbackSpeedSlowLabel.alphaValue = 1
        } else {
            playbackSpeedSlowLabel.stringValue = ""
            playbackSpeedSlowLabel.alphaValue = 0
        }

        if isFastSpeed {
            playbackSpeedFastLabel.stringValue = formattedPlaybackSpeed(preferredPlaybackRate)
            playbackSpeedFastLabel.alphaValue = 1
        } else {
            playbackSpeedFastLabel.stringValue = ""
            playbackSpeedFastLabel.alphaValue = 0
        }

        previousButton.isEnabled = index > 0
        nextButton.isEnabled = index < PlaybackSpeedSteps.rates.count - 1

        if isNormalSpeed {
            previousButton.alphaValue = 1
            nextButton.alphaValue = 1
        }
    }

    private func styleSettingsInfoLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
    }

    private func makeSettingsSectionHeader(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title.uppercased())
        field.font = .systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .tertiaryLabelColor
        return field
    }

    private func configureSettingsSegmentedControl(_ control: NSSegmentedControl, action: Selector) {
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.target = self
        control.action = action
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
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

    private func applyWindowAspectFromSettings() {
        let store = SettingsStore.shared
        let ratio: CGFloat?
        switch store.windowAspectPreset {
        case .auto:
            if store.lockAspectRatioEnabled {
                guard let mediaRatio = currentMediaAspectRatio(), mediaRatio > 0 else {
                    return
                }
                ratio = mediaRatio
            } else {
                ratio = nil
            }
        case .widescreen, .standard, .ultrawide, .square:
            ratio = store.windowAspectPreset.aspectRatio
        }
        delegate?.playerViewController(self, didRequestWindowAspectRatio: ratio)
    }

    private func updateLockAspectControlAvailability() {
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

    private func applyVideoFitMode(_ mode: VideoFitMode) {
        playerSurfaceView.videoGravity = mode == .fill ? .resizeAspectFill : .resizeAspect
    }

    private func startPlaybackAtPreferredRate() {
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
        guard SettingsStore.shared.loopPlaybackEnabled else { return }
        guard let item = notification.object as? AVPlayerItem, item === player.currentItem else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.startPlaybackAtPreferredRate()
            self?.updatePlayPauseButtonIcon()
        }
    }

    @objc private func videoFitChanged() {
        let mode: VideoFitMode = videoFitModeControl.selectedSegment == 1 ? .fill : .fit
        SettingsStore.shared.videoFitMode = mode
        applyVideoFitMode(mode)
    }

    @objc private func windowAspectChanged() {
        let index = windowAspectControl.selectedSegment
        let presets = WindowAspectPreset.selectablePresets
        guard index >= 0, index < presets.count else { return }
        SettingsStore.shared.windowAspectPreset = presets[index]
        updateLockAspectControlAvailability()
        applyWindowAspectFromSettings()
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

    @objc private func playbackSourceChanged() {
        guard !suppressPlaybackSourceAction else { return }
        guard playbackSourcePopUp.isEnabled else { return }
        guard let source = playbackSourceURL ?? currentMediaURL else { return }

        let resumeTime = player.currentTime()
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

    private func showSettingsSheet() {
        guard activeMediaKind != .empty else { return }
        guard playbackLibraryOverlay == .closed else { return }
        guard rightSettingsSheet.isHidden else { return }
        rightSettingsSheet.isHidden = false
        syncVideoSettingsControlsFromStore()
        updateVideoInfoLabels()
        applyWindowAspectFromSettings()
        raisePlaybackChromeToFront()
        installOutsideClickMonitor()
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

    private func hideSettingsSheet() {
        guard !rightSettingsSheet.isHidden else { return }
        rightSettingsSheet.isHidden = true
        removeOutsideClickMonitorIfNoSheetsVisible()
    }

    private func showFullMediaLibrary() {
        installLibraryChromeIfNeeded()
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = false
        libraryBrowse.isHidden = false
        playbackMiniPreview.isHidden = true
        librarySidebar.reloadRoots()
        // Grid scan can be slow for large folders — keep UI responsive at launch.
        if case .root = mediaLibraryController.sidebarMode,
           mediaLibraryController.currentDirectoryURL != nil {
            libraryBrowse.reloadContent()
        } else {
            libraryBrowse.refresh()
        }
        playerSurfaceView.isHidden = true
        openButton.isHidden = true
        hintLabel.isHidden = true
        raisePlaybackChromeToFront()
    }

    private func showPlaybackLibrarySidebarOnly() {
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

    private func collapsePlaybackLibraryOverlay() {
        guard activeMediaKind != .empty else { return }
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = true
        libraryBrowse.isHidden = true
        playbackMiniPreview.isHidden = true
        restoreMainPlaybackSurface()
        removeOutsideClickMonitorIfNoSheetsVisible()
        raisePlaybackChromeToFront()
    }

    private func hideMediaLibrary() {
        if activeMediaKind == .empty { return }
        collapsePlaybackLibraryOverlay()
    }

    private func restoreMainPlaybackSurface() {
        switch activeMediaKind {
        case .empty:
            break
        case .video:
            playerSurfaceView.isHidden = false
            controlsContainer.isHidden = false
        case .image:
            imageSurfaceView.isHidden = false
            imageControlsContainer.isHidden = false
        }
    }

    private func showPlaybackMiniPreview() {
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

    private func syncPlaybackLibraryBrowseExpansion() {
        guard activeMediaKind != .empty else { return }

        switch mediaLibraryController.sidebarMode {
        case .root:
            if playbackLibraryOverlay == .sidebarOnly {
                expandPlaybackLibraryBrowse()
            }
        case .recentHeader:
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
        switch kind {
        case .video:
            loadVideo(url: url, replaceCurrent: true)
        case .image:
            loadImage(url: url)
        case .unsupported:
            showUnsupportedFileMessage("Unsupported file type.")
        }
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard self.view.window != nil else { return event }
            let pointInView = self.view.convert(event.locationInWindow, from: nil)

            if !self.rightSettingsSheet.isHidden {
                if self.rightSettingsSheet.frame.contains(pointInView) {
                    return event
                }
                if self.settingsButton.frame.contains(pointInView) || self.imageSettingsButton.frame.contains(pointInView) {
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
        let hotZoneWidth: CGFloat = 42
        let isInLeftHotZone = point.x <= hotZoneWidth
        let isInRightHotZone = point.x >= (view.bounds.width - hotZoneWidth)
        if isInLeftHotZone, activeMediaKind != .empty, playbackLibraryOverlay == .closed {
            showPlaybackLibrarySidebarOnly()
        }
        if activeMediaKind != .empty, isInRightHotZone, playbackLibraryOverlay == .closed {
            showSettingsSheet()
        }
    }

    private func setupPlaybackTopRowLayout() {
        guard !playbackTopRowLayoutConfigured else { return }
        playbackTopRowLayoutConfigured = true

        playbackTopRowView.translatesAutoresizingMaskIntoConstraints = false
        playbackCenterClusterStack.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false

        playbackTopRowView.addSubview(playbackCenterClusterStack)
        playbackTopRowView.addSubview(volumeSlider)

        NSLayoutConstraint.activate([
            playbackTopRowView.heightAnchor.constraint(equalToConstant: 28),

            volumeSlider.trailingAnchor.constraint(equalTo: playbackTopRowView.trailingAnchor),
            volumeSlider.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            playbackCenterClusterStack.centerXAnchor.constraint(equalTo: playbackTopRowView.centerXAnchor),
            playbackCenterClusterStack.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),
            playbackCenterClusterStack.leadingAnchor.constraint(greaterThanOrEqualTo: playbackTopRowView.leadingAnchor),
            playbackCenterClusterStack.trailingAnchor.constraint(
                lessThanOrEqualTo: volumeSlider.leadingAnchor,
                constant: -playbackControlClusterSpacing
            )
        ])
    }

    private func configureTransportSpeedClusterSpacer(_ spacer: NSView) {
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureTransportSpeedLabel(_ label: NSTextField, alignment: NSTextAlignment) {
        label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.alphaValue = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: Self.transportSpeedLabelReservedWidth).isActive = true
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
        let width = MusicStylePlaybackBar.preferredBarWidth(forContentWidthPoints: view.bounds.width)
        playbackBarWidthConstraint?.constant = width
        imageBarWidthConstraint?.constant = min(420, width)
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

        transportClusterStack.arrangedSubviews.forEach {
            transportClusterStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        transportClusterStack.addArrangedSubview(transportSpeedLeftCluster)
        transportClusterStack.addArrangedSubview(playPauseButton)
        transportClusterStack.addArrangedSubview(transportSpeedRightCluster)
        updatePlaybackSpeedTransportLabels()

        queueButton.isHidden = queue.isEmpty

        playbackCenterClusterStack.addArrangedSubview(libraryButton)
        playbackCenterClusterStack.addArrangedSubview(transportClusterStack)
        playbackCenterClusterStack.addArrangedSubview(settingsButton)
        if !queue.isEmpty {
            playbackCenterClusterStack.addArrangedSubview(queueButton)
        }

        if playbackTopRowView.superview != topControlsStack {
            topControlsStack.addArrangedSubview(playbackTopRowView)
            playbackTopRowView.widthAnchor.constraint(equalTo: topControlsStack.widthAnchor).isActive = true
        }
        playbackTopRowView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playbackCenterClusterStack.setContentHuggingPriority(.required, for: .horizontal)
        playbackCenterClusterStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        transportClusterStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        bottomLeftControlsStack.addArrangedSubview(currentTimeLabel)
        bottomRightControlsStack.addArrangedSubview(totalTimeLabel)

        bottomControlsStack.addArrangedSubview(bottomLeftControlsStack)
        bottomControlsStack.addArrangedSubview(seekSlider)
        bottomControlsStack.addArrangedSubview(bottomRightControlsStack)

        currentTimeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        totalTimeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        volumeSliderWidthConstraint?.constant = volumeSliderWidth(for: tier)
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
        let symbol = player.rate > 0 ? "pause.fill" : "play.fill"
        let label = player.rate > 0 ? "Pause" : "Play"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            playPauseButton.image = image.withSymbolConfiguration(config)
            playPauseButton.image?.isTemplate = true
        }
        playPauseButton.title = ""
    }

    private func updateTimelineUI() {
        guard !isSeekingFromUI else { return }
        guard let currentItem = player.currentItem else { return }
        logBufferStateChanges(item: currentItem)
        let durationSec = CMTimeGetSeconds(currentItem.duration)
        let currentSec = CMTimeGetSeconds(player.currentTime())
        if durationSec.isFinite && durationSec > 0 {
            seekSlider.maxValue = durationSec
            seekSlider.doubleValue = max(0, min(currentSec, durationSec))
            currentTimeLabel.stringValue = formatTime(currentSec)
            totalTimeLabel.stringValue = formatTime(durationSec)
        }
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

    @objc private func togglePlayPause() {
        let start = CFAbsoluteTimeGetCurrent()
        if player.rate > 0 {
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
        let target = CMTime(seconds: seekSlider.doubleValue, preferredTimescale: 600)
        performCooperativeSeek(to: target) { _ in
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print(String(format: "[DEBUG-ui] seek=%.2fms", elapsedMs))
        }
    }

    @objc private func volumeSliderChanged() {
        let start = CFAbsoluteTimeGetCurrent()
        desiredPlaybackVolume = Float(volumeSlider.doubleValue)
        if !isMutedForSwitch {
            player.volume = desiredPlaybackVolume
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[DEBUG-ui] volume=%.2fms", elapsedMs))
    }

    /// Pause and mute Laugh only (not system output) before swapping items.
    private func preparePlayerForVideoSwitch() {
        volumeRampToken += 1
        isMutedForSwitch = true
        player.pause()
        player.isMuted = true
        print("[DEBUG-playback] paused Laugh for video switch (player muted, volume unchanged)")
    }

    /// Stop Laugh audio/video output without `replaceCurrentItem(nil)` — that call can reset Core Audio for all apps.
    private func suspendPlayerOutputForStillOrEmpty() {
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
        let target = max(0, min(1, desiredPlaybackVolume))
        isMutedForSwitch = false
        player.isMuted = false
        player.volume = target
        print(String(format: "[DEBUG-playback] restored Laugh volume=%.2f", target))
    }

    /// Safety net after playback has actually started — never during an in-flight switch.
    private func ensureLaughVolumeIfPlaying() {
        guard activeMediaKind == .video else { return }
        guard !isMutedForSwitch else { return }
        guard lastPlaybackStartedItemID != nil else { return }
        guard player.rate > 0, player.currentItem != nil else { return }
        guard desiredPlaybackVolume > 0.01 else { return }
        guard player.volume < 0.01 || player.isMuted else { return }
        player.isMuted = false
        player.volume = desiredPlaybackVolume
        print(String(format: "[DEBUG-playback] volume safety restore=%.2f", desiredPlaybackVolume))
    }

    @objc private func previousPressed() {
        stepPlaybackSpeed(by: -1)
    }

    @objc private func nextPressed() {
        stepPlaybackSpeed(by: 1)
    }

    @objc private func queuePressed() {
        let list = queue.map(\.lastPathComponent).joined(separator: "\n")
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Queued Videos"
        alert.informativeText = list.isEmpty ? "Queue is empty." : list
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        selectedVideoSettingsTabIndex = max(0, min(sender.tag, 2))
        applySettingsTabButtonState()
        updateSettingsTabVisibility()
    }

    @objc private func imageSettingsTabPressed(_ sender: NSButton) {
        selectedImageSettingsTabIndex = max(0, min(sender.tag, 1))
        applySettingsTabButtonState()
        updateSettingsTabVisibility()
    }

    @objc private func imageZoomIn() {
        imageSurfaceView.setZoomScale(min(imageSurfaceView.zoomScale * 1.15, 8.0))
    }

    @objc private func imageZoomOut() {
        imageSurfaceView.setZoomScale(max(imageSurfaceView.zoomScale / 1.15, 0.2))
    }

    @objc private func imageFit() {
        imageSurfaceView.resetZoom()
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

final class PlaybackMiniPreviewView: NSView {
    var onExpand: (() -> Void)?

    private let videoSurface = MiniPlayerSurfaceView()
    private let imageSurface = NSImageView()
    private let expandBadge = NSImageView()

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

        expandBadge.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Return to full playback") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            expandBadge.image = image.withSymbolConfiguration(config)
            expandBadge.contentTintColor = .white
        }

        addSubview(videoSurface)
        addSubview(imageSurface)
        addSubview(expandBadge)

        NSLayoutConstraint.activate([
            videoSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoSurface.topAnchor.constraint(equalTo: topAnchor),
            videoSurface.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageSurface.topAnchor.constraint(equalTo: topAnchor),
            imageSurface.bottomAnchor.constraint(equalTo: bottomAnchor),

            expandBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            expandBadge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            expandBadge.widthAnchor.constraint(equalToConstant: 18),
            expandBadge.heightAnchor.constraint(equalToConstant: 18)
        ])

        toolTip = "Click to return to full playback"
        let click = NSClickGestureRecognizer(target: self, action: #selector(expandClicked))
        addGestureRecognizer(click)
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

    @objc private func expandClicked() {
        onExpand?()
    }
}

private final class HoverTextButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?
    var uiScale: CGFloat = 1 {
        didSet { updateAttributedTitle() }
    }
    var symbolName: String = "" {
        didSet { updateAttributedTitle() }
    }
    var textColor: NSColor = .secondaryLabelColor {
        didSet { updateAttributedTitle() }
    }
    var fontWeight: NSFont.Weight = .medium {
        didSet { updateAttributedTitle() }
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
        alignment = .center
        setButtonType(.momentaryChange)
        contentTintColor = .secondaryLabelColor
        font = .systemFont(ofSize: 12, weight: .medium)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateAttributedTitle()
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

    private func updateAttributedTitle() {
        let baseFont = NSFont.systemFont(ofSize: 12 * uiScale, weight: fontWeight)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: textColor,
                .font: baseFont
            ]
        )
        contentTintColor = textColor
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 11 * uiScale, weight: .medium)
            self.image = image.withSymbolConfiguration(config)
            self.image?.isTemplate = true
        }
    }
}

private final class SettingsTabHeaderItemView: NSView {
    init(button: HoverTextButton, showsSeparator: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            button.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])

        if showsSeparator {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separator)
            NSLayoutConstraint.activate([
                separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
                separator.centerYAnchor.constraint(equalTo: centerYAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
                separator.heightAnchor.constraint(equalToConstant: 14)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class MiniPlayerSurfaceView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
        }
    }

    private var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Expected AVPlayerLayer backing layer.")
        }
        return layer
    }
}

final class DragHostView: NSView {
    var readURLs: ((NSDraggingInfo) -> [URL])?
    var onPerformDrop: (([URL], NSPoint) -> Bool)?
    var onDragSessionActive: ((Bool) -> Void)?
    var onMouseMoved: ((NSPoint) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var activeDragSessions = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])
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
        let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
}

final class PlayerSurfaceView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
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

