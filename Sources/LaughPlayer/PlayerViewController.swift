import AppKit
import AVKit
import AVFoundation
import CoreMedia
import CoreImage
import Metal
import QuartzCore
import UniformTypeIdentifiers

protocol PlayerViewControllerDelegate: AnyObject {
    func playerViewController(_ controller: PlayerViewController, didRequestWindowAspectRatio ratio: CGFloat?)
    func playerViewController(_ controller: PlayerViewController, didUpdatePlayingTitle title: String?)
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
    private let idleSleepGuard = PlaybackIdleSleepGuard()
    private let mpvController = MpvPlaybackController()
    /// Subtitle-only libmpv (vid=no) over remux AVPlayer for embedded PGS.
    private let bitmapOverlayController = MpvPlaybackController()
    private let bitmapOverlayBlitView = MpvSoftwareBlitView()
    private var bitmapOverlayActive = false
    private var bitmapOverlaySourcePath: String?
    private var bitmapOverlaySyncTimer: Timer?
    /// ffmpeg-seeded PGS/VobSub rows so the Subs picker fills before overlay mpv is ready.
    private var cachedBitmapProbeTracks: [SubtitleTrackInfo] = []
    private var bitmapOverlayWantPlaying = false
    private var bitmapOverlayLastRate: Float = 1
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
    private let imageTopRowView = NSView()
    private let imageCropBar = ImageCropBarView()
    private var isImageCropMode = false
    private let imageLeadingAccessoryCluster = NSStackView()
    private let imageTransportCluster = NSStackView()
    private let imageLibraryButton = NSButton(title: "Library", target: nil, action: nil)
    private let imageQueuePreviousButton = NSButton(title: "", target: nil, action: nil)
    private let imageZoomOutButton = NSButton(title: "Zoom −", target: nil, action: nil)
    private let imageActualSizeButton = NSButton(title: "Actual", target: nil, action: nil)
    private let imageZoomInButton = NSButton(title: "Zoom +", target: nil, action: nil)
    private let imageFitButton = NSButton(title: "Fit", target: nil, action: nil)
    private let imageCropButton = NSButton(title: "Crop", target: nil, action: nil)
    private let imageRotateLeftButton = NSButton(title: "Rotate Left", target: nil, action: nil)
    private let imageRotateRightButton = NSButton(title: "Rotate Right", target: nil, action: nil)
    private let imageQueueNextButton = NSButton(title: "", target: nil, action: nil)
    private let imageSettingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private var imageTopRowLayoutConfigured = false
    private let controlsStack = NSStackView()
    private let transportClusterStack = NSStackView()
    private let playbackLeadingAccessoryCluster = NSStackView()
    private let playbackTopRowView = NSView()
    private let topControlsStack = NSStackView()
    private let bottomControlsStack = NSStackView()
    private let bottomLeftControlsStack = NSStackView()
    private let bottomRightControlsStack = NSStackView()
    private var playbackBarWidthConstraint: NSLayoutConstraint?
    private var playbackBarBottomConstraint: NSLayoutConstraint?
    private var imageBarWidthConstraint: NSLayoutConstraint?
    private var imageBarHeightConstraint: NSLayoutConstraint?
    private var imageBarBottomConstraint: NSLayoutConstraint?
    private var miniPreviewWidthConstraint: NSLayoutConstraint?
    private var miniPreviewHeightConstraint: NSLayoutConstraint?
    private let transportSpeedLeftCluster = NSStackView()
    private let playbackSpeedSlowLabel = NSTextField(labelWithString: "")
    private let queuePreviousButton = NSButton(title: "", target: nil, action: nil)
    private let speedStepDownButton = NSButton(title: "", target: nil, action: nil)
    private let playPauseButton = NSButton(title: "Play", target: nil, action: nil)
    private let transportSpeedRightCluster = NSStackView()
    private let speedStepUpButton = NSButton(title: "", target: nil, action: nil)
    private let queueNextButton = NSButton(title: "", target: nil, action: nil)
    private let playbackSpeedFastLabel = NSTextField(labelWithString: "")
    private let queueButton = NSButton(title: "Queue", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let playbackAccessoryCluster = NSStackView()
    private let imageAccessoryCluster = NSStackView()
    private let libraryButton = NSButton(title: "Library", target: nil, action: nil)
    private let mediaLibraryController = MediaLibraryController()
    private lazy var librarySidebar = LibrarySidebarView(controller: mediaLibraryController)
    private lazy var libraryBrowse = LibraryBrowseView(controller: mediaLibraryController)
    private let playbackMiniPreview = PlaybackMiniPreviewView()
    private let titleBarChromeStrip = TitleBarChromeStripView()
    private var titleBarChromeHeightConstraint: NSLayoutConstraint?
    private let rightSettingsSheet = NSVisualEffectView()
    /// Opaque floor for image studio — covers the visual-effect sheet so the edit column matches content chrome.
    private let settingsColumnFillView = NSView()
    /// Opaque wash-over-floor fill so the floating tools bar isn’t lightened by the photo underneath.
    private let imageToolsBarFillView = NSView()
    private let videoSettingsTabsRow = NSStackView()
    private let imageSettingsTabsRow = NSStackView()
    private var videoSettingsTabButtons: [HoverTextButton] = []
    private var imageSettingsTabButtons: [HoverTextButton] = []
    private var videoSettingsTabHeaders: [SettingsTabHeaderItemView] = []
    private var imageSettingsTabHeaders: [SettingsTabHeaderItemView] = []
    private var selectedVideoSettingsTabIndex = 0
    private var selectedImageSettingsTabIndex = 0
    private let settingsContentContainer = SettingsScrollDocumentView()
    private let settingsScrollClipHost = SettingsScrollClipHostView()
    private let settingsScrollView = NSScrollView()
    private let settingsTopOverflowFade = ScrollOverflowFadeView()
    private let settingsBottomOverflowFade = ScrollOverflowFadeView()
    private let videoTabView = NSStackView()
    private let audioTabView = NSStackView()
    private let audioSettings = AudioSettingsControls()
    private var cachedAudioTracks: [AudioTrackInfo] = []
    private var suppressAudioTrackPopUpAction = false
    private var pendingAudioTrackBackendID: AudioTrackInfo.BackendID?
    private var pendingResumePlayingAfterLoad: Bool?
    private let subtitlesSettings = SubtitlesSettingsControls()
    /// Retained while the OpenSubtitles sheet is on screen.
    private var openSubtitlesSearchSheet: OpenSubtitlesSearchSheetController?
    private var cachedSubtitleTracks: [SubtitleTrackInfo] = []
    private var suppressSubtitlePopUpAction = false
    private var suppressSubtitleAppearanceCallback = false
    private var primarySubtitlesEnabled = false
    private var secondarySubtitlesEnabled = false
    private var lastExternalSubtitlePath: String?
    private var pendingCompanionSubtitlePath: String?
    private var userDisabledSubtitlesForSourcePath: String?
    private var cachedDiscoveredCompanions: [DiscoveredCompanionSubtitle] = []
    private let subtitlesTabView = NSStackView()
    private let nativeSubtitleOverlay = NativeSubtitleOverlay()
    private let playbackSubtitleToggle = PlaybackSubtitleToggleButton()
    private let imageTabView = NSStackView()
    private let imageFitTabView = NSStackView()
    private let imageAdjustSession = ImageAdjustSession()
    private let imageSelectionSession = ImageSelectionSession()
    private let imageAdjustControls = ImageAdjustControls()
    private var imageSectionHeaders: [ImageAdjustSection: CollapsibleSettingsSectionView] = [:]
    private var imageSubjectSelectHeader: CollapsibleSettingsSectionView?
    private let subjectSelectAutoButton = NSButton(title: "Auto Select", target: nil, action: nil)
    private let subjectSelectClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let subjectSelectCancelDownloadButton = NSButton(title: "Cancel Download", target: nil, action: nil)
    private let subjectSelectExportButton = NSButton(title: "Export Cutout…", target: nil, action: nil)
    private let subjectSelectSmoothSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let subjectSelectFeatherSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let subjectSelectContrastSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let subjectSelectShiftSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    private let subjectSelectDecontamSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let subjectSelectBrushRadiusSlider = NSSlider(value: 24, minValue: 4, maxValue: 80, target: nil, action: nil)
    private let subjectSelectBrushModeControl = NSSegmentedControl(
        labels: SelectionBrushMode.allCases.map(\.menuTitle),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let subjectSelectSmoothValue = NSTextField(labelWithString: "0")
    private let subjectSelectFeatherValue = NSTextField(labelWithString: "0")
    private let subjectSelectContrastValue = NSTextField(labelWithString: "0")
    private let subjectSelectShiftValue = NSTextField(labelWithString: "0")
    private let subjectSelectDecontamValue = NSTextField(labelWithString: "0")
    private let subjectSelectBrushRadiusValue = NSTextField(labelWithString: "24")
    private let subjectSelectStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let subjectSelectProgressView = SelectionProgressView()
    private var subjectSelectProgressRow: SettingsCardRow?
    /// What the progress row currently costs in height — re-measure the section when it changes.
    private var subjectSelectProgressShape: (hidden: Bool, hasBar: Bool) = (true, false)
    private var subjectSelectRefineSettleWork: DispatchWorkItem?
    private var subjectSelectBrushEnabled = false
    private var subjectSelectClickEnabled = false
    private let subjectSelectBrushToggle = CompactTealToggle()
    private let subjectSelectClickToggle = CompactTealToggle()
    private let imageStudioCommitFooter = ImageStudioCommitFooter()
    private var imageStudioCommitFooterHeightConstraint: NSLayoutConstraint?
    private var imageSavedPresetsHost = NSStackView()
    private let imageFolderCarousel = ImageFolderCarouselView()
    private let imageStudioMetaBar = ImageStudioMetaBarView()
    private var imageFolderSiblings: [LibraryMediaFile] = []
    private var imageSurfaceBottomConstraint: NSLayoutConstraint?
    private var imageSurfaceLeadingConstraint: NSLayoutConstraint?
    private var imageSurfaceTrailingConstraint: NSLayoutConstraint?
    private var imageSurfaceTopConstraint: NSLayoutConstraint?
    private var imageCarouselHeightConstraint: NSLayoutConstraint?
    private var imageCarouselLeadingConstraint: NSLayoutConstraint?
    private var imageCarouselTrailingConstraint: NSLayoutConstraint?
    private var imageCarouselTrailingToSidebarConstraint: NSLayoutConstraint?
    private var imageMetaBarLeadingConstraint: NSLayoutConstraint?
    private var imageMetaBarTrailingConstraint: NSLayoutConstraint?
    private var imageMetaBarTrailingToSidebarConstraint: NSLayoutConstraint?
    private var imageMetaBarBottomConstraint: NSLayoutConstraint?
    private var imageSurfaceTrailingToSidebarConstraint: NSLayoutConstraint?
    private var libraryBrowseTrailingToEdgeConstraint: NSLayoutConstraint?
    private var libraryBrowseWidthConstraint: NSLayoutConstraint?
    private let imageCarouselHeight: CGFloat = 100
    private let imageMetaBarHeight: CGFloat = 38
    private let imageLibraryBrowseWidth: CGFloat = 272
    /// Luminar-like padding around the photo in the main container.
    private let imageStudioMargin: CGFloat = 56
    private let imageStudioTopMargin: CGFloat = 52
    private let imageZoomPercentLabel = NSTextField(labelWithString: "100%")
    /// User hid the filmstrip via the meta bar toggle.
    private var imageCarouselUserHidden = false
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
    private let freezeWatchdog = PlaybackFreezeWatchdog()
    private let compatibilityBanner = CompatibilityBannerView()
    private var currentMediaURL: URL?
    /// Set when media is opened, cleared once folder management has been scoped to its
    /// folder — so the reveal happens on the first visit and never fights later browsing.
    private var pendingLibraryFolderReveal = false
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
    private var lastPlaybackTraceSecond: Int = -1
    private var isSeekingFromUI = false
    private var seekGeneration = 0
    /// Sticky across rapid seek bursts: first seek pauses, later seeks see rate==0.
    private var resumePlaybackAfterSeek = false
    private var currentControlTier: ControlDensityTier = .regular
    private var outsideClickMonitor: Any?
    private var edgeHotZoneClickMonitor: Any?
    /// Armed on mouseDown in an edge zone; fired on mouseUp only if the pointer barely moved.
    private var pendingEdgeHotZoneAction: (() -> Void)?
    private var edgeHotZoneMouseDownPoint: NSPoint?
    /// Tracks whether we pushed `.pointingHand` for an edge hot zone.
    private var edgeHotZoneCursorPushed = false
    private var suppressSettingsDismissForColorPicker = false
    private var immersivePointerMonitor: Any?
    private var keyboardShortcutMonitor: Any?
    private var scrollShortcutMonitor: Any?
    private var videoDoubleClickMonitor: Any?
    private var scrollVolumeAccumulator: CGFloat = 0
    private var scrollSeekAccumulator: CGFloat = 0
    private var immersiveChromeHideWorkItem: DispatchWorkItem?
    private var immersiveChromeVisible = false
    private var immersiveCursorHiddenUntilMove = false
    private var immersiveCursorWindowObservers: [NSObjectProtocol] = []
    private var screenParameterObserver: NSObjectProtocol?
    private var dragSessionActive = false
    /// Width of the clickable edge strips that open/close side panels.
    private static let edgeHotZoneWidth = EdgeHotZoneGeometry.width
    private let leftEdgeHotZoneAffordance = EdgeHotZoneAffordanceView(edge: .leading)
    private let rightEdgeHotZoneAffordance = EdgeHotZoneAffordanceView(edge: .trailing)
    private var rightEdgeHotZoneToWindowTrailingConstraint: NSLayoutConstraint?
    private var rightEdgeHotZoneToSidebarLeadingConstraint: NSLayoutConstraint?
    private var settingsContentBottomConstraint: NSLayoutConstraint?
    /// Pins the active tab’s bottom to the scroll document so height tracks content (enables scrolling).
    private var settingsActiveTabBottomConstraint: NSLayoutConstraint?
    private var securityScopedMediaURL: URL?
    private var videoLoadGeneration = 0
    private var activePlaybackGeneration = 0
    private var observedItemLoadGeneration = 0
    private var observedItemPlayableURL: URL?
    private var fallbackConvertedOutputPaths: Set<String> = []
    private var fallbackInProgress = false {
        didSet {
            if oldValue, !fallbackInProgress {
                flushPendingWindowAspectIfReady()
            }
        }
    }
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
    /// One ffmpeg probe per playable remux path — detects sparse incomplete remux freezes.
    private var sparseRemuxFreezeCheckedPath: String?
    /// Avoid re-tipping bitmap-only subs on every subtitle refresh for the same source.
    private var bitmapSubtitlesTipShownForPath: String?
    private var seekBarPrepareTimer: Timer?
    private var playbackPrepareActive = false
    private var fallbackSessionToken: Int = 0
    private var lastLoadRequestURL: String?
    private var lastLoadRequestAt: CFAbsoluteTime = 0
    /// Throttle resume-position writes while scrubbing / playing.
    private var lastResumePersistAt: CFAbsoluteTime = 0
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
    /// Narrower docked edit column for image studio.
    private let imageStudioSettingsPanelWidth: CGFloat = 268
    private let baseLibrarySidebarWidth: CGFloat = LibrarySidebarView.width
    private var librarySidebarWidthConstraint: NSLayoutConstraint?
    private var settingsPanelWidthConstraint: NSLayoutConstraint?
    private var settingsPanelTopConstraint: NSLayoutConstraint?
    private var imageSettingsTabsTopConstraint: NSLayoutConstraint?
    private var volumeSliderWidthConstraint: NSLayoutConstraint?
    private var volumeClusterCollapsedWidthConstraint: NSLayoutConstraint?
    private var playbackAccessoryToVolumeConstraint: NSLayoutConstraint?
    private var playbackAccessoryToSettingsConstraint: NSLayoutConstraint?
    private var volumeToSettingsConstraint: NSLayoutConstraint?
    private var playbackTopRowLayoutConfigured = false
    private var audioOutputEnabled = true
    private var playerInterfaceInstalled = false
    private var libraryChromeInstalled = false
    private let playbackControlClusterSpacing: CGFloat = 20
    private var lastAppliedUIScale: CGFloat = 1
    private var responsiveControlsLayoutScheduled = false
    private var titleBarLayoutUpdateScheduled = false
    private var uiScaleUpdateScheduled = false
    private var playbackBarLayoutUpdateScheduled = false
    private var pendingWindowAspectRefresh = false
    private var settingsBottomInsetScheduled = false
    private enum PlaybackLibraryOverlay {
        case closed
        case sidebarOnly
        case sidebarAndBrowse
    }

    private var playbackLibraryOverlay: PlaybackLibraryOverlay = .closed
    private let settingsPanelInnerInset: CGFloat = 12
    /// Scroll column hugs the panel’s trailing edge so the overlay knob isn’t on the cards.
    private let settingsScrollTrailingInset: CGFloat = 4
    /// Gap between section cards and the vertical scroller.
    private let settingsScrollerGutter: CGFloat = 12
    private let settingsTabsTopInset: CGFloat = 40
    private let settingsContentBottomClearance: CGFloat = 142
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
        installScreenParameterObserverIfNeeded()
        prepareInterfaceForDisplay()
    }

    /// Ensures the library empty state is laid out once the window has a real size.
    func prepareInterfaceForDisplay(skipLibrary: Bool = false) {
        guard view.window != nil else { return }
        installImmersiveCursorWindowObserversIfNeeded()
        installPlayerInterfaceIfNeeded()
        installLibraryChromeIfNeeded()
        if !skipLibrary, activeMediaKind == .empty {
            showFullMediaLibrary()
            setImmersiveChromeVisible(true, animated: false)
        }
        LaunchLog.emit("prepareInterfaceForDisplay: bounds=\(view.bounds) skipLibrary=\(skipLibrary)")
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
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.actionAtItemEnd = .pause
        PlaybackPipelinePolicy.configure(player)
        if #available(macOS 12.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        }
        playerSurfaceView.videoGravity = .resizeAspect
        playerSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        nativeSubtitleOverlay.install(in: playerSurfaceView)
        installBitmapOverlayBlitViewIfNeeded()
        playerSurfaceView.onMpvLayoutChanged = { [weak self] in
            guard let self, self.mpvBackendActive else { return }
            self.mpvController.requestRenderRefresh()
        }
        playerSurfaceView.onScrollWheel = { [weak self] event in
            self?.handlePlaybackScrollEvent(event) ?? false
        }
        view.addSubview(playerSurfaceView)

        imageSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        imageSurfaceView.isHidden = true
        view.addSubview(imageSurfaceView)

        imageFolderCarousel.translatesAutoresizingMaskIntoConstraints = false
        imageFolderCarousel.isHidden = true
        imageFolderCarousel.onSelect = { [weak self] url in
            self?.loadImage(url: url)
        }
        view.addSubview(imageFolderCarousel)

        imageStudioMetaBar.translatesAutoresizingMaskIntoConstraints = false
        imageStudioMetaBar.isHidden = true
        imageStudioMetaBar.onFavoriteToggle = { [weak self] in self?.toggleImageFavorite() }
        imageStudioMetaBar.onRatingChange = { [weak self] rating in self?.setImageRating(rating) }
        imageStudioMetaBar.onZoomMenuChoice = { [weak self] choice in self?.applyImageStudioZoomMenuChoice(choice) }
        imageStudioMetaBar.onCarouselVisibilityToggle = { [weak self] in self?.toggleImageCarouselVisibility() }
        imageStudioMetaBar.onBeforeAfterSelect = { [weak self] showingBefore in
            self?.setImageBeforeAfter(showingBefore: showingBefore)
        }
        view.addSubview(imageStudioMetaBar)

        leftEdgeHotZoneAffordance.translatesAutoresizingMaskIntoConstraints = false
        leftEdgeHotZoneAffordance.setVisible(false, emphasized: false, animated: false)
        leftEdgeHotZoneAffordance.onActivate = { [weak self] in
            guard let self, self.activeMediaKind != .empty, self.playbackLibraryOverlay == .closed else { return }
            self.showPlaybackLibrarySidebarOnly()
        }
        view.addSubview(leftEdgeHotZoneAffordance)

        rightEdgeHotZoneAffordance.translatesAutoresizingMaskIntoConstraints = false
        rightEdgeHotZoneAffordance.setVisible(false, emphasized: false, animated: false)
        rightEdgeHotZoneAffordance.onActivate = { [weak self] in
            guard let self, self.activeMediaKind != .empty, self.playbackLibraryOverlay == .closed else { return }
            if self.isSettingsPanelFullyOpen() {
                self.hideSettingsSheet()
            } else {
                self.showSettingsSheet()
            }
        }
        view.addSubview(rightEdgeHotZoneAffordance)

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

        imageToolsBarFillView.translatesAutoresizingMaskIntoConstraints = false
        imageToolsBarFillView.wantsLayer = true
        imageToolsBarFillView.isHidden = true
        imageControlsContainer.addSubview(imageToolsBarFillView, positioned: .below, relativeTo: nil)

        imageTopRowView.translatesAutoresizingMaskIntoConstraints = false
        imageControlsContainer.addSubview(imageTopRowView)
        configureImageControls()
        setupImageTopRowLayout()
        imageSurfaceView.onDoubleClick = { [weak self] in
            self?.toggleImageFitActualSize()
        }
        imageSurfaceView.onZoomScaleChanged = { [weak self] in
            self?.updateImageZoomPercentLabel()
        }
        imageSurfaceView.onCropChanged = { [weak self] in
            guard let self else { return }
            if !self.imageSurfaceView.isCropMode {
                self.isImageCropMode = false
                self.updateImageCropChrome()
                self.updateImageZoomPercentLabel()
            }
            self.updateImageStudioCommitFooter()
        }
        imageAdjustControls.bind(to: imageAdjustSession)
        imageAdjustSession.onChange = { [weak self] quality in
            guard let self else { return }
            self.imageSurfaceView.setAdjustParameters(
                self.imageAdjustSession.presentationParameters,
                quality: quality
            )
        }
        imageAdjustSession.onChromeChange = { [weak self] in
            self?.refreshImageSectionEditChrome()
            self?.updateImageStudioCommitFooter()
        }
        imageSelectionSession.onChange = { [weak self] quality in
            guard let self else { return }
            let mask = self.imageSelectionSession.currentMask
            let mode = self.imageSelectionSession.currentDisplayMode
            let renderQuality: ImageAdjustRenderQuality = quality == .accurate ? .full : .preview
            self.imageSurfaceView.setSelectionPreview(
                mask: mask,
                displayMode: mode,
                refine: self.imageSelectionSession.currentRefine,
                quality: renderQuality
            )
            self.refreshSubjectSelectChrome()
            self.updateImageStudioCommitFooter()
        }
        imageSelectionSession.onChromeChange = { [weak self] in
            self?.refreshSubjectSelectChrome()
            self?.updateImageStudioCommitFooter()
        }
        imageSurfaceView.onSelectionBrushStroke = { [weak self] point in
            guard let self else { return }
            _ = self.imageSelectionSession.applyBrush(at: point, preview: true)
        }
        imageSurfaceView.onSelectionBrushStrokeEnded = { [weak self] in
            guard let self else { return }
            self.imageSurfaceView.setSelectionPreview(
                mask: self.imageSelectionSession.currentMask,
                displayMode: self.imageSelectionSession.currentDisplayMode,
                refine: self.imageSelectionSession.currentRefine,
                quality: .full
            )
        }
        imageSurfaceView.onSelectionClick = { [weak self] point, negative, additive in
            guard let self, let image = self.imageSurfaceView.selectionSourceCIImage else { return }
            self.imageSelectionSession.clickSelect(
                in: image,
                at: point,
                negative: negative,
                additive: additive
            )
        }
        imageSurfaceView.onSelectionBox = { [weak self] box, additive in
            guard let self, let image = self.imageSurfaceView.selectionSourceCIImage else { return }
            self.imageSelectionSession.boxSelect(in: image, box: box, additive: additive)
        }

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

        settingsColumnFillView.translatesAutoresizingMaskIntoConstraints = false
        settingsColumnFillView.wantsLayer = true
        settingsColumnFillView.isHidden = true
        rightSettingsSheet.addSubview(settingsColumnFillView, positioned: .below, relativeTo: nil)

        videoSettingsTabsRow.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(videoSettingsTabsRow)

        imageSettingsTabsRow.isHidden = true
        imageSettingsTabsRow.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(imageSettingsTabsRow)
        configureSettingsTabsAppearance()

        settingsScrollView.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.hasVerticalScroller = true
        settingsScrollView.hasHorizontalScroller = false
        settingsScrollView.autohidesScrollers = true
        settingsScrollView.scrollerStyle = .overlay
        settingsScrollView.drawsBackground = false
        settingsScrollView.borderType = .noBorder
        settingsScrollView.verticalScrollElasticity = .allowed
        settingsScrollView.horizontalScrollElasticity = .none
        settingsScrollView.automaticallyAdjustsContentInsets = false
        settingsScrollView.contentView.drawsBackground = false
        settingsScrollView.verticalScroller = SoftThinScroller()
        settingsScrollView.verticalScroller?.controlSize = .mini
        settingsScrollView.verticalScroller?.scrollerStyle = .overlay
        settingsScrollClipHost.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(settingsScrollClipHost)
        settingsScrollClipHost.addSubview(settingsScrollView)

        settingsTopOverflowFade.translatesAutoresizingMaskIntoConstraints = false
        settingsTopOverflowFade.edge = .top
        settingsScrollClipHost.addSubview(settingsTopOverflowFade, positioned: .above, relativeTo: settingsScrollView)

        settingsBottomOverflowFade.translatesAutoresizingMaskIntoConstraints = false
        settingsBottomOverflowFade.edge = .bottom
        settingsScrollClipHost.addSubview(settingsBottomOverflowFade, positioned: .above, relativeTo: settingsScrollView)

        imageStudioCommitFooter.isHidden = true
        imageStudioCommitFooter.resetAllButton.target = self
        imageStudioCommitFooter.resetAllButton.action = #selector(imageStudioResetAllPressed)
        imageStudioCommitFooter.exportButton.target = self
        imageStudioCommitFooter.exportButton.action = #selector(imageStudioExportPressed)
        imageStudioCommitFooter.savePresetButton.target = self
        imageStudioCommitFooter.savePresetButton.action = #selector(imageStudioSavePresetPressed)
        rightSettingsSheet.addSubview(imageStudioCommitFooter)

        settingsContentContainer.translatesAutoresizingMaskIntoConstraints = false
        settingsScrollView.documentView = settingsContentContainer
        settingsTopOverflowFade.attach(to: settingsScrollView)
        settingsBottomOverflowFade.attach(to: settingsScrollView)
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
        transportSpeedLeftCluster.spacing = 0
        transportSpeedLeftCluster.addArrangedSubview(speedStepDownButton)

        transportSpeedRightCluster.orientation = .horizontal
        transportSpeedRightCluster.alignment = .centerY
        transportSpeedRightCluster.spacing = 0
        transportSpeedRightCluster.addArrangedSubview(speedStepUpButton)
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

        playbackLeadingAccessoryCluster.orientation = .horizontal
        playbackLeadingAccessoryCluster.alignment = .centerY
        playbackLeadingAccessoryCluster.spacing = 0
        playbackLeadingAccessoryCluster.setContentHuggingPriority(.required, for: .horizontal)
        playbackLeadingAccessoryCluster.setContentCompressionResistancePriority(.required, for: .horizontal)

        transportClusterStack.translatesAutoresizingMaskIntoConstraints = false
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
        imageBarHeightConstraint = imageControlsContainer.heightAnchor.constraint(equalToConstant: 52)
        // Sit just under the photo, above the studio meta bar / filmstrip.
        imageBarBottomConstraint = imageControlsContainer.bottomAnchor.constraint(
            equalTo: imageStudioMetaBar.topAnchor,
            constant: -10
        )
        settingsPanelWidthConstraint = rightSettingsSheet.widthAnchor.constraint(equalToConstant: baseSettingsPanelWidth)
        settingsPanelTopConstraint = rightSettingsSheet.topAnchor.constraint(equalTo: view.topAnchor)
        imageSettingsTabsTopConstraint = imageSettingsTabsRow.topAnchor.constraint(
            equalTo: rightSettingsSheet.topAnchor,
            constant: settingsTabsTopInset
        )

        imageSurfaceLeadingConstraint = imageSurfaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        imageSurfaceTrailingConstraint = imageSurfaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        imageSurfaceTopConstraint = imageSurfaceView.topAnchor.constraint(equalTo: view.topAnchor)
        imageSurfaceBottomConstraint = imageSurfaceView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        imageCarouselHeightConstraint = imageFolderCarousel.heightAnchor.constraint(equalToConstant: imageCarouselHeight)
        imageCarouselLeadingConstraint = imageFolderCarousel.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        imageCarouselTrailingConstraint = imageFolderCarousel.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        imageCarouselTrailingToSidebarConstraint = imageFolderCarousel.trailingAnchor.constraint(
            equalTo: rightSettingsSheet.leadingAnchor
        )
        imageMetaBarLeadingConstraint = imageStudioMetaBar.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        imageMetaBarTrailingConstraint = imageStudioMetaBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        imageMetaBarTrailingToSidebarConstraint = imageStudioMetaBar.trailingAnchor.constraint(
            equalTo: rightSettingsSheet.leadingAnchor
        )
        imageSurfaceTrailingToSidebarConstraint = imageSurfaceView.trailingAnchor.constraint(
            equalTo: rightSettingsSheet.leadingAnchor,
            constant: -12
        )
        imageCarouselTrailingToSidebarConstraint?.isActive = false
        imageMetaBarTrailingToSidebarConstraint?.isActive = false
        imageSurfaceTrailingToSidebarConstraint?.isActive = false
        rightEdgeHotZoneToWindowTrailingConstraint = rightEdgeHotZoneAffordance.trailingAnchor.constraint(
            equalTo: view.trailingAnchor
        )
        rightEdgeHotZoneToSidebarLeadingConstraint = rightEdgeHotZoneAffordance.trailingAnchor.constraint(
            equalTo: rightSettingsSheet.leadingAnchor
        )
        rightEdgeHotZoneToWindowTrailingConstraint?.isActive = true
        rightEdgeHotZoneToSidebarLeadingConstraint?.isActive = false
        imageMetaBarBottomConstraint = imageStudioMetaBar.bottomAnchor.constraint(
            equalTo: imageFolderCarousel.topAnchor
        )

        NSLayoutConstraint.activate([
            playerSurfaceView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerSurfaceView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerSurfaceView.topAnchor.constraint(equalTo: view.topAnchor),
            playerSurfaceView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            imageSurfaceLeadingConstraint!,
            imageSurfaceTrailingConstraint!,
            imageSurfaceTopConstraint!,
            imageSurfaceBottomConstraint!,

            imageFolderCarousel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageCarouselHeightConstraint!,
            imageCarouselLeadingConstraint!,
            imageCarouselTrailingConstraint!,

            imageMetaBarLeadingConstraint!,
            imageMetaBarTrailingConstraint!,
            imageMetaBarBottomConstraint!,
            imageStudioMetaBar.heightAnchor.constraint(equalToConstant: imageMetaBarHeight),

            leftEdgeHotZoneAffordance.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftEdgeHotZoneAffordance.topAnchor.constraint(equalTo: view.topAnchor),
            leftEdgeHotZoneAffordance.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftEdgeHotZoneAffordance.widthAnchor.constraint(equalToConstant: Self.edgeHotZoneWidth),

            rightEdgeHotZoneAffordance.topAnchor.constraint(equalTo: view.topAnchor),
            rightEdgeHotZoneAffordance.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rightEdgeHotZoneAffordance.widthAnchor.constraint(equalToConstant: Self.edgeHotZoneWidth),

            queueDropZone.widthAnchor.constraint(equalToConstant: 180),
            queueDropZone.heightAnchor.constraint(equalToConstant: 96),
            queueDropZone.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            queueDropZone.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hintLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 8),
            hintLabel.centerXAnchor.constraint(equalTo: openButton.centerXAnchor),

            compatibilityBanner.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            compatibilityBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            compatibilityBanner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            compatibilityBanner.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

            controlsContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playbackBarBottomConstraint!,
            controlsContainer.heightAnchor.constraint(equalToConstant: 76),
            playbackBarWidthConstraint!,

            imageControlsContainer.centerXAnchor.constraint(equalTo: imageSurfaceView.centerXAnchor),
            imageBarBottomConstraint!,
            imageBarHeightConstraint!,
            imageBarWidthConstraint!,

            imageToolsBarFillView.leadingAnchor.constraint(equalTo: imageControlsContainer.leadingAnchor),
            imageToolsBarFillView.trailingAnchor.constraint(equalTo: imageControlsContainer.trailingAnchor),
            imageToolsBarFillView.topAnchor.constraint(equalTo: imageControlsContainer.topAnchor),
            imageToolsBarFillView.bottomAnchor.constraint(equalTo: imageControlsContainer.bottomAnchor),

            imageTopRowView.leadingAnchor.constraint(equalTo: imageControlsContainer.leadingAnchor, constant: 10),
            imageTopRowView.trailingAnchor.constraint(equalTo: imageControlsContainer.trailingAnchor, constant: -10),
            imageTopRowView.topAnchor.constraint(equalTo: imageControlsContainer.topAnchor, constant: 8),
            imageTopRowView.bottomAnchor.constraint(equalTo: imageControlsContainer.bottomAnchor, constant: -8),

            controlsStack.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 16),
            controlsStack.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -16),
            controlsStack.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 10),
            controlsStack.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -10),

            settingsPanelTopConstraint!,
            rightSettingsSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightSettingsSheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            settingsPanelWidthConstraint!,

            settingsColumnFillView.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor),
            settingsColumnFillView.trailingAnchor.constraint(equalTo: rightSettingsSheet.trailingAnchor),
            settingsColumnFillView.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor),
            settingsColumnFillView.bottomAnchor.constraint(equalTo: rightSettingsSheet.bottomAnchor),

            videoSettingsTabsRow.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor, constant: settingsTabsTopInset),
            videoSettingsTabsRow.heightAnchor.constraint(equalToConstant: 34),
            // Match the scroll content column (leading inset + trailing scroller gutter) so tabs sit centered over the cards.
            videoSettingsTabsRow.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset),
            videoSettingsTabsRow.trailingAnchor.constraint(
                equalTo: rightSettingsSheet.trailingAnchor,
                constant: -(settingsScrollTrailingInset + settingsScrollerGutter)
            ),

            imageSettingsTabsTopConstraint!,
            imageSettingsTabsRow.heightAnchor.constraint(equalToConstant: 34),
            imageSettingsTabsRow.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset),
            imageSettingsTabsRow.trailingAnchor.constraint(
                equalTo: rightSettingsSheet.trailingAnchor,
                constant: -(settingsScrollTrailingInset + settingsScrollerGutter)
            ),

            settingsScrollClipHost.topAnchor.constraint(equalTo: videoSettingsTabsRow.bottomAnchor, constant: 8),
            settingsScrollClipHost.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset),
            settingsScrollClipHost.trailingAnchor.constraint(
                equalTo: rightSettingsSheet.trailingAnchor,
                constant: -settingsScrollTrailingInset
            ),

            settingsScrollView.topAnchor.constraint(equalTo: settingsScrollClipHost.topAnchor),
            settingsScrollView.leadingAnchor.constraint(equalTo: settingsScrollClipHost.leadingAnchor),
            settingsScrollView.trailingAnchor.constraint(equalTo: settingsScrollClipHost.trailingAnchor),
            settingsScrollView.bottomAnchor.constraint(equalTo: settingsScrollClipHost.bottomAnchor),

            imageStudioCommitFooter.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor),
            imageStudioCommitFooter.trailingAnchor.constraint(equalTo: rightSettingsSheet.trailingAnchor),
            imageStudioCommitFooter.bottomAnchor.constraint(equalTo: rightSettingsSheet.bottomAnchor),

            settingsTopOverflowFade.leadingAnchor.constraint(equalTo: settingsScrollView.leadingAnchor),
            settingsTopOverflowFade.trailingAnchor.constraint(
                equalTo: settingsScrollView.trailingAnchor,
                constant: -settingsScrollerGutter
            ),
            settingsTopOverflowFade.topAnchor.constraint(equalTo: settingsScrollView.topAnchor),
            settingsTopOverflowFade.heightAnchor.constraint(equalToConstant: 40),

            settingsBottomOverflowFade.leadingAnchor.constraint(equalTo: settingsScrollView.leadingAnchor),
            settingsBottomOverflowFade.trailingAnchor.constraint(
                equalTo: settingsScrollView.trailingAnchor,
                constant: -settingsScrollerGutter
            ),
            settingsBottomOverflowFade.bottomAnchor.constraint(equalTo: settingsScrollView.bottomAnchor),
            settingsBottomOverflowFade.heightAnchor.constraint(equalToConstant: 40),

            // Pin document top/width only — height comes from the active tab so content can exceed the clip view.
            // Leave a trailing gutter so the overlay scroller doesn’t sit on the section cards.
            settingsContentContainer.leadingAnchor.constraint(equalTo: settingsScrollView.contentView.leadingAnchor),
            settingsContentContainer.topAnchor.constraint(equalTo: settingsScrollView.contentView.topAnchor),
            settingsContentContainer.widthAnchor.constraint(
                equalTo: settingsScrollView.contentView.widthAnchor,
                constant: -settingsScrollerGutter
            )
        ])

        settingsContentBottomConstraint = settingsScrollClipHost.bottomAnchor.constraint(
            equalTo: imageStudioCommitFooter.topAnchor,
            constant: -settingsPanelInnerInset
        )
        settingsContentBottomConstraint?.isActive = true
        imageStudioCommitFooterHeightConstraint = imageStudioCommitFooter.heightAnchor.constraint(equalToConstant: 0)
        imageStudioCommitFooterHeightConstraint?.isActive = true
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
            PlaybackTrace.emit("[DEBUG-qos] playback stalled (possible audio/video pipeline starvation)")
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
                self.tracePlaybackTick(seconds: seconds)
                self.ensureLaughVolumeIfPlaying()
                _ = self.extendProgressivePlaybackIfNeeded()
                self.updateTimelineUI()
            }
        }

        updateSettingsContentBottomInset()
        installKeyboardShortcutMonitor()
        installScrollShortcutMonitor()
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
        libraryBrowse.onBatchAction = { [weak self] action, entries in
            self?.handleLibraryBrowseBatchAction(action, entries: entries)
        }
        playbackMiniPreview.isHidden = true
        playbackMiniPreview.translatesAutoresizingMaskIntoConstraints = false
        playbackMiniPreview.onExpand = { [weak self] in
            self?.collapsePlaybackLibraryOverlay()
        }
        playbackMiniPreview.onClose = { [weak self] in
            self?.closePlaybackFromMiniPreview()
        }
        playbackMiniPreview.onTogglePlayPause = { [weak self] in
            self?.togglePlayPause()
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
        mediaLibraryController.onSelectionChange = { [weak self] in
            guard let self, self.libraryChromeInstalled else { return }
            self.libraryBrowse.refreshSelection()
        }

        librarySidebarWidthConstraint = librarySidebar.widthAnchor.constraint(equalToConstant: baseLibrarySidebarWidth)
        libraryBrowseTrailingToEdgeConstraint = libraryBrowse.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        libraryBrowseWidthConstraint = libraryBrowse.widthAnchor.constraint(equalToConstant: imageLibraryBrowseWidth)
        libraryBrowseWidthConstraint?.isActive = false
        NSLayoutConstraint.activate([
            librarySidebar.topAnchor.constraint(equalTo: view.topAnchor),
            librarySidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            librarySidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            librarySidebarWidthConstraint!,

            libraryBrowse.topAnchor.constraint(equalTo: view.topAnchor),
            libraryBrowse.leadingAnchor.constraint(equalTo: librarySidebar.trailingAnchor),
            libraryBrowse.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            libraryBrowseTrailingToEdgeConstraint!,

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

    func openMediaFiles(_ urls: [URL]) {
        _ = handleDroppedURLs(urls, queueOnly: false)
    }

    func loadVideo(url: URL, replaceCurrent: Bool = true, startAt: CMTime? = nil, forceDirectMpv: Bool = false) {
        pendingVideoLoadWorkItem?.cancel()
        pendingVideoLoadWorkItem = nil
        let run = { [weak self] in
            self?.performLoadVideo(
                url: url,
                replaceCurrent: replaceCurrent,
                startAt: startAt,
                forceDirectMpv: forceDirectMpv
            )
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async {
                run()
            }
        }
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
        setPrimarySubtitlesEnabled(false)
        secondarySubtitlesEnabled = false
        cachedSubtitleTracks = []
        bitmapSubtitlesTipShownForPath = nil
        resetNativeSubtitlePresentationForSourceChange()
        stopBitmapSubtitleOverlay()
        cachedBitmapProbeTracks = []
        if mpvBackendActive {
            stopMpvBackend()
        }
        lastLoadRequestURL = url.path
        lastLoadRequestAt = now
        PlaybackTrace.emit("[DEBUG-playback] Loading video: \(url.path)")
        videoLoadGeneration += 1
        seekGeneration += 1
        resumePlaybackAfterSeek = false
        isSeekingFromUI = false
        lastPlaybackTraceSecond = -1
        let generation = videoLoadGeneration

        let previousMediaURL = currentMediaURL
        // Remember where we left the previous video before switching away.
        if let previousMediaURL,
           previousMediaURL.standardizedFileURL.path != url.standardizedFileURL.path {
            persistPlaybackResumePosition(force: true)
        }

        if let startAt {
            let sec = CMTimeGetSeconds(startAt)
            pendingStartTimeAfterLoad = sec.isFinite && sec >= 0 ? startAt : nil
        } else if isVideoFileURL(url), !isGeneratedFallbackURL(url),
                  let resumeSec = PlaybackResumeStore.resumeSeconds(for: url) {
            pendingStartTimeAfterLoad = CMTime(seconds: resumeSec, preferredTimescale: 600)
            PlaybackTrace.emit(String(format: "[DEBUG-resume] restore %.2fs path=%@", resumeSec, url.lastPathComponent))
        } else {
            pendingStartTimeAfterLoad = nil
        }

        hideCompatibilityFailure()
        renderMonitor.reset()
        freezeWatchdog.reset()
        audioOutputEnabled = true
        isUserVolumeMuted = false
        lastPlaybackStartedItemID = nil
        committedPlayerItemID = nil
        if previousMediaURL?.standardizedFileURL.path != url.standardizedFileURL.path {
            userDisabledSubtitlesForSourcePath = nil
        }
        currentMediaURL = url
        pendingLibraryFolderReveal = true
        if isVideoFileURL(url) {
            activeMediaKind = .video
        }
        if !isGeneratedFallbackURL(url) {
            beginSecurityScopedAccess(for: url)
            playbackSourceURL = url
            cachedDiscoveredCompanions = CompanionSubtitleDiscovery.discover(for: url)
            syncSubtitleTrackPopUpsToCache()
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

        if !isGeneratedFallbackURL(url) {
            if PlaybackErrorFormatter.matchesAccessProbe(url: url) {
                showCompatibilityFailure(PlaybackErrorFormatter.accessDeniedNotice(for: url))
                return
            }
            if PlaybackErrorFormatter.looksLikeMissingFile(url) {
                showCompatibilityFailure(PlaybackErrorFormatter.missingFileNotice(for: url))
                return
            }
        }

        if forceDirectMpv, MpvPlaybackController.isAvailable() {
            if isVideoFileURL(url) {
                enterInstantPlaybackPrepareUI(for: url, probeDuration: false)
            }
            PlaybackTrace.emit("[DEBUG-route] forced mpv path=\(url.path)")
            startDirectMpvPlayback(sourceURL: url, generation: generation)
            return
        }

        if !isGeneratedFallbackURL(url), PlaybackRoutePlanner.prefersFastRemux(for: url) {
            // Open-time route (includes bitmap-only → DirectMpv). Must not use empty Inputs.
            Task {
                let route = await PlaybackRoutePlanner.route(for: url)
                await MainActor.run {
                    guard generation == self.videoLoadGeneration else { return }
                    if isVideoFileURL(url) {
                        enterInstantPlaybackPrepareUI(
                            for: url,
                            probeDuration: PlaybackRoutePlanner.shouldProbeSourceDuration(for: route)
                        )
                    }
                    switch route {
                    case .directMpv(let reason):
                        PlaybackTrace.emit("[DEBUG-route] planned mpv (\(reason)) path=\(url.path)")
                        startDirectMpvPlayback(sourceURL: url, generation: generation)
                    case .compatibilityRemux(let reason):
                        PlaybackTrace.emit("[DEBUG-route] planned remux (\(reason)) path=\(url.path)")
                        startPlannedCompatibilityPlayback(sourceURL: url, generation: generation)
                    case .nativeAVFoundation:
                        PlaybackTrace.emit("[DEBUG-route] planned native path=\(url.path)")
                        startNativePlayback(url: url, generation: generation)
                    }
                }
            }
            return
        }

        if isVideoFileURL(url) {
            enterInstantPlaybackPrepareUI(for: url)
        }

        Task {
            await MainActor.run {
                guard generation == self.videoLoadGeneration else { return }
                if forceDirectMpv, MpvPlaybackController.isAvailable() {
                    PlaybackTrace.emit("[DEBUG-route] forced mpv path=\(url.path)")
                    self.startDirectMpvPlayback(sourceURL: url, generation: generation)
                    return
                }
                Task {
                    let route = await PlaybackRoutePlanner.route(for: url)
                    await MainActor.run {
                        guard generation == self.videoLoadGeneration else { return }
                        switch route {
                        case .directMpv(let reason):
                            PlaybackTrace.emit("[DEBUG-route] planned mpv (\(reason)) path=\(url.path)")
                            self.startDirectMpvPlayback(sourceURL: url, generation: generation)
                        case .compatibilityRemux(let reason):
                            PlaybackTrace.emit("[DEBUG-route] planned remux (\(reason)) path=\(url.path)")
                            self.startPlannedCompatibilityPlayback(sourceURL: url, generation: generation)
                        case .nativeAVFoundation:
                            PlaybackTrace.emit("[DEBUG-route] planned native path=\(url.path)")
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

    /// Show playback chrome and animated seek bar immediately while remux/decode prepares.
    private func enterInstantPlaybackPrepareUI(for url: URL, probeDuration: Bool = true) {
        playbackPrepareActive = true
        hideSettingsSheet()
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

        guard probeDuration else { return }

        let sourceURL = url.standardizedFileURL
        Task.detached(priority: .utility) { [weak self] in
            let sourceDuration = FFmpegVideoFallback.probeSourceDurationSec(for: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard sourceURL == self.currentMediaURL?.standardizedFileURL else { return }
                self.activePreviewSourceDurationSec = sourceDuration
                if let sourceDuration, sourceDuration > 0 {
                    self.seekSlider.maxValue = sourceDuration
                    self.totalTimeLabel.stringValue = self.formatTime(sourceDuration)
                }
                self.updateSeekBarPreparingState()
            }
        }
    }

    private func flushPendingWindowAspectIfReady() {
        guard pendingWindowAspectRefresh, !playbackPrepareActive, !fallbackInProgress else { return }
        pendingWindowAspectRefresh = false
        delegate?.playerViewController(self, didRequestWindowAspectRatio: resolvedWindowAspectRatio())
    }

    private func leavePlaybackPrepareUI() {
        guard playbackPrepareActive else { return }
        playbackPrepareActive = false
        updateSeekBarPreparingState()
        syncPlaybackBarVisibilityForCurrentState()
        flushPendingWindowAspectIfReady()
        if usesImmersiveChrome, !immersiveChromePinnedVisible {
            resetImmersiveChromeAfterMediaChange()
        }
    }

    private func startPlannedCompatibilityPlayback(sourceURL: URL, generation: Int) {
        // Do not prefetch full remux here — progressive preview must own the disk first.
        attemptFFmpegFallbackIfNeeded(plannedRoute: true, generation: generation)
    }

    private func startDirectMpvPlayback(sourceURL: URL, generation: Int) {
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
        scheduleMpvEmbed(sourceURL: sourceURL, generation: generation, attempt: 0)
    }

    private func scheduleMpvEmbed(sourceURL: URL, generation: Int, attempt: Int) {
        let attemptEmbed = { [weak self] in
            guard let self, generation == self.videoLoadGeneration else { return }
            self.view.layoutSubtreeIfNeeded()
            let surfaceReady = self.playerSurfaceView.window != nil
                && self.playerSurfaceView.bounds.width > 1
                && self.playerSurfaceView.bounds.height > 1
            let hostView = self.playerSurfaceView.mpvHostViewIfEmbedded
            if !surfaceReady || hostView == nil {
                if attempt < 12 {
                    PlaybackTrace.emit("[DEBUG-mpv] embedding not ready attempt=\(attempt); retrying")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.scheduleMpvEmbed(sourceURL: sourceURL, generation: generation, attempt: attempt + 1)
                    }
                    return
                }
                PlaybackTrace.emit("[DEBUG-mpv] embedding view not ready; falling back to remux")
                self.mpvBackendActive = false
                self.playerSurfaceView.setMpvEmbeddingActive(false)
                self.startPlannedCompatibilityPlayback(sourceURL: sourceURL, generation: generation)
                return
            }

            self.wireMpvCallbacks(generation: generation, sourceURL: sourceURL)

            self.mpvController.load(url: sourceURL, hostView: hostView!) { [weak self] result in
                guard let self, generation == self.videoLoadGeneration else { return }
                switch result {
                case .success:
                    self.leavePlaybackPrepareUI()
                    self.finishMpvPlaybackStart(sourceURL: sourceURL, generation: generation)
                case .failed(let message):
                    PlaybackTrace.emit("[DEBUG-mpv] load failed: \(message); falling back to remux")
                    self.stopMpvBackend()
                    self.startPlannedCompatibilityPlayback(sourceURL: sourceURL, generation: generation)
                }
            }
        }
        if Thread.isMainThread {
            attemptEmbed()
        } else {
            DispatchQueue.main.async {
                attemptEmbed()
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
            Task { @MainActor in
                let companions = CompanionSubtitleDiscovery.discover(for: sourceURL)
                let controller = self.mpvController
                await Task.detached {
                    controller.prepareSubtitleTracks(companionURLs: companions.map(\.url))
                }.value
                await self.refreshAudioTrackPicker()
                await self.refreshSubtitleSettings()
                await self.applyPendingCompanionSubtitleSelectionIfNeeded()
                await self.applySubtitleAppearanceToPlayback()
            }
            PlaybackTrace.emit("[DEBUG-mpv] playback started path=\(sourceURL.path)")
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
        if let source = playbackSourceURL ?? currentMediaURL, !isGeneratedFallbackURL(source) {
            PlaybackResumeStore.clear(for: source)
        }
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
            guard let self else { return }
            self.updateTimelineUI()
            let seconds = self.mpvController.currentTimeSec()
            let tick = Int(seconds)
            if tick != self.lastPlaybackTraceSecond {
                self.lastPlaybackTraceSecond = tick
                self.tracePlaybackTick(seconds: seconds)
            }
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
                    if failure.offersFileAccessSettings {
                        self.showCompatibilityFailure(failure)
                    } else {
                        self.handleNativePlaybackUnavailable(failure.userMessage)
                    }
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
                    // Remux/preview URLs that AVFoundation rejects must not re-enter the remux
                    // loop (terminate + wipe + remux forever while the tip stays up).
                    if self.isGeneratedFallbackURL(playableURL) {
                        self.leavePlaybackPrepareUI()
                        if IncompleteMediaProbe.looksLikeIncompleteDownload(at: sourceURL) {
                            self.showCompatibilityFailure(
                                PlaybackErrorFormatter.stillDownloadingNotice(for: sourceURL)
                            )
                        } else {
                            self.showCompatibilityFailure(
                                PlaybackErrorFormatter.remuxFailedNotice(for: sourceURL)
                            )
                        }
                        return
                    }
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
        PlaybackPipelinePolicy.configure(item)
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

        PlaybackTrace.emit("[DEBUG-playback] Ready to play")
        showVideoChrome()

        let pending = pendingStartTimeAfterLoad ?? .zero
        let pendingSec = CMTimeGetSeconds(pending)
        let target = (pendingSec.isFinite && pendingSec >= 0) ? pending : .zero
        pendingStartTimeAfterLoad = nil

        let startPlayback = { [weak self] in
            guard let self else { return }
            guard generation == self.videoLoadGeneration, self.isCurrentPlaybackItem(item) else { return }
            let health = PlaybackBufferHealth.classify(
                keepUp: item.isPlaybackLikelyToKeepUp,
                empty: item.isPlaybackBufferEmpty,
                full: item.isPlaybackBufferFull
            )
            PlaybackTrace.emit(String(
                format: "[DEBUG-playback] start_play buffer=%@ keepUp=%@ empty=%@ full=%@",
                health.logLabel,
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
                self.startFreezeWatchdog(for: item)
                Task {
                    await self.refreshAudioTrackPicker()
                    await self.refreshSubtitleSettings()
                }
                Task { @MainActor in
                    await PlaybackSeekStressHarness.run(
                        generation: generation,
                        currentGeneration: { self.videoLoadGeneration },
                        seekBySeconds: { self.commandSeek(bySeconds: $0) },
                        playbackRate: {
                            if self.mpvBackendActive {
                                return self.activeSession?.isPlaying == true ? self.preferredPlaybackRate : 0
                            }
                            return self.player.rate
                        },
                        currentTimeSec: {
                            if self.mpvBackendActive, let session = self.activeSession {
                                return session.currentTimeSec
                            }
                            return CMTimeGetSeconds(self.player.currentTime())
                        }
                    )
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
            let currentlyPlaying = session.isPlaying && !isMutedForSwitch
            resumePlaybackAfterSeek = CooperativeSeekResumePolicy.markPlaying(
                currentRatePlaying: currentlyPlaying,
                existingIntent: resumePlaybackAfterSeek
            )
            if currentlyPlaying { session.pause() }
            session.seek(to: seconds, exact: precise) { [weak self] finished in
                guard let self, generation == self.seekGeneration else {
                    completion?(false)
                    return
                }
                self.isSeekingFromUI = false
                self.updateTimelineUI()
                let shouldResume = CooperativeSeekResumePolicy.shouldResume(
                    intent: self.resumePlaybackAfterSeek,
                    finished: finished,
                    mutedForSwitch: self.isMutedForSwitch
                )
                self.resumePlaybackAfterSeek = false
                if shouldResume {
                    self.startPlaybackAtPreferredRate()
                }
                completion?(finished)
            }
            return
        }

        let currentlyPlaying = player.rate > 0 && !isMutedForSwitch
        resumePlaybackAfterSeek = CooperativeSeekResumePolicy.markPlaying(
            currentRatePlaying: currentlyPlaying,
            existingIntent: resumePlaybackAfterSeek
        )
        // Scrub while playing. Pausing here made every seek-bar click feel frozen
        // (rate=0 for 1s+) and raced resume when seeks overlapped.

        let tolerance = precise
            ? .zero
            : CMTime(seconds: 0.5, preferredTimescale: 600)

        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, generation == self.seekGeneration else {
                    // Superseded by a newer seek — keep sticky resume intent for that seek.
                    completion?(false)
                    return
                }
                self.isSeekingFromUI = false
                self.updateTimelineUI()
                let shouldResume = CooperativeSeekResumePolicy.shouldResume(
                    intent: self.resumePlaybackAfterSeek,
                    finished: finished,
                    mutedForSwitch: self.isMutedForSwitch
                )
                self.resumePlaybackAfterSeek = false
                if shouldResume {
                    // Always re-assert play after scrub. Seek-while-playing can leave
                    // HEVC/AVPlayerLayer showing a stuck frame while the clock advances.
                    self.startPlaybackAtPreferredRate()
                    self.kickVideoDisplayAfterSeek()
                }
                completion?(finished)
            }
        }
    }

    /// Nudge the display path after a scrub — remuxed HEVC often freezes the picture otherwise.
    private func kickVideoDisplayAfterSeek() {
        guard !mpvBackendActive else { return }
        guard player.currentItem != nil else { return }
        // Re-bind the layer player briefly; cheaper than replaceCurrentItem, enough to
        // restart frame delivery when AVPlayerLayer goes stale after a long seek.
        let surface = playerSurfaceView
        if surface.player === player {
            surface.player = nil
            surface.player = player
        }
        PlaybackTrace.emit(String(
            format: "[DEBUG-ui] seek_display_kick rate=%.2f t=%.2f",
            player.rate,
            CMTimeGetSeconds(player.currentTime())
        ))
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
        persistPlaybackResumePosition(force: true)
        if !suppressPlaybackHistoryAppend, let currentMediaURL {
            playbackHistory.append(currentMediaURL)
        }
        currentMediaURL = url
        pendingLibraryFolderReveal = true
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
        cancelImageCropMode()
        imageSelectionSession.setSourceToken(url.path)
        imageSurfaceView.setImage(loaded.image, naturalSize: loaded.pixelSize)
        imageSurfaceView.setAdjustParameters(imageAdjustSession.presentationParameters)
        refreshSubjectSelectChrome()
        // Already browsing photos in studio: swap the image without forcing the edit column open.
        let stayingInImageStudio = activeMediaKind == .image
            && playbackLibraryOverlay == .closed
        activeMediaKind = .image
        RecentlyViewedStore.shared.record(url: url, kind: .image)
        refreshImageFolderCarousel(for: url)
        if stayingInImageStudio {
            // Preserve edit-column visibility; only refresh studio chrome for the new photo.
            imageAdjustSession.setShowingBefore(false)
            applyImageBeforeAfterPresentation()
            syncImageStudioFilmstripVisibility()
            updateImageZoomPercentLabel()
            refreshImageStudioMetaBar()
            syncPlayingWindowTitle()
            updateImageStudioLayoutInsets()
            imageFolderCarousel.layoutSubtreeIfNeeded()
        } else {
            showImageChrome()
        }

        applyWindowAspectFromSettings()
    }

    private func refreshImageFolderCarousel(for url: URL) {
        let folder = url.deletingLastPathComponent()
        let sort = mediaLibraryController.browseSort
        imageFolderSiblings = MediaLibraryScanner.imageFiles(in: folder, sort: sort)
        imageFolderCarousel.setImages(imageFolderSiblings, selected: url)
        updateImageStudioLayoutInsets()
    }

    private func clearImageFolderCarousel() {
        imageFolderSiblings = []
        imageFolderCarousel.clear()
        updateImageStudioLayoutInsets()
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
        if let edgeHotZoneClickMonitor {
            NSEvent.removeMonitor(edgeHotZoneClickMonitor)
        }
        if let keyboardShortcutMonitor {
            NSEvent.removeMonitor(keyboardShortcutMonitor)
        }
        if let scrollShortcutMonitor {
            NSEvent.removeMonitor(scrollShortcutMonitor)
        }
        if let videoDoubleClickMonitor {
            NSEvent.removeMonitor(videoDoubleClickMonitor)
        }
        removeImmersivePointerMonitor()
        renderMonitor.reset()
        freezeWatchdog.reset()
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
                let notice = PlaybackErrorFormatter.playbackItemFailedNotice(
                    url: self.currentMediaURL ?? self.playbackSourceURL,
                    error: item.error
                )
                if notice.offersFileAccessSettings {
                    self.showCompatibilityFailure(notice)
                } else {
                    self.handleNativePlaybackUnavailable(notice.message)
                }
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

    private func handleLibraryBrowseBatchAction(_ action: LibraryBrowseBatchAction, entries: [LibraryBrowseEntry]) {
        switch action {
        case .play:
            let files = flattenBrowseEntriesToMedia(entries)
            guard !files.isEmpty else { return }
            playAllMedia(files)
        case .addToQueue:
            let files = flattenBrowseEntriesToMedia(entries)
            guard !files.isEmpty else { return }
            appendPlaybackQueueItems(playbackQueueItems(for: files))
        case .remove:
            handleLibraryBrowseBatchRemove(entries)
        }
    }

    private func flattenBrowseEntriesToMedia(_ entries: [LibraryBrowseEntry]) -> [LibraryMediaFile] {
        var files: [LibraryMediaFile] = []
        for entry in entries {
            switch entry.kind {
            case .media(let file):
                files.append(file)
            case .folder(let url):
                files.append(contentsOf: mediaLibraryController.mediaFiles(in: url))
            }
        }
        return files
    }

    private func handleLibraryBrowseBatchRemove(_ entries: [LibraryBrowseEntry]) {
        let count = entries.count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Move to Trash?" : "Move \(count) Items to Trash?"
        alert.informativeText = count == 1
            ? "“\(entries[0].name)” will be moved to the Trash."
            : "The selected items will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var removedCurrent = false
        for entry in entries {
            guard let url = LibraryBrowseFileActions.itemURL(for: entry) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            do {
                try LibraryBrowseFileActions.moveToTrash(url: url)
                if isDirectory.boolValue {
                    let files = mediaLibraryController.mediaFiles(in: url)
                    removeURLsFromQueue(Set(files.map(\.url)))
                } else {
                    removeURLsFromQueue([url])
                }
                if currentMediaURL?.standardizedFileURL == url.standardizedFileURL {
                    removedCurrent = true
                }
            } catch {
                LibraryBrowseFileActions.presentError(error, title: "Could Not Remove")
            }
        }
        if removedCurrent {
            suspendPlayerOutputForStillOrEmpty()
            showEmptySurface()
        }
        mediaLibraryController.reloadAfterFilesystemChange()
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
        let canGoPrevious = !playbackHistory.isEmpty
        let canGoNext = !queue.isEmpty

        queuePreviousButton.isHidden = !show
        queueNextButton.isHidden = !show
        queuePreviousButton.isEnabled = canGoPrevious
        queueNextButton.isEnabled = canGoNext

        imageQueuePreviousButton.isHidden = !show
        imageQueueNextButton.isHidden = !show
        imageQueuePreviousButton.isEnabled = canGoPrevious
        imageQueueNextButton.isEnabled = canGoNext

        attachTransportSpeedIndicatorOverlays()
        updatePlaybackSpeedTransportLabels()
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
    }

    private func detachImageAccessoryClusterFromImageControls() {
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
        persistPlaybackResumePosition(force: true)
        activeMediaKind = .empty
        playbackLibraryOverlay = .closed
        hidePlaybackMiniPreview()
        hideCompatibilityFailure()
        renderMonitor.reset()
        freezeWatchdog.reset()
        endSecurityScopedAccess()
        suspendPlayerOutputForStillOrEmpty()
        currentMediaURL = nil
        playbackSourceURL = nil
        activePlaybackFileURL = nil
        imageSurfaceView.clearImage()
        clearImageFolderCarousel()
        cancelImageCropMode()
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
        imageFolderCarousel.isHidden = true
        imageStudioMetaBar.isHidden = true
        applyLibraryBrowseLayoutMode(dockedForImageStudio: false)
        openButton.isHidden = true
        hintLabel.isHidden = true
        playerSurfaceView.isHidden = true
        dragHostView.setImageStudioGradientActive(false)
        dragHostView.setPlaybackBackdropActive(false)
        hideSettingsSheet()
        removeEdgeHotZoneClickMonitor()
        showFullMediaLibrary()
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        updateImageStudioCommitFooter()
        raisePlaybackChromeToFront()
        syncPlayingWindowTitle()
        removeImmersivePointerMonitor()
        setImmersiveChromeVisible(true, animated: false)
        applyWindowAspectFromSettings()
        installEdgeHotZoneClickMonitorIfNeeded()
        syncEdgeHotZoneAffordances()
    }

    private func showVideoChrome() {
        activeMediaKind = .video
        dismissLibraryChromeForPlayback()
        hideMediaLibrary()
        dragHostView.setImageStudioGradientActive(false)
        dragHostView.setPlaybackBackdropActive(true)
        imageSurfaceView.isHidden = true
        imageFolderCarousel.isHidden = true
        imageStudioMetaBar.isHidden = true
        cancelImageCropMode()
        clearImageFolderCarousel()
        applyLibraryBrowseLayoutMode(dockedForImageStudio: false)
        if !mpvBackendActive {
            connectPlayerToVideoSurfaces()
        }
        playerSurfaceView.isHidden = false
        imageControlsContainer.isHidden = true
        openButton.isHidden = true
        hintLabel.isHidden = true
        syncSettingsPanelGeometry()
        styleRightSettingsPanel()
        updateImageStudioLayoutInsets()
        applyContextualSettingsTabs()
        scheduleSettingsContentBottomInsetUpdate()
        updateImageStudioCommitFooter()
        raisePlaybackChromeToFront()
        schedulePlaybackBarLayoutUpdate()
        scheduleResponsiveControlsLayout()
        updatePlaybackVolumeChromeVisibility()
        syncQueueChrome()
        syncPlayingWindowTitle()
        syncPlaybackBarVisibilityForCurrentState()
        if !playbackPrepareActive && !fallbackInProgress {
            resetImmersiveChromeAfterMediaChange()
        }
        installEdgeHotZoneClickMonitorIfNeeded()
        syncEdgeHotZoneAffordances()
        DispatchQueue.main.async { [weak self] in
            self?.focusPlaybackSurfaceForTransportShortcuts()
        }
    }

    private func dismissLibraryChromeForPlayback() {
        guard libraryChromeInstalled else { return }
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = true
        libraryBrowse.isHidden = true
        hidePlaybackMiniPreview()
    }

    private func showImageChrome() {
        activeMediaKind = .image
        // Studio mode: folders / left library closed; photo padded in the main container.
        dismissLibraryChromeForPlayback()
        applyLibraryBrowseLayoutMode(dockedForImageStudio: false)
        dragHostView.setPlaybackBackdropActive(false)
        dragHostView.setImageStudioGradientActive(true)
        imageSurfaceView.isHidden = false
        playerSurfaceView.isHidden = true
        controlsContainer.isHidden = true
        openButton.isHidden = true
        hintLabel.isHidden = true
        imageAdjustSession.setShowingBefore(false)
        applyImageBeforeAfterPresentation()
        syncImageStudioFilmstripVisibility()
        updateImageZoomPercentLabel()
        refreshImageStudioMetaBar()
        applyContextualSettingsTabs()
        updateSettingsContentBottomInset()
        updateImageStudioCommitFooter()
        raisePlaybackChromeToFront()
        updatePlaybackBarWidth()
        syncQueueChrome()
        syncPlayingWindowTitle()
        // Always show the right adjust/settings panel for image studio.
        if rightSettingsSheet.isHidden {
            showSettingsSheet()
        } else {
            syncSettingsPanelGeometry()
            updateImageStudioLayoutInsets()
        }
        view.layoutSubtreeIfNeeded()
        updateImageStudioLayoutInsets()
        syncPlaybackBarVisibilityForCurrentState()
        // Keep title chrome available; do not treat this as immersive fullscreen video.
        immersiveChromeHideWorkItem?.cancel()
        immersiveChromeHideWorkItem = nil
        setImmersiveChromeVisible(true, animated: false)
        installEdgeHotZoneClickMonitorIfNeeded()
        syncEdgeHotZoneAffordances()
    }

    private func updateImageStudioLayoutInsets() {
        let isImage = activeMediaKind == .image
        let showMetaBar = isImage && !imageStudioMetaBar.isHidden
        let showCarousel = isImage && !imageFolderCarousel.isHidden && imageFolderSiblings.count >= 2 && !imageCarouselUserHidden

        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        var top: CGFloat = 0
        var bottom: CGFloat = 0

        if isImage {
            // Integrated split: photo / meta / carousel pin to the edit column leading edge
            // so opening the sidebar truly pushes the content column (not an overlay sheet).
            leading = imageStudioMargin
            top = imageStudioTopMargin

            var bottomChrome: CGFloat = 0
            if showMetaBar { bottomChrome += imageMetaBarHeight }
            if showCarousel { bottomChrome += imageCarouselHeight }
            let toolsBarHeight = imageBarHeightConstraint?.constant ?? 52
            let toolsBarReserve: CGFloat = imageControlsContainer.isHidden ? 0 : (toolsBarHeight + 10 + 8)
            bottom = -(bottomChrome + toolsBarReserve)

            if playbackLibraryOverlay != .closed, !librarySidebar.isHidden {
                let sidebarWidth = librarySidebar.bounds.width > 0
                    ? librarySidebar.bounds.width
                    : baseLibrarySidebarWidth
                leading = sidebarWidth + imageStudioMargin
                if playbackLibraryOverlay == .sidebarAndBrowse, !libraryBrowse.isHidden {
                    leading += imageLibraryBrowseWidth
                }
            }

            imageCarouselTrailingConstraint?.isActive = false
            imageMetaBarTrailingConstraint?.isActive = false
            imageSurfaceTrailingConstraint?.isActive = false
            imageCarouselTrailingToSidebarConstraint?.isActive = true
            imageMetaBarTrailingToSidebarConstraint?.isActive = true
            imageSurfaceTrailingToSidebarConstraint?.isActive = true
            imageSurfaceTrailingToSidebarConstraint?.constant = -12

            // Full-bleed meta + filmstrip; edge open/close ignores clicks over this chrome.
            imageCarouselLeadingConstraint?.constant = 0
            imageMetaBarLeadingConstraint?.constant = 0
            imageCarouselTrailingToSidebarConstraint?.constant = 0
            imageMetaBarTrailingToSidebarConstraint?.constant = 0
            imageCarouselHeightConstraint?.constant = showCarousel ? imageCarouselHeight : 0

            syncImageStudioSettingsPanelGeometry()
            syncImageStudioIntegratedChromeAppearance()
            view.layoutSubtreeIfNeeded()
            layoutImageStudioSidebarDivider()
            imageFolderCarousel.refreshEdgeFades()
            // Sidebar width changes the clip; keep the selected thumb visible (esp. first/last).
            imageFolderCarousel.recenterSelected(animated: false)
            DispatchQueue.main.async { [weak self] in
                self?.imageFolderCarousel.recenterSelected(animated: false)
            }
            trailing = 0
        } else {
            imageCarouselTrailingToSidebarConstraint?.isActive = false
            imageMetaBarTrailingToSidebarConstraint?.isActive = false
            imageSurfaceTrailingToSidebarConstraint?.isActive = false
            imageCarouselTrailingConstraint?.isActive = true
            imageMetaBarTrailingConstraint?.isActive = true
            imageSurfaceTrailingConstraint?.isActive = true

            imageCarouselLeadingConstraint?.constant = 0
            imageCarouselTrailingConstraint?.constant = 0
            imageMetaBarLeadingConstraint?.constant = 0
            imageMetaBarTrailingConstraint?.constant = 0
            imageCarouselHeightConstraint?.constant = imageCarouselHeight
            syncImageStudioSettingsPanelGeometry()
            styleRightSettingsPanel()
        }

        imageSurfaceLeadingConstraint?.constant = leading
        if !isImage {
            imageSurfaceTrailingConstraint?.constant = trailing
        }
        imageSurfaceTopConstraint?.constant = top
        imageSurfaceBottomConstraint?.constant = bottom
        syncEdgeHotZoneStripInsets()
    }

    private func imageStudioSettingsTargetWidth(scale: CGFloat) -> CGFloat {
        imageStudioSettingsPanelWidth * max(scale, 1)
    }

    private func videoSettingsTargetWidth(scale: CGFloat) -> CGFloat {
        baseSettingsPanelWidth * max(scale, 1)
    }

    private func syncSettingsPanelGeometry() {
        let scale = max(lastAppliedUIScale, 1)
        let sheetVisible = !rightSettingsSheet.isHidden

        switch activeMediaKind {
        case .image:
            settingsPanelTopConstraint?.constant = max(30, ImmersiveWindowChrome.titleBarChromeStripHeight(for: view.window))
            imageSettingsTabsTopConstraint?.constant = 12
            settingsPanelWidthConstraint?.constant = sheetVisible
                ? imageStudioSettingsTargetWidth(scale: scale)
                : 0
            if sheetVisible {
                layoutImageStudioSidebarDivider()
            }
        case .video:
            settingsPanelTopConstraint?.constant = 0
            imageSettingsTabsTopConstraint?.constant = settingsTabsTopInset
            settingsPanelWidthConstraint?.constant = sheetVisible
                ? videoSettingsTargetWidth(scale: scale)
                : 0
        case .empty:
            settingsPanelTopConstraint?.constant = 0
            settingsPanelWidthConstraint?.constant = 0
        }
    }

    /// Image studio: sit the edit column under the translucent title chrome and use a narrower width.
    private func syncImageStudioSettingsPanelGeometry() {
        syncSettingsPanelGeometry()
    }

    /// Opaque shared chrome so the edit column reads as part of the studio floor, not a floating sheet.
    private func syncImageStudioIntegratedChromeAppearance() {
        styleRightSettingsPanel()
        styleImageToolsBar()
        imageStudioMetaBar.applyStudioChromeBackground()
        imageFolderCarousel.applyStudioChromeBackground()
    }

    /// Opaque fill + separator border matching how the edit column reads over studio floor
    /// (video bar stays frosted; translucent wash would brighten over the photo).
    private func styleImageToolsBar() {
        guard activeMediaKind == .image else {
            imageToolsBarFillView.isHidden = true
            MusicStylePlaybackBar.applyChrome(to: imageControlsContainer)
            return
        }
        let appearance = view.effectiveAppearance
        imageControlsContainer.material = .contentBackground
        imageControlsContainer.blendingMode = .withinWindow
        imageControlsContainer.state = .active
        imageControlsContainer.isEmphasized = false
        imageControlsContainer.wantsLayer = true
        imageControlsContainer.layer?.cornerRadius = MusicStylePlaybackBar.barCornerRadius
        imageControlsContainer.layer?.masksToBounds = true
        imageControlsContainer.layer?.shadowOpacity = 0
        imageControlsContainer.layer?.shadowPath = nil
        // Clear VE tint — opaque fill view owns the color so the photo can’t lighten it.
        imageControlsContainer.layer?.backgroundColor = nil
        imageControlsContainer.layer?.borderWidth = 1
        imageControlsContainer.layer?.borderColor = LaughTheme.imageStudioChromeBorder(appearance: appearance).cgColor
        imageToolsBarFillView.isHidden = false
        imageToolsBarFillView.layer?.backgroundColor =
            LaughTheme.imageStudioPanelWashResolved(appearance: appearance).cgColor
        MusicStylePlaybackBar.syncRoundedShape(for: imageControlsContainer)
        imageControlsContainer.layer?.shadowOpacity = 0
    }

    private func syncImageStudioFilmstripVisibility() {
        let hasSiblings = imageFolderSiblings.count >= 2
        let showCarousel = activeMediaKind == .image && hasSiblings && !imageCarouselUserHidden
        imageFolderCarousel.isHidden = !showCarousel
        imageStudioMetaBar.isHidden = activeMediaKind != .image
        imageCarouselHeightConstraint?.constant = showCarousel ? imageCarouselHeight : 0
        syncEdgeHotZoneStripInsets()
    }

    private func refreshImageStudioMetaBar() {
        guard activeMediaKind == .image, let url = currentMediaURL else { return }
        let path = url.path
        let percent = Int((imageSurfaceView.zoomScale * 100).rounded())
        imageStudioMetaBar.configure(
            fileName: url.lastPathComponent,
            isFavorite: ImageLibraryMetaStore.isFavorite(path: path),
            rating: ImageLibraryMetaStore.rating(path: path),
            zoomPercent: percent,
            isFitZoom: imageSurfaceView.isApproximatelyFitZoom,
            carouselVisible: !imageCarouselUserHidden && imageFolderSiblings.count >= 2,
            showingBefore: imageAdjustSession.isShowingBefore
        )
    }

    private func applyImageStudioZoomMenuChoice(_ choice: ImageStudioZoomMenuChoice) {
        guard activeMediaKind == .image else { return }
        switch choice {
        case .fitScreen:
            imageSurfaceView.resetZoom()
        case .percent(let percent):
            let scale = max(0.2, min(24.0, CGFloat(percent) / 100.0))
            imageSurfaceView.setZoomScale(scale)
        }
        updateImageZoomPercentLabel()
    }

    private func toggleImageFavorite() {
        guard let url = currentMediaURL else { return }
        let path = url.path
        ImageLibraryMetaStore.setFavorite(!ImageLibraryMetaStore.isFavorite(path: path), path: path)
        refreshImageStudioMetaBar()
    }

    private func setImageRating(_ rating: Int) {
        guard let url = currentMediaURL else { return }
        ImageLibraryMetaStore.setRating(rating, path: url.path)
        refreshImageStudioMetaBar()
    }

    private func toggleImageCarouselVisibility() {
        guard imageFolderSiblings.count >= 2 else { return }
        imageCarouselUserHidden.toggle()
        syncImageStudioFilmstripVisibility()
        updateImageStudioLayoutInsets()
        refreshImageStudioMetaBar()
    }

    private func setImageBeforeAfter(showingBefore: Bool) {
        imageAdjustSession.setShowingBefore(showingBefore)
        refreshImageStudioMetaBar()
    }

    private func applyImageBeforeAfterPresentation() {
        imageSurfaceView.setAdjustParameters(imageAdjustSession.presentationParameters)
    }

    private func applyLibraryBrowseLayoutMode(dockedForImageStudio: Bool) {
        guard libraryChromeInstalled else { return }
        if dockedForImageStudio {
            libraryBrowseTrailingToEdgeConstraint?.isActive = false
            libraryBrowseWidthConstraint?.isActive = true
        } else {
            libraryBrowseWidthConstraint?.isActive = false
            libraryBrowseTrailingToEdgeConstraint?.isActive = true
        }
    }

    private func updateImageZoomPercentLabel() {
        let percent = Int((imageSurfaceView.zoomScale * 100).rounded())
        imageZoomPercentLabel.stringValue = "\(percent)%"
        if activeMediaKind == .image {
            refreshImageStudioMetaBar()
        }
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
        titleBarChromeStrip.refreshPlate()
    }

    private func styleRightSettingsPanel() {
        let appearance = view.effectiveAppearance
        // Shared column chrome for Video/Audio/Subtitles and Edits/Presets.
        rightSettingsSheet.material = .contentBackground
        rightSettingsSheet.blendingMode = .withinWindow
        rightSettingsSheet.state = .active
        rightSettingsSheet.wantsLayer = true
        rightSettingsSheet.layer?.cornerRadius = 0
        rightSettingsSheet.layer?.masksToBounds = true
        rightSettingsSheet.layer?.shadowOpacity = 0
        rightSettingsSheet.layer?.backgroundColor = nil
        settingsColumnFillView.isHidden = false
        let wash = LaughTheme.imageStudioPanelWash(appearance: appearance)
        settingsColumnFillView.layer?.backgroundColor = wash.cgColor
        let fadeFloor = LaughTheme.imageStudioFloorColor(appearance: appearance)
        settingsTopOverflowFade.floorColor = fadeFloor
        settingsBottomOverflowFade.floorColor = fadeFloor
        if rightSettingsSheet.layer?.sublayers?.contains(where: { $0.name == "imageStudioLeadingDivider" }) != true {
            let divider = CALayer()
            divider.name = "imageStudioLeadingDivider"
            rightSettingsSheet.layer?.addSublayer(divider)
        }
        layoutImageStudioSidebarDivider()

        if activeMediaKind == .image {
            styleImageToolsBar()
        } else {
            imageToolsBarFillView.isHidden = true
            MusicStylePlaybackBar.applyChrome(to: imageControlsContainer)
        }
        settingsTopOverflowFade.refreshOverflow(animated: false)
        settingsBottomOverflowFade.refreshOverflow(animated: false)
    }

    private func layoutImageStudioSidebarDivider() {
        guard let layer = rightSettingsSheet.layer,
              let divider = layer.sublayers?.first(where: { $0.name == "imageStudioLeadingDivider" })
        else { return }
        let appearance = view.effectiveAppearance
        let border = LaughTheme.imageStudioChromeBorder(appearance: appearance)
        divider.frame = CGRect(x: 0, y: 0, width: 1, height: layer.bounds.height)
        divider.backgroundColor = border.cgColor
        if activeMediaKind == .image {
            imageControlsContainer.layer?.borderColor = border.cgColor
            imageToolsBarFillView.layer?.backgroundColor =
                LaughTheme.imageStudioPanelWashResolved(appearance: appearance).cgColor
        }
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
            titlesAndSymbols: [("Edits", "slider.horizontal.3"), ("Presets", "square.grid.2x2")],
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
        applySettingsTabButtonState(
            buttons: videoSettingsTabButtons,
            headers: videoSettingsTabHeaders,
            selectedIndex: selectedVideoSettingsTabIndex
        )
        applySettingsTabButtonState(
            buttons: imageSettingsTabButtons,
            headers: imageSettingsTabHeaders,
            selectedIndex: selectedImageSettingsTabIndex
        )
    }

    private func applySettingsTabButtonState(
        buttons: [HoverTextButton],
        headers: [SettingsTabHeaderItemView],
        selectedIndex: Int
    ) {
        for (index, button) in buttons.enumerated() {
            let isActive = index == selectedIndex
            let color: NSColor
            if isActive {
                color = LaughTheme.settingsTabActive
            } else if button.isHovered {
                color = LaughTheme.settingsTabHover
            } else {
                color = LaughTheme.settingsTabIdle
            }
            button.textColor = color
            button.usesRainbowIcon = false
            // Match Edits/Presets: icon follows label idle/hover/active, not playback teal.
            button.iconTintColor = color
            button.needsDisplay = true
            if index < headers.count {
                headers[index].isActive = isActive
            }
        }
    }

    private func raisePlaybackChromeToFront() {
        // Filmstrip / meta above edge strips so thumbs & favorites receive clicks first.
        view.addSubview(imageFolderCarousel, positioned: .above, relativeTo: imageSurfaceView)
        view.addSubview(imageStudioMetaBar, positioned: .above, relativeTo: imageFolderCarousel)
        // Image studio: edit sidebar is a full-height column above the left content strip.
        if activeMediaKind == .image, !rightSettingsSheet.isHidden {
            view.addSubview(rightSettingsSheet, positioned: .above, relativeTo: imageStudioMetaBar)
            ensureSettingsTabRowsAboveContent()
        }
        view.addSubview(controlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
        view.addSubview(imageControlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
        view.addSubview(queueDropZone, positioned: .above, relativeTo: rightSettingsSheet)
        // Edge cues above content, but below filmstrip/meta so bottom chrome wins hits.
        view.addSubview(leftEdgeHotZoneAffordance, positioned: .above, relativeTo: imageControlsContainer)
        view.addSubview(rightEdgeHotZoneAffordance, positioned: .above, relativeTo: leftEdgeHotZoneAffordance)
        view.addSubview(imageFolderCarousel, positioned: .above, relativeTo: rightEdgeHotZoneAffordance)
        view.addSubview(imageStudioMetaBar, positioned: .above, relativeTo: imageFolderCarousel)
        if activeMediaKind != .image, !rightSettingsSheet.isHidden {
            ensureSettingsTabRowsAboveContent()
        }
        if libraryChromeInstalled {
            if !openButton.isHidden {
                view.addSubview(openButton, positioned: .above, relativeTo: libraryBrowse)
                view.addSubview(hintLabel, positioned: .above, relativeTo: libraryBrowse)
            }
            view.addSubview(librarySidebar, positioned: .above, relativeTo: playerSurfaceView)
            view.addSubview(libraryBrowse, positioned: .above, relativeTo: playerSurfaceView)
            view.addSubview(librarySidebar, positioned: .above, relativeTo: imageSurfaceView)
            view.addSubview(libraryBrowse, positioned: .above, relativeTo: imageFolderCarousel)
            // Folder management must sit above the floating playback/image bars.
            if playbackLibraryOverlay != .closed {
                view.addSubview(librarySidebar, positioned: .above, relativeTo: controlsContainer)
                view.addSubview(libraryBrowse, positioned: .above, relativeTo: controlsContainer)
                view.addSubview(librarySidebar, positioned: .above, relativeTo: imageControlsContainer)
                view.addSubview(libraryBrowse, positioned: .above, relativeTo: imageControlsContainer)
            }
            view.addSubview(playbackMiniPreview, positioned: .above, relativeTo: libraryBrowse)
        }
        raiseTitleBarChromeToFront()
        raiseEdgeHotZoneAffordancesToFront()
    }

    private func raiseEdgeHotZoneAffordancesToFront() {
        // Above the video surface and title chrome so the hover wash stays visible.
        view.addSubview(leftEdgeHotZoneAffordance, positioned: .above, relativeTo: playerSurfaceView)
        view.addSubview(rightEdgeHotZoneAffordance, positioned: .above, relativeTo: leftEdgeHotZoneAffordance)
        if !titleBarChromeStrip.isHidden {
            view.addSubview(leftEdgeHotZoneAffordance, positioned: .above, relativeTo: titleBarChromeStrip)
            view.addSubview(rightEdgeHotZoneAffordance, positioned: .above, relativeTo: leftEdgeHotZoneAffordance)
        }
        if !rightSettingsSheet.isHidden {
            // Keep the close-zone strip visible beside the settings column.
            view.addSubview(rightEdgeHotZoneAffordance, positioned: .above, relativeTo: rightSettingsSheet)
        }
        if activeMediaKind == .image {
            if !imageFolderCarousel.isHidden {
                view.addSubview(imageFolderCarousel, positioned: .above, relativeTo: rightEdgeHotZoneAffordance)
            }
            if !imageStudioMetaBar.isHidden {
                view.addSubview(imageStudioMetaBar, positioned: .above, relativeTo: imageFolderCarousel)
            }
            if !imageControlsContainer.isHidden {
                view.addSubview(imageControlsContainer, positioned: .above, relativeTo: imageStudioMetaBar)
            }
        }
    }

    private func setEdgeHotZonePointerCursor(_ active: Bool) {
        if active {
            guard !edgeHotZoneCursorPushed else { return }
            edgeHotZoneCursorPushed = true
            NSCursor.pointingHand.push()
        } else if edgeHotZoneCursorPushed {
            edgeHotZoneCursorPushed = false
            NSCursor.pop()
        }
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
        scheduleSettingsContentBottomInsetUpdate()
    }

    private func scheduleSettingsContentBottomInsetUpdate() {
        guard !settingsBottomInsetScheduled else { return }
        settingsBottomInsetScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settingsBottomInsetScheduled = false
            let clearance: CGFloat
            switch self.activeMediaKind {
            case .image:
                // Docked edit column — keep a small inset so the last section isn’t flush.
                // Commit footer (when visible) already lifts the scroll bottom.
                clearance = max(self.settingsPanelInnerInset, 16)
            case .empty:
                clearance = self.settingsPanelInnerInset
            case .video:
                // Side column — only a small inset; playback bar sits over the video, not this panel.
                clearance = max(self.settingsPanelInnerInset, 16)
            }
            self.settingsContentBottomConstraint?.constant = -clearance
            self.settingsTopOverflowFade.refreshOverflow(animated: false)
            self.settingsBottomOverflowFade.refreshOverflow(animated: false)
        }
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
                        self.showCompatibilityFailure(PlaybackErrorFormatter.noVideoTrackMessage())
                    }
                    return
                }
                let formatDescriptions = try await track.load(.formatDescriptions)
                if let formatDesc = formatDescriptions.first {
                    let codec = CMFormatDescriptionGetMediaSubType(formatDesc)
                    let fourCC = fourCCString(codec)
                    await MainActor.run {
                        PlaybackTrace.emit("[DEBUG-playback] video codec fourcc=\(fourCC)")
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
        scheduleTitleBarChromeLayoutUpdate()
        scheduleUIScaleUpdateIfNeeded()
        schedulePlaybackBarLayoutUpdate()
        scheduleMiniPreviewLayoutUpdate()
        scheduleResponsiveControlsLayout()
        if activeMediaKind == .image {
            layoutImageStudioSidebarDivider()
        }
    }

    private func schedulePlaybackBarLayoutUpdate() {
        guard !playbackBarLayoutUpdateScheduled else { return }
        playbackBarLayoutUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playbackBarLayoutUpdateScheduled = false
            self.updatePlaybackBarWidth()
        }
    }

    private func scheduleMiniPreviewLayoutUpdate() {
        schedulePlaybackBarLayoutUpdate()
        DispatchQueue.main.async { [weak self] in
            self?.updateMiniPreviewLayout()
        }
    }

    private func scheduleTitleBarChromeLayoutUpdate() {
        guard !titleBarLayoutUpdateScheduled else { return }
        titleBarLayoutUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.titleBarLayoutUpdateScheduled = false
            self.updateTitleBarChromeLayout()
        }
    }

    private func scheduleUIScaleUpdateIfNeeded() {
        guard !uiScaleUpdateScheduled else { return }
        uiScaleUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.uiScaleUpdateScheduled = false
            self.applyUIScaleIfNeeded()
        }
    }

    private func scheduleResponsiveControlsLayout() {
        guard !responsiveControlsLayoutScheduled else { return }
        responsiveControlsLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.responsiveControlsLayoutScheduled = false
            self.applyResponsiveControlsLayout()
        }
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
        syncSettingsPanelGeometry()

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
        showCompatibilityFailure(PlaybackUserNotice(kind: .genericPlayback, message: message))
    }

    private func showCompatibilityFailure(_ failure: PlaybackOpenFailure) {
        showCompatibilityFailure(
            PlaybackUserNotice(kind: failure.kind, message: failure.userMessage)
        )
    }

    private func showCompatibilityFailure(_ notice: PlaybackUserNotice) {
        print("[DEBUG-playback] CompatibilityFailure: \(notice.message)")
        switch notice.action {
        case .openFileAccessSettings:
            compatibilityBanner.onAction = { MacPrivacySettings.openFilesAndFoldersPrivacy() }
        case .searchOnlineSubtitles:
            compatibilityBanner.onAction = { [weak self] in
                self?.hideCompatibilityFailure()
                self?.searchOnlineSubtitlesPressed()
            }
        case .useEmbeddedBitmapSubs:
            compatibilityBanner.onAction = { [weak self] in
                self?.hideCompatibilityFailure()
                self?.restartWithEmbeddedBitmapSubs()
            }
        case nil:
            compatibilityBanner.onAction = nil
        }
        compatibilityBanner.show(
            message: notice.message,
            actionTitle: notice.actionTitle
        )
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

        if IncompleteMediaProbe.looksLikeUnreadableContainer(at: inputURL) {
            leavePlaybackPrepareUI()
            showCompatibilityFailure(PlaybackErrorFormatter.incompleteOrDamagedNotice(for: inputURL))
            PlaybackTrace.emit("[DEBUG-fallback] unreadable container header path=\(inputURL.path)")
            return
        }
        if IncompleteMediaProbe.looksLikeIncompleteDownload(at: inputURL) {
            // Header is fine — allow progressive start. Full remux stays blocked until complete.
            showCompatibilityFailure(PlaybackErrorFormatter.stillDownloadingNotice(for: inputURL))
            PlaybackTrace.emit("[DEBUG-fallback] source still downloading — progressive only path=\(inputURL.lastPathComponent)")
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

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard FFmpegVideoFallback.isAvailable() else {
                let lookup = BundledCodecTools.diagnosticSummary(for: "ffmpeg")
                await MainActor.run {
                    self.showCompatibilityFailure(
                        PlaybackErrorFormatter.decoderUnavailableMessage(lookup: lookup)
                    )
                }
                return
            }
            if !plannedRoute, FFmpegVideoFallback.shouldPreferBlockingRemux(for: inputURL) {
                await MainActor.run {
                    guard activeGeneration == self.videoLoadGeneration else { return }
                    PlaybackTrace.emit("[DEBUG-fallback] blocking remux preferred (audio transcode)")
                    self.runBlockingRemuxFallback(
                        inputURL: inputURL,
                        activeGeneration: activeGeneration,
                        resumeTime: resumeTime,
                        rawResumeTargetSec: rawResumeTargetSec,
                        plannedRoute: plannedRoute
                    )
                }
                return
            }
            let remuxStart = FFmpegVideoFallback.beginRemux(inputURL: inputURL)
            await MainActor.run {
                guard activeGeneration == self.videoLoadGeneration else { return }
                self.applyRemuxStart(
                    remuxStart,
                    inputURL: inputURL,
                    activeGeneration: activeGeneration,
                    resumeTime: resumeTime,
                    rawResumeTargetSec: rawResumeTargetSec,
                    plannedRoute: plannedRoute
                )
            }
        }
    }

    @MainActor
    private func applyRemuxStart(
        _ remuxStart: FFmpegVideoFallback.RemuxStart,
        inputURL: URL,
        activeGeneration: Int,
        resumeTime: CMTime,
        rawResumeTargetSec: Double,
        plannedRoute: Bool
    ) {
        switch remuxStart {
        case .cacheHit(let cachedURL):
            PlaybackTrace.emit("[DEBUG-fallback] cache hit path=\(cachedURL.path)")
            fallbackInProgress = true
            updateSeekBarPreparingState()
            if rawResumeTargetSec.isFinite && rawResumeTargetSec >= 0 {
                pendingStartTimeAfterLoad = resumeTime
            }
            resolveAndAttach(playableURL: cachedURL, sourceURL: inputURL, generation: activeGeneration)
        case .failed:
            showCompatibilityFailure(PlaybackErrorFormatter.remuxFailedNotice(for: inputURL))
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

        PlaybackTrace.emit("[DEBUG-fallback] preview poll preview=\(previewURL.path) full=\(fullTargetURL.path)")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Don't block preview attach on a slow incomplete-MKV duration probe.
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let sourceDuration = FFmpegVideoFallback.probeSourceDurationSec(for: inputURL)
                await MainActor.run {
                    guard sessionToken == self.fallbackSessionToken else { return }
                    self.activePreviewSourceDurationSec = sourceDuration
                    self.updateSeekBarPreparingState()
                }
            }

            let pollIntervalNs: UInt64 = 100_000_000
            let maxWaitNs: UInt64 = 120 * 1_000_000_000
            var waited: UInt64 = 0

            func attachChunkedPreviewIfPossible(waitedMs: Double) async -> Bool {
                let readable = await FFmpegVideoFallback.isPreviewReadableEnoughForPlayback(url: previewURL)
                    || FFmpegVideoFallback.isOutputReadyForPlayback(at: previewURL)
                guard readable else { return false }

                // Finished sparse remuxes of incomplete torrents advance the clock with a frozen
                // frame — refuse attach and wipe so a capped remux can replace them.
                if !FFmpegVideoFallback.isRemuxing(outputURL: previewURL),
                   IncompleteMediaProbe.looksLikeIncompleteDownload(at: inputURL),
                   FFmpegVideoFallback.remuxLooksTooSparseForPlayback(at: previewURL) {
                    PlaybackTrace.emit(
                        "[DEBUG-fallback] discard sparse progressive preview (would freeze) path=\(previewURL.lastPathComponent)"
                    )
                    try? FileManager.default.removeItem(at: previewURL)
                    return false
                }

                await MainActor.run {
                    guard sessionToken == self.fallbackSessionToken else { return }
                    self.fallbackInProgress = false
                    self.updateSeekBarPreparingState()
                    self.fallbackLastMethod = "remux-preview"
                    self.fallbackConvertedOutputPaths.insert(previewURL.path)
                    // Keep the still-downloading tip visible; don't clear it on preview start.
                    if !IncompleteMediaProbe.looksLikeIncompleteDownload(at: inputURL) {
                        self.hideCompatibilityFailure()
                    }
                    if rawResumeTargetSec.isFinite, rawResumeTargetSec > 2 {
                        PlaybackTrace.emit(String(
                            format: "[DEBUG-fallback] deferring resume %.1fs until full remux",
                            rawResumeTargetSec
                        ))
                        self.fallbackResumeTargetSec = rawResumeTargetSec
                        self.pendingStartTimeAfterLoad = .zero
                    } else if rawResumeTargetSec.isFinite, rawResumeTargetSec >= 0 {
                        self.pendingStartTimeAfterLoad = resumeTime
                    }
                    let sourceDuration = self.activePreviewSourceDurationSec
                    PlaybackTrace.emit("[DEBUG-fallback] chunked preview start waitedMs=\(waitedMs) sourceDur=\(sourceDuration ?? 0)s")
                    self.activePreviewFullTargetURL = fullTargetURL
                    self.activePlayableDurationSec = 0
                    _ = FFmpegVideoFallback.ensureBackgroundFullRemux(
                        inputURL: inputURL,
                        outputURL: fullTargetURL
                    )
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
                return true
            }

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
                        PlaybackTrace.emit("[DEBUG-fallback] full remux ready — attaching")
                        self.fallbackConvertedOutputPaths.insert(fullTargetURL.path)
                        self.resolveAndAttach(
                            playableURL: fullTargetURL,
                            sourceURL: inputURL,
                            generation: activeGeneration
                        )
                    }
                    return
                }

                let waitedMs = Double(waited) / 1_000_000
                if await attachChunkedPreviewIfPossible(waitedMs: waitedMs) {
                    return
                }

                let previewRunning = FFmpegVideoFallback.isRemuxing(outputURL: previewURL)
                let fullRunning = FFmpegVideoFallback.isBackgroundFullRemuxing(outputURL: fullTargetURL)
                if !previewRunning && !fullRunning && waited > 2_000_000_000 {
                    // Remux ended — one last attach attempt before falling back.
                    if await attachChunkedPreviewIfPossible(waitedMs: waitedMs) {
                        return
                    }
                    break
                }

                try? await Task.sleep(nanoseconds: pollIntervalNs)
                waited += pollIntervalNs
            }

            // Still-downloading sources must not enter blocking full-remux retries (always sparse).
            if IncompleteMediaProbe.looksLikeIncompleteDownload(at: inputURL) {
                let waitedMs = Double(waited) / 1_000_000
                if await attachChunkedPreviewIfPossible(waitedMs: waitedMs) {
                    return
                }
                await MainActor.run {
                    guard sessionToken == self.fallbackSessionToken else { return }
                    self.fallbackInProgress = false
                    self.leavePlaybackPrepareUI()
                    self.showCompatibilityFailure(PlaybackErrorFormatter.stillDownloadingNotice(for: inputURL))
                    self.fallbackStartedAt = nil
                    self.fallbackResumeTargetSec = nil
                    self.fallbackLastMethod = nil
                    PlaybackTrace.emit("[DEBUG-fallback] progressive preview unavailable while downloading")
                }
                return
            }

            let result = FFmpegVideoFallback.convertToPlayable(inputURL: inputURL)
            await MainActor.run {
                guard sessionToken == self.fallbackSessionToken else { return }
                self.fallbackInProgress = false
                guard let result else {
                    self.leavePlaybackPrepareUI()
                    // Planned remux (MKV etc.) used to swallow this, so a bad open looked
                    // like "buffering then nothing" with no banner.
                    self.showCompatibilityFailure(PlaybackErrorFormatter.remuxFailedNotice(for: inputURL))
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

                    let resume: CMTime
                    if let deferred = self.fallbackResumeTargetSec, deferred > 2 {
                        resume = CMTime(seconds: deferred, preferredTimescale: 600)
                        self.fallbackResumeTargetSec = nil
                    } else {
                        resume = self.player.currentTime()
                    }
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
                    // Planned remux (MKV etc.) used to swallow this, so a still-downloading
                    // torrent looked like "buffering then nothing" with no banner.
                    self.showCompatibilityFailure(PlaybackErrorFormatter.remuxFailedNotice(for: inputURL))
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
        styleIconButton(imageQueuePreviousButton, symbol: "backward.end.fill", label: "Previous in queue", pointSize: 13)
        styleIconButton(imageZoomOutButton, symbol: "minus.magnifyingglass", label: "Zoom out")
        styleIconButton(imageActualSizeButton, symbol: "1.magnifyingglass", label: "Actual size")
        styleIconButton(imageZoomInButton, symbol: "plus.magnifyingglass", label: "Zoom in")
        styleIconButton(imageFitButton, symbol: "arrow.up.left.and.arrow.down.right", label: "Fit")
        styleIconButton(imageCropButton, symbol: "crop", label: "Crop")
        styleIconButton(imageRotateLeftButton, symbol: "rotate.left", label: "Rotate left")
        styleIconButton(imageRotateRightButton, symbol: "rotate.right", label: "Rotate right")
        styleIconButton(imageQueueNextButton, symbol: "forward.end.fill", label: "Next in queue", pointSize: 13)
        pinTransportIconButtonSize(imageQueuePreviousButton)
        pinTransportIconButtonSize(imageQueueNextButton)

        imageQueuePreviousButton.target = self
        imageZoomOutButton.target = self
        imageActualSizeButton.target = self
        imageZoomInButton.target = self
        imageFitButton.target = self
        imageCropButton.target = self
        imageRotateLeftButton.target = self
        imageRotateRightButton.target = self
        imageQueueNextButton.target = self
        imageSettingsButton.target = self
        imageLibraryButton.target = self

        imageQueuePreviousButton.action = #selector(queuePreviousPressed)
        imageZoomOutButton.action = #selector(imageZoomOut)
        imageActualSizeButton.action = #selector(imageActualSize)
        imageZoomInButton.action = #selector(imageZoomIn)
        imageFitButton.action = #selector(imageFit)
        imageCropButton.action = #selector(imageCropPressed)
        imageRotateLeftButton.action = #selector(imageRotateLeft)
        imageRotateRightButton.action = #selector(imageRotateRight)
        imageQueueNextButton.action = #selector(queueNextPressed)
        imageSettingsButton.action = #selector(settingsPressed)
        imageLibraryButton.action = #selector(libraryPressed)

        imageCropBar.onAspectChange = { [weak self] in
            self?.imageCropAspectChanged()
        }
        imageCropBar.cancelButton.target = self
        imageCropBar.cancelButton.action = #selector(imageCropCancelPressed)
        imageCropBar.applyButton.target = self
        imageCropBar.applyButton.action = #selector(imageCropApplyPressed)
        imageCropBar.rotateLeftButton.target = self
        imageCropBar.rotateLeftButton.action = #selector(imageRotateLeft)
        imageCropBar.rotateRightButton.target = self
        imageCropBar.rotateRightButton.action = #selector(imageRotateRight)
        imageCropBar.flipHorizontalButton.target = self
        imageCropBar.flipHorizontalButton.action = #selector(imageCropFlipHorizontal)
        imageCropBar.flipVerticalButton.target = self
        imageCropBar.flipVerticalButton.action = #selector(imageCropFlipVertical)
        imageCropBar.isHidden = true
        imageCropBar.translatesAutoresizingMaskIntoConstraints = false

        imageQueuePreviousButton.isHidden = true
        imageQueueNextButton.isHidden = true

        imageLeadingAccessoryCluster.orientation = .horizontal
        imageLeadingAccessoryCluster.alignment = .centerY
        imageLeadingAccessoryCluster.spacing = 0
        imageLeadingAccessoryCluster.translatesAutoresizingMaskIntoConstraints = false
        imageLeadingAccessoryCluster.setContentHuggingPriority(.required, for: .horizontal)
        imageLeadingAccessoryCluster.setContentCompressionResistancePriority(.required, for: .horizontal)
        if !imageLeadingAccessoryCluster.arrangedSubviews.contains(imageLibraryButton) {
            imageLeadingAccessoryCluster.addArrangedSubview(imageLibraryButton)
        }

        imageTransportCluster.orientation = .horizontal
        imageTransportCluster.alignment = .centerY
        imageTransportCluster.distribution = .fill
        imageTransportCluster.spacing = 8
        imageTransportCluster.translatesAutoresizingMaskIntoConstraints = false
        imageTransportCluster.setContentHuggingPriority(.required, for: .horizontal)
        imageTransportCluster.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageTransportCluster.arrangedSubviews.forEach {
            imageTransportCluster.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        [
            imageQueuePreviousButton,
            imageZoomOutButton,
            imageActualSizeButton,
            imageZoomInButton,
            imageFitButton,
            imageCropButton,
            imageRotateLeftButton,
            imageRotateRightButton,
            imageQueueNextButton
        ].forEach { imageTransportCluster.addArrangedSubview($0) }

        imageAccessoryCluster.orientation = .horizontal
        imageAccessoryCluster.alignment = .centerY
        imageAccessoryCluster.spacing = 0
        imageAccessoryCluster.translatesAutoresizingMaskIntoConstraints = false
        imageAccessoryCluster.setContentHuggingPriority(.required, for: .horizontal)
        imageAccessoryCluster.setContentCompressionResistancePriority(.required, for: .horizontal)
        if !imageAccessoryCluster.arrangedSubviews.contains(imageSettingsButton) {
            imageAccessoryCluster.addArrangedSubview(imageSettingsButton)
        }
    }

    private func setupImageTopRowLayout() {
        guard !imageTopRowLayoutConfigured else { return }
        imageTopRowLayoutConfigured = true

        imageTopRowView.addSubview(imageLeadingAccessoryCluster)
        imageTopRowView.addSubview(imageTransportCluster)
        imageTopRowView.addSubview(imageAccessoryCluster)
        imageTopRowView.addSubview(imageCropBar)

        NSLayoutConstraint.activate([
            imageLeadingAccessoryCluster.leadingAnchor.constraint(
                equalTo: imageTopRowView.leadingAnchor
            ),
            imageLeadingAccessoryCluster.trailingAnchor.constraint(
                equalTo: imageTransportCluster.leadingAnchor,
                constant: -playbackControlClusterSpacing
            ),
            imageLeadingAccessoryCluster.centerYAnchor.constraint(equalTo: imageTopRowView.centerYAnchor),

            imageTransportCluster.centerXAnchor.constraint(equalTo: imageTopRowView.centerXAnchor),
            imageTransportCluster.centerYAnchor.constraint(equalTo: imageTopRowView.centerYAnchor),
            imageTransportCluster.trailingAnchor.constraint(
                lessThanOrEqualTo: imageAccessoryCluster.leadingAnchor,
                constant: -8
            ),

            imageAccessoryCluster.trailingAnchor.constraint(equalTo: imageTopRowView.trailingAnchor),
            imageAccessoryCluster.centerYAnchor.constraint(equalTo: imageTopRowView.centerYAnchor),

            imageCropBar.leadingAnchor.constraint(equalTo: imageTopRowView.leadingAnchor),
            imageCropBar.trailingAnchor.constraint(equalTo: imageTopRowView.trailingAnchor),
            imageCropBar.topAnchor.constraint(equalTo: imageTopRowView.topAnchor),
            imageCropBar.bottomAnchor.constraint(equalTo: imageTopRowView.bottomAnchor)
        ])
    }

    private func configurePlaybackAccessoryClusters() {
        playbackLeadingAccessoryCluster.translatesAutoresizingMaskIntoConstraints = false

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
        // Settings stays pinned to the far trailing edge of the top row — not in this cluster.
        settingsButton.removeFromSuperview()
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
        configureTransportSpeedLabel(playbackSpeedSlowLabel, alignment: .left)
        configureTransportSpeedLabel(playbackSpeedFastLabel, alignment: .right)
        configurePlaybackBarAccessoryButton(libraryButton, symbol: "folder", label: "Library")
        configurePlaybackBarAccessoryButton(imageLibraryButton, symbol: "folder", label: "Library")
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

        addPlaybackSettingsSection(to: videoTabView, title: "Decode", symbolName: "cpu", isFirst: true) { card in
            card.addFinalRow(SettingsRowFactory.valueRow(title: "Path", control: playbackSourcePopUp))
        }
        addPlaybackSettingsSection(to: videoTabView, title: "Playback", symbolName: "play.circle") { card in
            card.addRow(makePlaybackSpeedSectionRow())
            card.addFinalRow(SettingsRowFactory.toggleRow(title: "Loop playback", control: loopPlaybackCheckbox))
        }
        addPlaybackSettingsSection(to: videoTabView, title: "Display", symbolName: "rectangle.inset.filled") { card in
            card.addRow(SettingsRowFactory.stackedRow(title: "Scale", control: videoFitModeControl))
            card.addRow(SettingsRowFactory.stackedRow(title: "Aspect", control: windowAspectControl))
            card.addFinalRow(
                SettingsRowFactory.toggleRow(title: "Lock window to video aspect", control: lockAspectCheckbox)
            )
        }

        configureAudioSettingsTab()
        configureSubtitlesSettingsTab()

        imageTabView.arrangedSubviews.forEach {
            imageTabView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        imageFitTabView.arrangedSubviews.forEach {
            imageFitTabView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        imageSectionHeaders.removeAll()

        // Outline owns its own vertical rhythm (title → tools → next group → bottom pad).
        imageTabView.spacing = 0

        for (groupIndex, (group, tools)) in ImageDevelopOutline.groups.enumerated() {
            if groupIndex > 0 {
                let groupGap = NSView()
                groupGap.translatesAutoresizingMaskIntoConstraints = false
                groupGap.heightAnchor.constraint(equalToConstant: ImageDevelopOutlineStyle.groupSpacing).isActive = true
                imageTabView.addArrangedSubview(groupGap)
            }

            let groupColumn = NSStackView()
            groupColumn.orientation = .vertical
            groupColumn.alignment = .leading
            groupColumn.spacing = ImageDevelopOutlineStyle.titleToTools
            groupColumn.translatesAutoresizingMaskIntoConstraints = false

            let groupHeader = ImageDevelopGroupHeaderView(title: group.title)
            groupColumn.addArrangedSubview(groupHeader)
            groupHeader.widthAnchor.constraint(equalTo: groupColumn.widthAnchor).isActive = true

            let toolsColumn = NSStackView()
            toolsColumn.orientation = .vertical
            toolsColumn.alignment = .leading
            toolsColumn.spacing = ImageDevelopOutlineStyle.toolRowSpacing
            toolsColumn.translatesAutoresizingMaskIntoConstraints = false
            groupColumn.addArrangedSubview(toolsColumn)
            toolsColumn.widthAnchor.constraint(equalTo: groupColumn.widthAnchor).isActive = true

            for tool in tools {
                if tool.isSubjectSelect {
                    addSubjectSelectSection(
                        to: toolsColumn,
                        symbolName: tool.symbolName,
                        leadingGap: 0
                    )
                } else if let section = tool.adjustSection {
                    addImageAdjustSection(
                        section,
                        to: toolsColumn,
                        symbolName: tool.symbolName,
                        isFirst: true,
                        leadingGap: 0
                    ) { card in
                        self.configureImageAdjustCard(card, for: section)
                    }
                } else {
                    addImageDevelopComingSoonRow(
                        title: tool.title,
                        symbolName: tool.symbolName,
                        to: toolsColumn,
                        leadingGap: 0
                    )
                }
            }

            imageTabView.addArrangedSubview(groupColumn)
            groupColumn.widthAnchor.constraint(equalTo: imageTabView.widthAnchor).isActive = true
        }

        let outlineBottomPad = NSView()
        outlineBottomPad.translatesAutoresizingMaskIntoConstraints = false
        outlineBottomPad.heightAnchor.constraint(equalToConstant: ImageDevelopOutlineStyle.bottomPadding).isActive = true
        imageTabView.addArrangedSubview(outlineBottomPad)
        outlineBottomPad.widthAnchor.constraint(equalTo: imageTabView.widthAnchor).isActive = true

        addSettingsSection(
            to: imageFitTabView,
            title: "Looks",
            symbolName: "sparkles",
            isFirst: true
        ) { card in
            card.addFinalRow(SettingsRowFactory.fullWidthRow(makeImagePresetGrid(
                presets: [.original, .vivid, .soft, .warm, .cool]
            )))
        }

        addSettingsSection(
            to: imageFitTabView,
            title: "Mood",
            symbolName: "paintbrush.pointed"
        ) { card in
            card.addFinalRow(SettingsRowFactory.fullWidthRow(makeImagePresetGrid(
                presets: [.contrast, .dramatic, .fade, .mono, .highKey, .superContrast]
            )))
        }

        addSettingsSection(
            to: imageFitTabView,
            title: "Film",
            symbolName: "film"
        ) { card in
            card.addFinalRow(SettingsRowFactory.fullWidthRow(makeImagePresetGrid(
                presets: [.portra, .fuji, .noir]
            )))
        }

        imageSavedPresetsHost.orientation = .vertical
        imageSavedPresetsHost.alignment = .leading
        imageSavedPresetsHost.spacing = settingsStackSpacing
        imageSavedPresetsHost.translatesAutoresizingMaskIntoConstraints = false
        imageFitTabView.addArrangedSubview(imageSavedPresetsHost)
        imageSavedPresetsHost.widthAnchor.constraint(equalTo: imageFitTabView.widthAnchor).isActive = true
        refreshImageSavedPresetsSection()

        [imageTabView, imageFitTabView].forEach { stack in
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = settingsStackSpacing
            stack.translatesAutoresizingMaskIntoConstraints = false
        }
        // Edits outline uses explicit spacers; keep stack spacing at 0 so gaps don’t double.
        imageTabView.spacing = 0

        settingsContentContainer.addSubview(videoTabView)
        settingsContentContainer.addSubview(audioTabView)
        settingsContentContainer.addSubview(subtitlesTabView)
        settingsContentContainer.addSubview(imageTabView)
        settingsContentContainer.addSubview(imageFitTabView)

        [videoTabView, audioTabView, subtitlesTabView, imageTabView, imageFitTabView].forEach { tab in
            NSLayoutConstraint.activate([
                tab.leadingAnchor.constraint(equalTo: settingsContentContainer.leadingAnchor),
                tab.trailingAnchor.constraint(equalTo: settingsContentContainer.trailingAnchor),
                tab.topAnchor.constraint(equalTo: settingsContentContainer.topAnchor)
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

        let activeTab: NSView?
        switch activeMediaKind {
        case .video:
            let index = max(0, min(selectedVideoSettingsTabIndex, videoTabs.count - 1))
            selectedVideoSettingsTabIndex = index
            activeTab = videoTabs[index]
        case .image:
            let index = max(0, min(selectedImageSettingsTabIndex, imageTabs.count - 1))
            selectedImageSettingsTabIndex = index
            activeTab = imageTabs[index]
        case .empty:
            activeTab = nil
        }

        if let activeTab {
            activeTab.isHidden = false
            activeTab.alphaValue = 1
            settingsContentContainer.addSubview(activeTab)
            pinSettingsScrollDocument(to: activeTab)
        } else {
            settingsActiveTabBottomConstraint?.isActive = false
            settingsActiveTabBottomConstraint = nil
        }
        settingsContentContainer.layoutSubtreeIfNeeded()
        resetSettingsScrollPosition()
    }

    private func pinSettingsScrollDocument(to tab: NSView) {
        settingsActiveTabBottomConstraint?.isActive = false
        let bottom = tab.bottomAnchor.constraint(
            equalTo: settingsContentContainer.bottomAnchor,
            constant: -8
        )
        bottom.priority = NSLayoutConstraint.Priority.required
        settingsActiveTabBottomConstraint = bottom
        bottom.isActive = true
    }

    private func resetSettingsScrollPosition() {
        settingsContentContainer.layoutSubtreeIfNeeded()
        let clip = settingsScrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: 0))
        settingsScrollView.reflectScrolledClipView(clip)
        settingsTopOverflowFade.refreshOverflow(animated: false)
        settingsBottomOverflowFade.refreshOverflow(animated: false)
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
        let sourceNorm = source.standardizedFileURL
        if let active = activePlaybackFileURL,
           isGeneratedFallbackURL(active),
           active.standardizedFileURL != sourceNorm,
           FileManager.default.fileExists(atPath: active.path) {
            return active
        }
        guard let cached = FFmpegVideoFallback.knownCachedPlayableURL(for: source),
              cached.standardizedFileURL != sourceNorm else {
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
                alignment: .left
            )
            playbackSpeedSlowLabel.isHidden = false
        } else {
            clearTransportSpeedLabel(playbackSpeedSlowLabel)
            playbackSpeedSlowLabel.isHidden = true
        }

        if isFastSpeed {
            setTransportSpeedLabelText(
                formattedPlaybackSpeed(preferredPlaybackRate),
                on: playbackSpeedFastLabel,
                alignment: .right
            )
            playbackSpeedFastLabel.isHidden = false
        } else {
            clearTransportSpeedLabel(playbackSpeedFastLabel)
            playbackSpeedFastLabel.isHidden = true
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
        addPlaybackSettingsSection(to: audioTabView, title: "Track", symbolName: "waveform", isFirst: true) { card in
            card.addFinalRow(SettingsRowFactory.valueRow(title: "Audio", control: audioSettings.trackPopUp))
        }

        audioSettings.eqPresetPopUp.target = self
        audioSettings.eqPresetPopUp.action = #selector(audioEQPresetChanged)
        for slider in audioSettings.eqBandSliders {
            slider.target = self
            slider.action = #selector(audioEQBandChanged)
        }
        addPlaybackSettingsSection(to: audioTabView, title: "Equalizer", symbolName: "slider.vertical.3") { card in
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
        s.searchOnlineButton.target = self
        s.searchOnlineButton.action = #selector(searchOnlineSubtitlesPressed)

        let externalRow = NSStackView()
        externalRow.orientation = .horizontal
        externalRow.alignment = .centerY
        externalRow.spacing = 8
        externalRow.addArrangedSubview(s.loadExternalButton)
        externalRow.addArrangedSubview(s.searchOnlineButton)
        externalRow.addArrangedSubview(s.externalFileLabel)

        addPlaybackSettingsSection(to: subtitlesTabView, title: "Tracks", symbolName: "captions.bubble", isFirst: true) { card in
            card.addRow(self.makeSettingsSubtitleTrackBlock(
                title: "Primary",
                toggle: s.primaryEnabledSwitch,
                popUp: s.primaryTrackPopUp
            ))
            card.addFinalRow(SettingsRowFactory.fullWidthRow(externalRow))
        }

        addPlaybackSettingsSection(to: subtitlesTabView, title: "Timing", symbolName: "clock") { card in
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Delay",
                slider: s.delaySlider,
                valueLabel: s.delayValueLabel
            ))
        }

        addPlaybackSettingsSection(to: subtitlesTabView, title: "Placement", symbolName: "arrow.up.and.down.text.horizontal") { card in
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

        addPlaybackSettingsSection(to: subtitlesTabView, title: "Text style", symbolName: "textformat") { card in
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

    /// Video / Audio / Subtitles inspector sections — expanded by default (image studio stays collapsed).
    private func addPlaybackSettingsSection(
        to stack: NSStackView,
        title: String,
        symbolName: String,
        isFirst: Bool = false,
        configure: (SettingsSectionCard) -> Void
    ) {
        addSettingsSection(
            to: stack,
            title: title,
            symbolName: symbolName,
            isFirst: isFirst,
            initiallyExpanded: true,
            configure: configure
        )
    }

    private func addSettingsSection(
        to stack: NSStackView,
        title: String,
        symbolName: String,
        isFirst: Bool = false,
        initiallyExpanded: Bool = false,
        configure: (SettingsSectionCard) -> Void
    ) {
        let accentIndex = stack.arrangedSubviews.count
        let (block, _) = SettingsSectionBuilder.sectionBlock(
            title: title,
            symbolName: symbolName,
            accentIndex: accentIndex,
            isFirst: isFirst,
            initiallyExpanded: initiallyExpanded,
            configure: configure
        )
        stack.addArrangedSubview(block)
        block.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addImageAdjustSection(
        _ section: ImageAdjustSection,
        to stack: NSStackView,
        symbolName: String,
        isFirst: Bool = false,
        leadingGap: CGFloat? = nil,
        configure: (SettingsSectionCard) -> Void
    ) {
        let accentIndex = max(0, imageSectionHeaders.count)
        let (block, header) = SettingsSectionBuilder.sectionBlock(
            title: section.title,
            symbolName: symbolName,
            accentIndex: accentIndex,
            isFirst: isFirst,
            showsSectionEditActions: true,
            leadingGap: leadingGap,
            configure: configure
        )
        header.onToggleBypass = { [weak self] in
            self?.imageAdjustSession.toggleSectionBypass(section)
        }
        header.onRestoreSection = { [weak self] in
            self?.imageAdjustSession.resetSection(section)
        }
        header.onExpandedChange = { [weak self] expanded in
            guard expanded else { return }
            self?.collapseOtherImageAdjustSections(except: section)
        }
        imageSectionHeaders[section] = header
        stack.addArrangedSubview(block)
        block.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addSubjectSelectSection(
        to stack: NSStackView,
        symbolName: String,
        leadingGap: CGFloat = 0
    ) {
        let accentIndex = max(0, imageSectionHeaders.count)
        let (block, header) = SettingsSectionBuilder.sectionBlock(
            title: "Subject Select",
            symbolName: symbolName,
            accentIndex: accentIndex,
            isFirst: true,
            showsSectionEditActions: false,
            leadingGap: leadingGap
        ) { card in
            self.configureSubjectSelectCard(card)
        }
        header.onExpandedChange = { [weak self] expanded in
            guard expanded else { return }
            self?.collapseOtherImageAdjustSectionsForSubjectSelect()
        }
        imageSubjectSelectHeader = header
        stack.addArrangedSubview(block)
        block.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func collapseOtherImageAdjustSectionsForSubjectSelect() {
        for (_, header) in imageSectionHeaders {
            header.setExpanded(false, animated: true)
        }
    }

    private func configureSubjectSelectCard(_ card: SettingsSectionCard) {
        styleSubjectSelectButton(subjectSelectAutoButton)
        styleSubjectSelectButton(subjectSelectClearButton)
        styleSubjectSelectButton(subjectSelectCancelDownloadButton)
        styleSubjectSelectButton(subjectSelectExportButton)
        subjectSelectAutoButton.setAccessibilityLabel("Auto Select Person")
        subjectSelectAutoButton.toolTip = "Auto Select Person"
        subjectSelectAutoButton.target = self
        subjectSelectAutoButton.action = #selector(subjectSelectAutoPressed)
        subjectSelectClearButton.target = self
        subjectSelectClearButton.action = #selector(subjectSelectClearPressed)
        subjectSelectCancelDownloadButton.target = self
        subjectSelectCancelDownloadButton.action = #selector(subjectSelectCancelDownloadPressed)
        subjectSelectCancelDownloadButton.isHidden = true
        subjectSelectExportButton.target = self
        subjectSelectExportButton.action = #selector(subjectSelectExportPressed)

        configureSubjectSelectRefineSlider(subjectSelectSmoothSlider, action: #selector(subjectSelectRefineChanged))
        configureSubjectSelectRefineSlider(subjectSelectFeatherSlider, action: #selector(subjectSelectRefineChanged))
        configureSubjectSelectRefineSlider(subjectSelectContrastSlider, action: #selector(subjectSelectRefineChanged))
        configureSubjectSelectRefineSlider(subjectSelectShiftSlider, action: #selector(subjectSelectRefineChanged))
        configureSubjectSelectRefineSlider(subjectSelectDecontamSlider, action: #selector(subjectSelectRefineChanged))
        configureSubjectSelectRefineSlider(subjectSelectBrushRadiusSlider, action: #selector(subjectSelectBrushRadiusChanged))
        configureSettingsSegmentedControl(subjectSelectBrushModeControl, action: #selector(subjectSelectBrushModeChanged))
        subjectSelectBrushModeControl.selectedSegment = SelectionBrushMode.allCases.firstIndex(of: .refineEdge) ?? 0

        subjectSelectClickToggle.target = self
        subjectSelectClickToggle.action = #selector(subjectSelectClickToggleChanged)
        subjectSelectBrushToggle.target = self
        subjectSelectBrushToggle.action = #selector(subjectSelectBrushToggleChanged)

        subjectSelectStatusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subjectSelectStatusLabel.textColor = .secondaryLabelColor
        subjectSelectStatusLabel.maximumNumberOfLines = 3
        subjectSelectStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subjectSelectStatusLabel.stringValue = "Auto-select a person, or turn on Click Select to pick any object."

        // Primary actions — Cancel Download swaps in for Clear while downloading.
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.distribution = .fillEqually
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.addArrangedSubview(subjectSelectAutoButton)
        actions.addArrangedSubview(subjectSelectClearButton)
        actions.addArrangedSubview(subjectSelectCancelDownloadButton)
        subjectSelectAutoButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true

        card.addRow(SettingsRowFactory.fullWidthRow(actions))
        subjectSelectProgressRow = card.addRow(
            SettingsRowFactory.fullWidthRow(subjectSelectProgressView)
        )
        subjectSelectProgressRow?.isHidden = true
        subjectSelectProgressShape = (hidden: true, hasBar: false)
        card.addRow(SettingsRowFactory.sliderRow(
            title: "Smooth",
            slider: subjectSelectSmoothSlider,
            valueLabel: subjectSelectSmoothValue
        ))
        card.addRow(SettingsRowFactory.sliderRow(
            title: "Feather",
            slider: subjectSelectFeatherSlider,
            valueLabel: subjectSelectFeatherValue
        ))
        card.addRow(SettingsRowFactory.sliderRow(
            title: "Contrast",
            slider: subjectSelectContrastSlider,
            valueLabel: subjectSelectContrastValue
        ))
        card.addRow(SettingsRowFactory.sliderRow(
            title: "Shift Edge",
            slider: subjectSelectShiftSlider,
            valueLabel: subjectSelectShiftValue
        ))
        card.addRow(SettingsRowFactory.sliderRow(
            title: "Decontaminate",
            slider: subjectSelectDecontamSlider,
            valueLabel: subjectSelectDecontamValue
        ))
        card.addRow(SettingsRowFactory.toggleRow(title: "Click Select", control: subjectSelectClickToggle))
        card.addRow(SettingsRowFactory.toggleRow(title: "Brush", control: subjectSelectBrushToggle))
        card.addRow(SettingsRowFactory.stackedRow(title: "Brush Mode", control: subjectSelectBrushModeControl))
        card.addRow(SettingsRowFactory.sliderRow(
            title: "Brush Radius",
            slider: subjectSelectBrushRadiusSlider,
            valueLabel: subjectSelectBrushRadiusValue
        ))
        card.addRow(SettingsRowFactory.fullWidthRow(subjectSelectStatusLabel))
        card.addFinalRow(SettingsRowFactory.fullWidthRow(subjectSelectExportButton))
        refreshSubjectSelectChrome()
    }

    private func configureSubjectSelectRefineSlider(_ slider: NSSlider, action: Selector) {
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        slider.controlSize = .small
        slider.focusRingType = .none
        slider.useFlatBarAppearance(trackHeight: 3, filledColor: LaughTheme.interactiveAccent, showsKnob: true)
    }

    private func styleSubjectSelectButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.focusRingType = .none
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @objc private func subjectSelectAutoPressed() {
        guard let image = imageSurfaceView.selectionSourceCIImage else {
            subjectSelectStatusLabel.stringValue = "Open an image first, then run Auto Select."
            subjectSelectStatusLabel.textColor = .systemOrange
            return
        }
        imageSelectionSession.selectPerson(in: image)
        refreshSubjectSelectChrome()
    }

    @objc private func subjectSelectClearPressed() {
        imageSelectionSession.clearSelection()
        imageSurfaceView.setSelectionPreview(mask: nil, displayMode: .none, refine: .identity, quality: .full)
    }

    @objc private func subjectSelectCancelDownloadPressed() {
        imageSelectionSession.cancelModelDownload()
    }

    @objc private func subjectSelectRefineChanged() {
        let next = SelectionRefineParameters(
            smooth: subjectSelectSmoothSlider.doubleValue,
            feather: subjectSelectFeatherSlider.doubleValue,
            contrast: subjectSelectContrastSlider.doubleValue,
            shiftEdge: subjectSelectShiftSlider.doubleValue,
            decontaminate: subjectSelectDecontamSlider.doubleValue
        )
        syncSubjectSelectRefineValueLabels(next)
        imageSelectionSession.setRefine(next, preview: true)
        subjectSelectRefineSettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.imageSurfaceView.setSelectionPreview(
                mask: self.imageSelectionSession.currentMask,
                displayMode: self.imageSelectionSession.currentDisplayMode,
                refine: self.imageSelectionSession.currentRefine,
                quality: .full
            )
        }
        subjectSelectRefineSettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    @objc private func subjectSelectBrushToggleChanged() {
        subjectSelectBrushEnabled = subjectSelectBrushToggle.isOn
        if subjectSelectBrushEnabled {
            subjectSelectClickEnabled = false
            subjectSelectClickToggle.applySwitchState(false)
            imageSurfaceView.setSelectionClickEnabled(false)
        }
        imageSurfaceView.setSelectionBrushEnabled(subjectSelectBrushEnabled)
        refreshSubjectSelectChrome()
    }

    @objc private func subjectSelectClickToggleChanged() {
        subjectSelectClickEnabled = subjectSelectClickToggle.isOn
        if subjectSelectClickEnabled {
            subjectSelectBrushEnabled = false
            subjectSelectBrushToggle.applySwitchState(false)
            imageSurfaceView.setSelectionBrushEnabled(false)
        }
        imageSurfaceView.setSelectionClickEnabled(subjectSelectClickEnabled)
        refreshSubjectSelectChrome()
    }

    @objc private func subjectSelectBrushModeChanged() {
        let idx = subjectSelectBrushModeControl.selectedSegment
        guard idx >= 0, idx < SelectionBrushMode.allCases.count else { return }
        imageSelectionSession.setBrushMode(SelectionBrushMode.allCases[idx])
        refreshSubjectSelectChrome()
    }

    @objc private func subjectSelectBrushRadiusChanged() {
        let radius = CGFloat(subjectSelectBrushRadiusSlider.doubleValue)
        imageSelectionSession.setBrushRadius(radius)
        subjectSelectBrushRadiusValue.stringValue = String(format: "%.0f", radius)
        imageSurfaceView.setSelectionBrushRadius(radius)
    }

    @objc private func subjectSelectExportPressed() {
        exportSubjectCutout()
    }

    private func syncSubjectSelectRefineValueLabels(_ refine: SelectionRefineParameters) {
        subjectSelectSmoothValue.stringValue = String(format: "%.2f", refine.smooth)
        subjectSelectFeatherValue.stringValue = String(format: "%.2f", refine.feather)
        subjectSelectContrastValue.stringValue = String(format: "%.2f", refine.contrast)
        subjectSelectShiftValue.stringValue = String(format: "%+.2f", refine.shiftEdge)
        subjectSelectDecontamValue.stringValue = String(format: "%.2f", refine.decontaminate)
        subjectSelectBrushRadiusValue.stringValue = String(
            format: "%.0f",
            imageSelectionSession.currentBrushRadius
        )
    }

    private func refreshSubjectSelectChrome() {
        let hasMask = imageSelectionSession.hasSelection
        let loading = imageSelectionSession.isSelecting
        let downloading = imageSelectionSession.isDownloadingModel
        subjectSelectClearButton.isEnabled = hasMask || imageSelectionSession.error != nil
        subjectSelectClearButton.isHidden = downloading
        subjectSelectCancelDownloadButton.isHidden = !downloading
        subjectSelectCancelDownloadButton.isEnabled = downloading
        subjectSelectExportButton.isEnabled = hasMask && !loading
        subjectSelectAutoButton.isEnabled = !loading
        let refineEnabled = hasMask && !loading
        subjectSelectSmoothSlider.isEnabled = refineEnabled
        subjectSelectFeatherSlider.isEnabled = refineEnabled
        subjectSelectContrastSlider.isEnabled = refineEnabled
        subjectSelectShiftSlider.isEnabled = refineEnabled
        subjectSelectDecontamSlider.isEnabled = refineEnabled
        subjectSelectBrushToggle.isEnabled = !loading
        subjectSelectClickToggle.isEnabled = !loading
        subjectSelectBrushModeControl.isEnabled = !loading && subjectSelectBrushEnabled
        subjectSelectBrushRadiusSlider.isEnabled = !loading && subjectSelectBrushEnabled
        if !hasMask, subjectSelectBrushEnabled {
            subjectSelectBrushEnabled = false
            subjectSelectBrushToggle.applySwitchState(false)
            imageSurfaceView.setSelectionBrushEnabled(false)
        }
        subjectSelectClickToggle.applySwitchState(subjectSelectClickEnabled)
        subjectSelectBrushToggle.applySwitchState(subjectSelectBrushEnabled)

        if let brushIdx = SelectionBrushMode.allCases.firstIndex(of: imageSelectionSession.currentBrushMode) {
            subjectSelectBrushModeControl.selectedSegment = brushIdx
        }
        subjectSelectBrushRadiusSlider.doubleValue = Double(imageSelectionSession.currentBrushRadius)

        let refine = imageSelectionSession.currentRefine
        subjectSelectSmoothSlider.doubleValue = refine.smooth
        subjectSelectFeatherSlider.doubleValue = refine.feather
        subjectSelectContrastSlider.doubleValue = refine.contrast
        subjectSelectShiftSlider.doubleValue = refine.shiftEdge
        subjectSelectDecontamSlider.doubleValue = refine.decontaminate
        syncSubjectSelectRefineValueLabels(refine)

        updateSubjectSelectProgressRow()

        if downloading {
            subjectSelectStatusLabel.stringValue = "Cancel to select with the Vision fallback instead."
            subjectSelectStatusLabel.textColor = .secondaryLabelColor
        } else if loading {
            subjectSelectStatusLabel.stringValue = "Precision select (MobileSAM)…"
            subjectSelectStatusLabel.textColor = .secondaryLabelColor
        } else if let error = imageSelectionSession.error {
            subjectSelectStatusLabel.stringValue = subjectSelectErrorMessage(error)
            subjectSelectStatusLabel.textColor = .systemOrange
        } else if hasMask {
            let engineNote: String
            if imageSelectionSession.didUseVisionFallback {
                engineNote = "Vision fallback. "
            } else if case .coreML = imageSelectionSession.currentMask?.source {
                engineNote = "MobileSAM. "
            } else {
                engineNote = ""
            }
            let people = imageSelectionSession.personInstanceCount
            let peopleNote = people > 1 ? " \(people) people." : ""
            let brushNote: String
            if subjectSelectClickEnabled {
                let draft = imageSelectionSession.currentPromptDraft
                brushNote = " Click Select: click +, ⌥ −, ⇧ add; drag box. (\(draft.positivePoints.count)+ / \(draft.negativePoints.count)−)."
            } else if subjectSelectBrushEnabled {
                brushNote = " Brush: \(imageSelectionSession.currentBrushMode.menuTitle)."
            } else {
                brushNote = ""
            }
            subjectSelectStatusLabel.stringValue = "\(engineNote)Marching ants.\(peopleNote)\(brushNote)"
            subjectSelectStatusLabel.textColor = .secondaryLabelColor
        } else if subjectSelectClickEnabled {
            subjectSelectStatusLabel.stringValue = "Click Select: click object (+), ⌥-click (−), ⇧ to add; drag for box. Downloads MobileSAM if needed."
            subjectSelectStatusLabel.textColor = .secondaryLabelColor
        } else {
            subjectSelectStatusLabel.stringValue = "Auto-select a person, or turn on Click Select to pick any object."
            subjectSelectStatusLabel.textColor = .secondaryLabelColor
        }
    }

    /// Shows / hides the spinner row, re-measuring the open section when it flips (the
    /// expanded body height is a constant, so appearing rows would otherwise be clipped).
    private func updateSubjectSelectProgressRow() {
        let status = SelectionBusyStatus.make(phase: imageSelectionSession.currentPhase)
        subjectSelectProgressView.status = status
        guard let row = subjectSelectProgressRow else { return }
        // Height depends on whether the row is there and whether the bar is laid in;
        // caption text alone never changes it, so those updates skip the re-measure.
        let shape = (hidden: status == nil, hasBar: status?.fraction != nil)
        guard shape != subjectSelectProgressShape else { return }
        subjectSelectProgressShape = shape
        row.isHidden = shape.hidden
        imageSubjectSelectHeader?.refreshExpandedHeight()
    }

    private func subjectSelectErrorMessage(_ error: SelectionError) -> String {
        switch error {
        case .emptyResult:
            return "No person found in this image."
        case .pointMiss:
            return "That point is not on a person."
        case .invalidImage:
            return "Could not read this image for selection."
        case .unsupportedClass(let cls):
            return "“\(cls.rawValue)” is not available yet."
        case .modelNotReady:
            return "Selection model isn’t ready — run Auto Select or Click Select to download MobileSAM."
        }
    }

    private func exportSubjectCutout() {
        guard activeMediaKind == .image,
              let source = currentMediaURL,
              let mask = imageSelectionSession.currentMask
        else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ImageExportWriter.suggestedCutoutFileName(for: source)
        panel.title = "Export Cutout"
        panel.message = "Writes a transparent PNG. The original stays unchanged."
        panel.prompt = "Export"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let dest = panel.url else { return }
            self?.performCutoutExport(source: source, destination: dest, mask: mask)
        }
    }

    private func performCutoutExport(source: URL, destination: URL, mask: SelectionMask) {
        if destination.standardizedFileURL == source.standardizedFileURL {
            presentImageExportAlert(title: "Choose a new file", message: "Export never overwrites the original.")
            return
        }
        let parameters = imageAdjustSession.effectiveParameters
        let turns = imageSurfaceView.rotationQuarterTurns
        let crop = imageSurfaceView.appliedCropNormalized
        let straighten = imageSurfaceView.appliedStraightenRadians
        let flipH = imageSurfaceView.flipHorizontal
        let flipV = imageSurfaceView.flipVertical
        let refine = imageSelectionSession.currentRefine
        subjectSelectExportButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ImageExportWriter.renderCutoutCGImage(
                sourceURL: source,
                parameters: parameters,
                selectionMask: mask,
                quarterTurns: turns,
                cropNormalized: crop,
                straightenRadians: straighten,
                flipHorizontal: flipH,
                flipVertical: flipV,
                refine: refine
            )
            var writeError: Error?
            if let image {
                do {
                    try ImageExportWriter.write(image, to: destination, format: .png)
                } catch {
                    writeError = error
                }
            }
            DispatchQueue.main.async {
                self?.subjectSelectExportButton.isEnabled = self?.imageSelectionSession.hasSelection == true
                if image == nil {
                    self?.presentImageExportAlert(title: "Export failed", message: "Could not render the cutout.")
                } else if let writeError {
                    self?.presentImageExportAlert(title: "Export failed", message: writeError.localizedDescription)
                }
            }
        }
    }

    private func addImageDevelopComingSoonRow(
        title: String,
        symbolName: String,
        to stack: NSStackView,
        leadingGap: CGFloat = 0
    ) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        if leadingGap > 0 {
            let gap = NSView()
            gap.translatesAutoresizingMaskIntoConstraints = false
            gap.heightAnchor.constraint(equalToConstant: leadingGap).isActive = true
            container.addArrangedSubview(gap)
        }

        let row = ImageDevelopComingSoonRowView(title: title, symbolName: symbolName)
        container.addArrangedSubview(row)
        row.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        row.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true

        stack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func collapseOtherImageAdjustSections(except open: ImageAdjustSection) {
        for (section, header) in imageSectionHeaders where section != open {
            header.setExpanded(false, animated: true)
        }
        imageSubjectSelectHeader?.setExpanded(false, animated: true)
    }

    private func configureImageAdjustCard(_ card: SettingsSectionCard, for section: ImageAdjustSection) {
        switch section {
        case .develop:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Exposure",
                slider: imageAdjustControls.exposureSlider,
                valueLabel: imageAdjustControls.exposureValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Brightness",
                slider: imageAdjustControls.brightnessSlider,
                valueLabel: imageAdjustControls.brightnessValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Contrast",
                slider: imageAdjustControls.contrastSlider,
                valueLabel: imageAdjustControls.contrastValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Highlights",
                slider: imageAdjustControls.highlightsSlider,
                valueLabel: imageAdjustControls.highlightsValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Shadows",
                slider: imageAdjustControls.shadowsSlider,
                valueLabel: imageAdjustControls.shadowsValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Whites",
                slider: imageAdjustControls.whitesSlider,
                valueLabel: imageAdjustControls.whitesValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Blacks",
                slider: imageAdjustControls.blacksSlider,
                valueLabel: imageAdjustControls.blacksValueLabel
            ))
        case .color:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Saturation",
                slider: imageAdjustControls.saturationSlider,
                valueLabel: imageAdjustControls.saturationValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Vibrance",
                slider: imageAdjustControls.vibranceSlider,
                valueLabel: imageAdjustControls.vibranceValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Hue",
                slider: imageAdjustControls.hueSlider,
                valueLabel: imageAdjustControls.hueValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Temperature",
                slider: imageAdjustControls.temperatureSlider,
                valueLabel: imageAdjustControls.temperatureValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Tint",
                slider: imageAdjustControls.tintSlider,
                valueLabel: imageAdjustControls.tintValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Color balance",
                slider: imageAdjustControls.colorBalanceSlider,
                valueLabel: imageAdjustControls.colorBalanceValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Split highlights",
                slider: imageAdjustControls.splitHighlightSlider,
                valueLabel: imageAdjustControls.splitHighlightValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Split shadows",
                slider: imageAdjustControls.splitShadowSlider,
                valueLabel: imageAdjustControls.splitShadowValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Split amount",
                slider: imageAdjustControls.splitAmountSlider,
                valueLabel: imageAdjustControls.splitAmountValueLabel
            ))
        case .dramatic:
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.dramaticSlider,
                valueLabel: imageAdjustControls.dramaticValueLabel
            ))
        case .mood:
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.moodSlider,
                valueLabel: imageAdjustControls.moodValueLabel
            ))
        case .toning:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.toningAmountSlider,
                valueLabel: imageAdjustControls.toningAmountValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Highlights",
                slider: imageAdjustControls.toningHighlightsSlider,
                valueLabel: imageAdjustControls.toningHighlightsValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Shadows",
                slider: imageAdjustControls.toningShadowsSlider,
                valueLabel: imageAdjustControls.toningShadowsValueLabel
            ))
        case .matte:
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.matteSlider,
                valueLabel: imageAdjustControls.matteValueLabel
            ))
        case .glow:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.glowSlider,
                valueLabel: imageAdjustControls.glowValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Radius",
                slider: imageAdjustControls.glowRadiusSlider,
                valueLabel: imageAdjustControls.glowRadiusValueLabel
            ))
        case .blur:
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Soft focus",
                slider: imageAdjustControls.blurSlider,
                valueLabel: imageAdjustControls.blurValueLabel
            ))
        case .filmGrain:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.filmGrainSlider,
                valueLabel: imageAdjustControls.filmGrainValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Size",
                slider: imageAdjustControls.filmGrainSizeSlider,
                valueLabel: imageAdjustControls.filmGrainSizeValueLabel
            ))
        case .mystical:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.mysticalSlider,
                valueLabel: imageAdjustControls.mysticalValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Haze",
                slider: imageAdjustControls.mysticalHazeSlider,
                valueLabel: imageAdjustControls.mysticalHazeValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Hue",
                slider: imageAdjustControls.mysticalHueSlider,
                valueLabel: imageAdjustControls.mysticalHueValueLabel
            ))
        case .highKey:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.highKeySlider,
                valueLabel: imageAdjustControls.highKeyValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Softness",
                slider: imageAdjustControls.highKeySoftnessSlider,
                valueLabel: imageAdjustControls.highKeySoftnessValueLabel
            ))
        case .supercontrast:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.supercontrastSlider,
                valueLabel: imageAdjustControls.supercontrastValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Midtones",
                slider: imageAdjustControls.supercontrastMidtonesSlider,
                valueLabel: imageAdjustControls.supercontrastMidtonesValueLabel
            ))
        case .colorHarmony:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.colorHarmonySlider,
                valueLabel: imageAdjustControls.colorHarmonyValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Balance",
                slider: imageAdjustControls.colorHarmonyBalanceSlider,
                valueLabel: imageAdjustControls.colorHarmonyBalanceValueLabel
            ))
        case .sunrays:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.sunraysSlider,
                valueLabel: imageAdjustControls.sunraysValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Length",
                slider: imageAdjustControls.sunraysLengthSlider,
                valueLabel: imageAdjustControls.sunraysLengthValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Warmth",
                slider: imageAdjustControls.sunraysWarmthSlider,
                valueLabel: imageAdjustControls.sunraysWarmthValueLabel
            ))
        case .landscape:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.landscapeSlider,
                valueLabel: imageAdjustControls.landscapeValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Foliage",
                slider: imageAdjustControls.landscapeFoliageSlider,
                valueLabel: imageAdjustControls.landscapeFoliageValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Sky",
                slider: imageAdjustControls.landscapeSkySlider,
                valueLabel: imageAdjustControls.landscapeSkyValueLabel
            ))
        case .blackAndWhite:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.blackAndWhiteSlider,
                valueLabel: imageAdjustControls.blackAndWhiteValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Contrast",
                slider: imageAdjustControls.bwContrastSlider,
                valueLabel: imageAdjustControls.bwContrastValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Warmth",
                slider: imageAdjustControls.bwWarmthSlider,
                valueLabel: imageAdjustControls.bwWarmthValueLabel
            ))
        case .details:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Sharpness",
                slider: imageAdjustControls.sharpnessSlider,
                valueLabel: imageAdjustControls.sharpnessValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Definition",
                slider: imageAdjustControls.definitionSlider,
                valueLabel: imageAdjustControls.definitionValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Structure",
                slider: imageAdjustControls.structureSlider,
                valueLabel: imageAdjustControls.structureValueLabel
            ))
        case .denoise:
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Denoise",
                slider: imageAdjustControls.denoiseSlider,
                valueLabel: imageAdjustControls.denoiseValueLabel
            ))
        case .vignette:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.vignetteSlider,
                valueLabel: imageAdjustControls.vignetteValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Midpoint",
                slider: imageAdjustControls.vignetteMidpointSlider,
                valueLabel: imageAdjustControls.vignetteMidpointValueLabel
            ))
        case .dodgeBurn:
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Amount",
                slider: imageAdjustControls.dodgeBurnSlider,
                valueLabel: imageAdjustControls.dodgeBurnValueLabel
            ))
            card.addRow(SettingsRowFactory.sliderRow(
                title: "Range",
                slider: imageAdjustControls.dodgeBurnRangeSlider,
                valueLabel: imageAdjustControls.dodgeBurnRangeValueLabel
            ))
            card.addFinalRow(SettingsRowFactory.sliderRow(
                title: "Softness",
                slider: imageAdjustControls.dodgeBurnSoftnessSlider,
                valueLabel: imageAdjustControls.dodgeBurnSoftnessValueLabel
            ))
        }
    }

    private func refreshImageSectionEditChrome() {
        for section in ImageAdjustSection.allCases {
            imageSectionHeaders[section]?.setSectionEditState(
                edited: imageAdjustSession.isSectionEdited(section),
                bypassed: imageAdjustSession.isSectionBypassed(section),
                animated: true
            )
        }
        updateImageStudioCommitFooter()
    }

    private func updateImageStudioCommitFooter() {
        let geometryDirty = imageSurfaceView.hasNonIdentityCrop
            || imageSurfaceView.rotationQuarterTurns != 0
        let developDirty = imageAdjustSession.isDirty
        let selectionDirty = imageSelectionSession.hasSelection
        let show = activeMediaKind == .image
            && (developDirty || geometryDirty || selectionDirty)
            && playbackLibraryOverlay == .closed
            && !isImageCropMode
        imageStudioCommitFooter.isHidden = !show
        imageStudioCommitFooter.setShowsResetAll(developDirty || selectionDirty)
        imageStudioCommitFooterHeightConstraint?.constant = show
            ? (developDirty || selectionDirty
                ? ImageStudioCommitFooter.preferredHeight
                : ImageStudioCommitFooter.preferredHeightActionsOnly)
            : 0
        if show {
            LaughTheme.applySettingsAccentChrome(in: imageStudioCommitFooter)
        }
        updateSettingsContentBottomInset()
    }

    @objc private func imageStudioResetAllPressed() {
        // Develop adjusts only — crop / straighten / rotate / flip are framing tools
        // with their own Cancel; Reset All must not wipe an applied crop.
        imageAdjustSession.resetAll()
        imageSelectionSession.resetAll()
        imageSurfaceView.setSelectionPreview(mask: nil, displayMode: .none, refine: .identity, quality: .full)
        refreshSubjectSelectChrome()
        updateImageStudioCommitFooter()
        updateImageZoomPercentLabel()
    }

    @objc private func imageStudioExportPressed() {
        guard activeMediaKind == .image, let source = currentMediaURL else { return }
        let parameters = imageAdjustSession.effectiveParameters
        let turns = imageSurfaceView.rotationQuarterTurns
        let crop = imageSurfaceView.appliedCropNormalized
        let straighten = imageSurfaceView.appliedStraightenRadians
        let flipH = imageSurfaceView.flipHorizontal
        let flipV = imageSurfaceView.flipVertical
        let hasGeometry = turns != 0
            || flipH
            || flipV
            || !ImageCropGeometry.isIdentity(crop)
            || !ImageCropGeometry.isIdentityStraighten(straighten)
        guard !parameters.isIdentity || hasGeometry else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = ImageExportWriter.suggestedFileName(for: source)
        panel.title = "Export Image"
        panel.message = "Writes a new file. The original stays unchanged."
        panel.prompt = "Export"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let dest = panel.url else { return }
            self?.performImageExport(
                source: source,
                destination: dest,
                parameters: parameters,
                quarterTurns: turns,
                cropNormalized: crop,
                straightenRadians: straighten,
                flipHorizontal: flipH,
                flipVertical: flipV
            )
        }
    }

    private func performImageExport(
        source: URL,
        destination: URL,
        parameters: ImageAdjustParameters,
        quarterTurns: Int,
        cropNormalized: CGRect?,
        straightenRadians: CGFloat,
        flipHorizontal: Bool,
        flipVertical: Bool
    ) {
        if destination.standardizedFileURL == source.standardizedFileURL {
            presentImageExportAlert(title: "Choose a new file", message: "Export never overwrites the original.")
            return
        }
        imageStudioCommitFooter.exportButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ImageExportWriter.renderCGImage(
                sourceURL: source,
                parameters: parameters,
                quarterTurns: quarterTurns,
                cropNormalized: cropNormalized,
                straightenRadians: straightenRadians,
                flipHorizontal: flipHorizontal,
                flipVertical: flipVertical
            )
            let format = ImageExportWriter.Format.from(url: destination)
            var writeError: Error?
            if let image {
                do {
                    try ImageExportWriter.write(image, to: destination, format: format)
                } catch {
                    writeError = error
                }
            }
            DispatchQueue.main.async {
                self?.imageStudioCommitFooter.exportButton.isEnabled = true
                if image == nil {
                    self?.presentImageExportAlert(title: "Export failed", message: "Could not render the edited image.")
                } else if let writeError {
                    self?.presentImageExportAlert(title: "Export failed", message: writeError.localizedDescription)
                }
            }
        }
    }

    private func presentImageExportAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func imageStudioSavePresetPressed() {
        let parameters = imageAdjustSession.effectiveParameters
        guard !parameters.isIdentity else { return }

        let alert = NSAlert()
        alert.messageText = "Save Preset"
        alert.informativeText = "Name this look. It will appear on the Presets tab."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: "My Look")
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        field.placeholderString = "Preset name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let present: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            ImageUserPresetStore.save(name: field.stringValue, parameters: parameters)
            self?.refreshImageSavedPresetsSection()
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: present)
        } else {
            present(alert.runModal())
        }
    }

    private func refreshImageSavedPresetsSection() {
        imageSavedPresetsHost.arrangedSubviews.forEach {
            imageSavedPresetsHost.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let saved = ImageUserPresetStore.all()
        imageSavedPresetsHost.isHidden = saved.isEmpty
        guard !saved.isEmpty else { return }

        let (block, _) = SettingsSectionBuilder.sectionBlock(
            title: "Saved",
            symbolName: "bookmark.fill",
            accentIndex: imageFitTabView.arrangedSubviews.count,
            isFirst: false,
            configure: { card in
                card.addFinalRow(SettingsRowFactory.fullWidthRow(self.makeImageUserPresetGrid(presets: saved)))
            }
        )
        imageSavedPresetsHost.addArrangedSubview(block)
        block.widthAnchor.constraint(equalTo: imageSavedPresetsHost.widthAnchor).isActive = true
        LaughTheme.applySettingsAccentChrome(in: imageSavedPresetsHost)
    }

    private func makeImageUserPresetGrid(presets: [ImageUserPreset]) -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false

        let columns = 2
        var row: NSStackView?
        for (index, preset) in presets.enumerated() {
            if index % columns == 0 {
                row = NSStackView()
                row?.orientation = .horizontal
                row?.alignment = .centerY
                row?.spacing = 6
                row?.distribution = .fillEqually
                row?.translatesAutoresizingMaskIntoConstraints = false
                if let row {
                    grid.addArrangedSubview(row)
                    row.leadingAnchor.constraint(equalTo: grid.leadingAnchor).isActive = true
                    row.trailingAnchor.constraint(equalTo: grid.trailingAnchor).isActive = true
                }
            }
            let button = NSButton(title: preset.name, target: self, action: #selector(imageUserPresetPressed(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.identifier = NSUserInterfaceItemIdentifier(preset.id.uuidString)
            button.toolTip = "Apply \(preset.name)"
            row?.addArrangedSubview(button)
        }
        if let row, presets.count % columns == 1 {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(spacer)
        }
        return grid
    }

    @objc private func imageUserPresetPressed(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw),
              let preset = ImageUserPresetStore.all().first(where: { $0.id == id }) else { return }
        imageAdjustSession.apply(preset.parameters)
    }

    private func makeImagePresetGrid(presets: [ImageAdjustPreset]) -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false

        let columns = 2
        var row: NSStackView?
        for (index, preset) in presets.enumerated() {
            if index % columns == 0 {
                row = NSStackView()
                row?.orientation = .horizontal
                row?.alignment = .centerY
                row?.spacing = 6
                row?.distribution = .fillEqually
                row?.translatesAutoresizingMaskIntoConstraints = false
                if let row {
                    grid.addArrangedSubview(row)
                    row.leadingAnchor.constraint(equalTo: grid.leadingAnchor).isActive = true
                    row.trailingAnchor.constraint(equalTo: grid.trailingAnchor).isActive = true
                }
            }
            let button = makeImagePresetButton(preset)
            row?.addArrangedSubview(button)
        }
        // Pad last row so a single button doesn't stretch full width oddly.
        if let row, presets.count % columns == 1 {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(spacer)
        }
        return grid
    }

    private func makeImagePresetButton(_ preset: ImageAdjustPreset) -> NSButton {
        let button = NSButton(title: preset.title, target: self, action: #selector(imagePresetPressed(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.imagePosition = .imageLeading
        button.identifier = NSUserInterfaceItemIdentifier(preset.title)
        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: preset.symbolName, accessibilityDescription: preset.title)
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        }
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.toolTip = "Apply \(preset.title) look"
        return button
    }

    @objc private func imagePresetPressed(_ sender: NSButton) {
        let title = sender.identifier?.rawValue ?? sender.title
        guard let preset = ImageAdjustPreset.allCases.first(where: { $0.title == title }) else { return }
        imageAdjustSession.apply(preset.parameters)
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

    private func mergeCompanionSubtitleTracks(with tracks: [SubtitleTrackInfo]) -> [SubtitleTrackInfo] {
        let existingPaths = Set(tracks.compactMap { track -> String? in
            switch track.backendID {
            case .externalMpv(_, let path), .companionSidecar(let path):
                return CompanionSubtitleDiscovery.normalizePath(path)
            case .avFoundation, .mpv, .embeddedBitmapOverlay:
                return nil
            }
        })
        let companionsToAdd = cachedDiscoveredCompanions.filter {
            !existingPaths.contains(CompanionSubtitleDiscovery.normalizePath($0.url.path))
        }
        var merged = tracks
        if !companionsToAdd.isEmpty {
            merged += CompanionSubtitleDiscovery.subtitleTracks(
                from: companionsToAdd,
                startingDisplayIndex: merged.count
            )
        }
        return merged.filter { track in
            guard case .companionSidecar(let path) = track.backendID else { return true }
            let normalized = CompanionSubtitleDiscovery.normalizePath(path)
            return !merged.contains { other in
                guard case .externalMpv(_, let otherPath) = other.backendID else { return false }
                return CompanionSubtitleDiscovery.normalizePath(otherPath) == normalized
            }
        }
    }

    private func resolvedPlayableSubtitleTrack(_ track: SubtitleTrackInfo) -> SubtitleTrackInfo {
        guard case .companionSidecar(let path) = track.backendID else { return track }
        let normalized = CompanionSubtitleDiscovery.normalizePath(path)
        if let external = cachedSubtitleTracks.first(where: { candidate in
            guard case .externalMpv(_, let candidatePath) = candidate.backendID else { return false }
            return CompanionSubtitleDiscovery.normalizePath(candidatePath) == normalized
        }) {
            return external
        }
        return track
    }

    private func resolvedSubtitleTracksForUI() -> [SubtitleTrackInfo] {
        if let sourceURL = playbackSourceURL ?? currentMediaURL {
            cachedDiscoveredCompanions = CompanionSubtitleDiscovery.discover(for: sourceURL)
        }
        return mergeCompanionSubtitleTracks(with: cachedSubtitleTracks)
    }

    private func isSubtitlePlaybackReady() -> Bool {
        (mpvBackendActive && mpvPlaybackStarted)
            || bitmapOverlayActive
            || !cachedBitmapProbeTracks.isEmpty
            || nativeSubtitlePlayerItem() != nil
    }

    @MainActor
    private func setPrimarySubtitlesEnabled(_ enabled: Bool) {
        primarySubtitlesEnabled = enabled
        subtitlesSettings.primaryEnabledSwitch.applySwitchState(enabled)
        updatePlaybackSubtitleToggle()
    }

    /// Turn on the first discovered track in settings UI unless the user turned subs off for this file.
    @MainActor
    private func applySubtitleUIDefaultIfNeeded(tracks: [SubtitleTrackInfo]) {
        guard !tracks.isEmpty else { return }
        guard !primarySubtitlesEnabled else { return }
        let sourcePath = (playbackSourceURL ?? currentMediaURL)?.standardizedFileURL.path
        guard let sourcePath else { return }
        guard userDisabledSubtitlesForSourcePath != sourcePath else { return }
        setPrimarySubtitlesEnabled(true)
    }

    @MainActor
    private func syncSubtitleTrackPopUpsToCache(allowHeavyProbe: Bool = true) {
        guard activeMediaKind == .video else {
            cachedSubtitleTracks = []
            populateSubtitleTrackPopUps(tracks: [], primarySelected: nil, secondarySelected: nil)
            updateSubtitleControlsAvailability(allowHeavyProbe: false)
            return
        }
        let displayTracks = resolvedSubtitleTracksForUI()
        cachedSubtitleTracks = displayTracks
        applySubtitleUIDefaultIfNeeded(tracks: displayTracks)
        let primarySelected = primarySubtitlesEnabled ? displayTracks.first : nil
        populateSubtitleTrackPopUps(
            tracks: displayTracks,
            primarySelected: primarySelected,
            secondarySelected: nil
        )
        updateSubtitleControlsAvailability(allowHeavyProbe: allowHeavyProbe && displayTracks.isEmpty)
    }

    @MainActor
    private func applyCachedSubtitleSettingsUI() {
        syncSubtitleTrackPopUpsToCache()
    }

    @MainActor
    private func refreshSubtitleSettings(
        syncPlayback: Bool = true,
        applyAppearance: Bool = true
    ) async {
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
            if tracks.isEmpty, !cachedDiscoveredCompanions.isEmpty {
                let controller = mpvController
                let companionURLs = cachedDiscoveredCompanions.map(\.url)
                await Task.detached {
                    controller.prepareSubtitleTracks(companionURLs: companionURLs)
                }.value
                tracks = await fetchMpvSubtitleTracks()
            }
            if let sourceURL {
                tracks = tracks.map { CompanionSubtitleDiscovery.enrich($0, mediaURL: sourceURL) }
            }
        } else if bitmapOverlayActive || !cachedBitmapProbeTracks.isEmpty {
            let overlayTracks = await fetchBitmapOverlaySubtitleTracks()
            tracks = overlayTracks.isEmpty ? cachedBitmapProbeTracks : overlayTracks
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

        let availableTracks = mergeCompanionSubtitleTracks(with: tracks)
        cachedSubtitleTracks = availableTracks
        let uiSecondaryOn = subtitlesSettings.secondaryEnabledSwitch.isOn
        if availableTracks.isEmpty {
            setPrimarySubtitlesEnabled(false)
            secondarySubtitlesEnabled = false
        } else {
            applySubtitleUIDefaultIfNeeded(tracks: availableTracks)
            let sourcePath = (playbackSourceURL ?? currentMediaURL)?.standardizedFileURL.path
            if let sourcePath, userDisabledSubtitlesForSourcePath == sourcePath {
                setPrimarySubtitlesEnabled(false)
            }
            secondarySubtitlesEnabled = mpvBackendActive && mpvPlaybackStarted
                ? (await isSecondarySubtitlesEnabled() || uiSecondaryOn)
                : false
        }

        let primarySelected = primarySubtitlesEnabled
            ? await currentPrimarySubtitleTrack(in: availableTracks) ?? availableTracks.first
            : nil
        let secondarySelected = secondarySubtitlesEnabled
            ? await currentSecondarySubtitleTrack(in: availableTracks)
            : nil
        populateSubtitleTrackPopUps(
            tracks: availableTracks,
            primarySelected: primarySelected,
            secondarySelected: secondarySelected
        )
        updateCompanionSubtitlesUI()
        updateSubtitleControlsAvailability()
        maybeTipBitmapSubtitlesOnly(sourceURL: sourceURL, playableTracks: availableTracks)
        if applyAppearance {
            await applySubtitleAppearanceToPlayback()
        }
        if syncPlayback, primarySubtitlesEnabled, isSubtitlePlaybackReady() {
            await syncSubtitleSelectionFromUI(tracks: availableTracks)
        }
        updatePlaybackSubtitleToggle()
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
                await applyPrimarySubtitleTrack(resolvedPlayableSubtitleTrack(track))
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

    private func updateCompanionSubtitlesUI(allowHeavyProbe: Bool = true) {
        // Tracks no longer lists Secondary (DirectMpv-only dual subs); keep this hook for probes.
        _ = allowHeavyProbe
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
        if bitmapOverlayActive {
            let selectedID = await Task.detached { [bitmapOverlayController] in
                bitmapOverlayController.selectedSubtitleTrackID(secondary: false)
            }.value
            if let selectedID, let match = tracks.first(where: {
                if case .mpv(let id) = $0.backendID { return id == selectedID }
                return false
            }) {
                return match
            }
            return preferredBitmapTrack(in: tracks) ?? tracks.first
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
        s.primaryTrackPopUp.isEnabled = !tracks.isEmpty
        s.secondaryTrackPopUp.isEnabled = secondarySubtitlesEnabled && !tracks.isEmpty

        if let path = lastExternalSubtitlePath, !path.isEmpty {
            s.externalFileLabel.stringValue = (path as NSString).lastPathComponent
        } else {
            s.externalFileLabel.stringValue = "No external file"
        }
        suppressSubtitlePopUpAction = false
    }

    private func updateSubtitleControlsAvailability(allowHeavyProbe: Bool = true) {
        let extended = mpvBackendActive && mpvPlaybackStarted
        let nativeActive = activeMediaKind == .video && !mpvBackendActive
            && (committedPlayerItemID != nil || nativeSubtitlePlayerItem() != nil)
        let canEditAppearance = activeMediaKind == .video && (extended || nativeActive)

        subtitlesSettings.setAppearanceControlsEnabled(canEditAppearance, delayEnabled: extended)
        subtitlesSettings.setMpvExclusiveControlsEnabled(extended)

        let hasVideo = activeMediaKind == .video && (currentMediaURL != nil || playbackSourceURL != nil)
        subtitlesSettings.searchOnlineButton.isEnabled = hasVideo

        subtitlesSettings.primaryEnabledSwitch.isEnabled = !cachedSubtitleTracks.isEmpty
            || !cachedDiscoveredCompanions.isEmpty
            || lastExternalSubtitlePath != nil
        subtitlesSettings.primaryTrackPopUp.isEnabled = !cachedSubtitleTracks.isEmpty
            || !cachedDiscoveredCompanions.isEmpty
            || lastExternalSubtitlePath != nil
        subtitlesSettings.secondaryEnabledSwitch.isEnabled = extended && !cachedSubtitleTracks.isEmpty
        subtitlesSettings.secondaryTrackPopUp.isEnabled = extended && secondarySubtitlesEnabled && !cachedSubtitleTracks.isEmpty
        updateCompanionSubtitlesUI(allowHeavyProbe: allowHeavyProbe)
        updatePlaybackSubtitleToggle()
    }

    @MainActor
    func applySubtitleAppearanceToPlayback() async {
        subtitlesSettings.saveAppearanceToStore()
        let store = SettingsStore.shared

        if mpvBackendActive, mpvPlaybackStarted {
            await mpvController.applySubtitleAppearance(
                from: store,
                refreshTrack: primarySubtitlesEnabled
            )
            return
        }
        if mpvBackendActive {
            await mpvController.applySubtitleAppearance(from: store, refreshTrack: false)
            return
        }

        applyNativeSubtitleLiveStyle(from: store)
    }

    /// Immediate native subtitle styling — overlay text + AVFoundation rules, no seek / track toggle.
    @MainActor
    private func applyNativeSubtitleLiveStyle(from store: SettingsStore) {
        guard !mpvBackendActive else { return }

        if primarySubtitlesEnabled {
            syncNativeSubtitleOverlay()
            nativeSubtitleOverlay.refreshAppearance(from: store, userInitiated: true)
            if nativeSubtitleOverlay.usesSidecarPlayback, let currentSec = nativePlaybackTimeSec() {
                nativeSubtitleOverlay.updateSidecar(at: currentSec, enabled: true, store: store)
            }
        } else {
            syncNativeSubtitleOverlay()
            return
        }

        guard !nativeSubtitleOverlay.usesSidecarPlayback else { return }
        guard let item = nativeSubtitlePlayerItem(), item.status == .readyToPlay else { return }
        if let committed = committedPlayerItemID, ObjectIdentifier(item) != committed { return }

        let rules = NativeSubtitleAppearance.makeRules(from: store)
        item.textStyleRules = rules.isEmpty ? nil : rules
    }

    @MainActor
    private func syncNativeSubtitleOverlay() {
        guard !mpvBackendActive else { return }
        let store = SettingsStore.shared
        nativeSubtitleOverlay.sync(
            item: nativeSubtitlePlayerItem(),
            enabled: primarySubtitlesEnabled,
            store: store
        )
    }

    @MainActor
    private func resetNativeSubtitlePresentationForSourceChange() {
        pendingCompanionSubtitlePath = nil
        nativeSubtitleOverlay.clearSidecar()
        nativeSubtitleOverlay.detach()
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
        if !enable, let sourcePath = (playbackSourceURL ?? currentMediaURL)?.standardizedFileURL.path {
            userDisabledSubtitlesForSourcePath = sourcePath
        } else {
            userDisabledSubtitlesForSourcePath = nil
        }
        primarySubtitlesEnabledChanged()
    }

    private func hasNativePlayableSubtitleTracks() -> Bool {
        cachedSubtitleTracks.contains { track in
            if case .avFoundation = track.backendID { return true }
            return false
        }
    }

    @MainActor
    private func applyPendingCompanionSubtitleSelectionIfNeeded() async {
        guard let pendingPath = pendingCompanionSubtitlePath else { return }
        pendingCompanionSubtitlePath = nil
        let pendingNormalized = CompanionSubtitleDiscovery.normalizePath(pendingPath)
        guard let index = cachedSubtitleTracks.firstIndex(where: { track in
            switch track.backendID {
            case .externalMpv(_, let path), .companionSidecar(let path):
                return CompanionSubtitleDiscovery.normalizePath(path) == pendingNormalized
            case .avFoundation, .mpv, .embeddedBitmapOverlay:
                return false
            }
        }) else { return }

        setPrimarySubtitlesEnabled(true)
        suppressSubtitlePopUpAction = true
        subtitlesSettings.primaryTrackPopUp.selectItem(at: index + 1)
        suppressSubtitlePopUpAction = false
        updateSubtitleControlsAvailability()
        await applyPrimarySubtitleTrack(resolvedPlayableSubtitleTrack(cachedSubtitleTracks[index]))
    }

    @MainActor
    private func applyPrimarySubtitleTrack(_ track: SubtitleTrackInfo?) async {
        if let track, case .companionSidecar(let path) = track.backendID {
            if mpvBackendActive, mpvPlaybackStarted {
                let url = URL(fileURLWithPath: path)
                _ = await Task.detached { [mpvController] in
                    mpvController.addExternalSubtitle(url: url, select: true)
                }.value
                await refreshSubtitleSettings(syncPlayback: false, applyAppearance: true)
                if let refreshed = cachedSubtitleTracks.first(where: { candidate in
                    guard case .externalMpv(_, let candidatePath) = candidate.backendID else { return false }
                    return CompanionSubtitleDiscovery.normalizePath(candidatePath)
                        == CompanionSubtitleDiscovery.normalizePath(path)
                }) {
                    await applyPrimarySubtitleTrack(refreshed)
                }
                return
            }
            if SidecarSubtitleLoader.isNativeRenderableSidecar(path) {
                nativeSubtitleOverlay.loadSidecar(url: URL(fileURLWithPath: path))
                syncNativeSubtitleOverlay()
                if let currentSec = nativePlaybackTimeSec() {
                    nativeSubtitleOverlay.updateSidecar(
                        at: currentSec,
                        enabled: true,
                        store: SettingsStore.shared
                    )
                }
                return
            }
            // ASS/SSA and other non-native sidecars are not switched to DirectMpv
            // (picture blacks out on current macOS). Leave primary off.
            updatePlaybackSubtitleToggle()
            return
        }
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
            await applySubtitleAppearanceToPlayback()
            updatePlaybackSubtitleToggle()
            return
        }
        if bitmapOverlayActive || !cachedBitmapProbeTracks.isEmpty {
            if !bitmapOverlayActive,
               let url = playbackSourceURL ?? currentMediaURL,
               !isGeneratedFallbackURL(url) {
                startBitmapSubtitleOverlay(sourceURL: url)
            }
            if primarySubtitlesEnabled, let track {
                if case .mpv(let id) = track.backendID {
                    _ = await Task.detached { [bitmapOverlayController] in
                        bitmapOverlayController.setSubtitleTrackID(id, secondary: false)
                    }.value
                } else if case .embeddedBitmapOverlay(let subtitleIndex) = track.backendID {
                    _ = await Task.detached { [bitmapOverlayController] in
                        let tracks = bitmapOverlayController.subtitleTracks()
                        if subtitleIndex >= 0, subtitleIndex < tracks.count,
                           case .mpv(let id) = tracks[subtitleIndex].backendID {
                            bitmapOverlayController.setSubtitleTrackID(id, secondary: false)
                        } else {
                            bitmapOverlayController.selectPreferredSubtitleLanguage("en")
                        }
                    }.value
                }
                bitmapOverlayBlitView.isHidden = false
                bitmapOverlayBlitView.requestFrame()
            } else {
                bitmapOverlayBlitView.isHidden = true
            }
            updatePlaybackSubtitleToggle()
            return
        }
        guard let item = nativeSubtitlePlayerItem() else { return }
        if item.status != .readyToPlay {
            for _ in 0..<40 where item.status != .readyToPlay {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        guard item.status == .readyToPlay else { return }

        let resumeRate = nativeSubtitleResumeRate()

        guard let track, primarySubtitlesEnabled else {
            nativeSubtitleOverlay.clearSidecar()
            syncNativeSubtitleOverlay()
            if let item = nativeSubtitlePlayerItem() {
                _ = await NativeSubtitleSelection.disableSubtitles(on: item)
            }
            if let resumeRate {
                player.playImmediately(atRate: resumeRate)
            }
            return
        }

        if case .companionSidecar(let path) = track.backendID,
           SidecarSubtitleLoader.isNativeRenderableSidecar(path) {
            nativeSubtitleOverlay.loadSidecar(url: URL(fileURLWithPath: path))
            syncNativeSubtitleOverlay()
            if let currentSec = nativePlaybackTimeSec() {
                nativeSubtitleOverlay.updateSidecar(
                    at: currentSec,
                    enabled: true,
                    store: SettingsStore.shared
                )
            }
            if let resumeRate {
                player.playImmediately(atRate: resumeRate)
            }
            return
        }

        syncNativeSubtitleOverlay()

        let alreadySelected = await isNativeTrackSelected(track, on: item)
        if !alreadySelected {
            let applied = await NativeSubtitleSelection.select(track: track, on: item)
            if applied {
                applyNativeSubtitleLiveStyle(from: SettingsStore.shared)
            }
        } else {
            applyNativeSubtitleLiveStyle(from: SettingsStore.shared)
        }

        if let resumeRate {
            player.playImmediately(atRate: resumeRate)
        }
    }

    private func nativePlaybackTimeSec() -> Double? {
        let currentSec = CMTimeGetSeconds(player.currentTime())
        guard currentSec.isFinite else { return nil }
        return max(0, currentSec)
    }

    @MainActor
    private func nativeSubtitleResumeRate() -> Float? {
        guard !mpvBackendActive else { return nil }
        guard player.rate > 0.01 else { return nil }
        let rate = player.rate
        return rate > 0.01 ? rate : preferredPlaybackRate
    }

    @MainActor
    private func isNativeTrackSelected(_ track: SubtitleTrackInfo, on item: AVPlayerItem) async -> Bool {
        guard case .avFoundation(let optionIndex) = track.backendID else { return false }
        guard let selectedIndex = await NativeSubtitleSelection.selectedOptionIndex(for: item) else { return false }
        return selectedIndex == optionIndex
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
        setPrimarySubtitlesEnabled(enable)
        let sourcePath = (playbackSourceURL ?? currentMediaURL)?.standardizedFileURL.path
        if enable {
            userDisabledSubtitlesForSourcePath = nil
        } else if let sourcePath {
            userDisabledSubtitlesForSourcePath = sourcePath
        }
        if enable,
           !(mpvBackendActive && mpvPlaybackStarted),
           !hasNativePlayableSubtitleTracks(),
           !cachedDiscoveredCompanions.isEmpty {
            let popUpIndex = subtitlesSettings.primaryTrackPopUp.indexOfSelectedItem
            let path: String?
            if popUpIndex > 0, popUpIndex - 1 < cachedSubtitleTracks.count {
                switch cachedSubtitleTracks[popUpIndex - 1].backendID {
                case .companionSidecar(let sidecarPath):
                    path = sidecarPath
                case .externalMpv(_, let sidecarPath):
                    path = sidecarPath
                default:
                    path = cachedDiscoveredCompanions.first?.url.path
                }
            } else {
                path = cachedDiscoveredCompanions.first?.url.path
            }
            if let path, SidecarSubtitleLoader.isNativeRenderableSidecar(path) {
                updateSubtitleControlsAvailability()
                Task { await applyPrimarySubtitleFromUI(autoSelectDefault: true, enabled: true) }
                return
            }
            // Non-native sidecar formats stay listed but don’t force a DirectMpv reload.
            setPrimarySubtitlesEnabled(false)
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
        if subtitlesSettings.primaryTrackPopUp.indexOfSelectedItem > 0, !primarySubtitlesEnabled {
            setPrimarySubtitlesEnabled(true)
        }
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
        setPrimarySubtitlesEnabled(true)
        await applyPrimarySubtitleTrack(resolvedPlayableSubtitleTrack(cachedSubtitleTracks[index - 1]))
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .mpeg4Movie, .quickTimeMovie]
        panel.allowsOtherFileTypes = true
        panel.title = "Open subtitle file"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyExternalSubtitleURL(url)
    }

    @objc private func searchOnlineSubtitlesPressed() {
        guard let videoURL = playbackSourceURL ?? currentMediaURL, activeMediaKind == .video else {
            let alert = NSAlert()
            alert.messageText = "No video open"
            alert.informativeText = OpenSubtitlesClientError.noVideoOpen.userMessage
            alert.runModal()
            return
        }
        guard let hostWindow = view.window else { return }

        let sheet = OpenSubtitlesSearchSheetController()
        openSubtitlesSearchSheet = sheet
        sheet.videoURL = videoURL
        sheet.initialQuery = OpenSubtitlesQueryCleaner.query(fromFileName: videoURL.lastPathComponent)
        sheet.onAttach = { [weak self] url in
            self?.applyExternalSubtitleURL(url)
        }
        sheet.onDismiss = { [weak self] in
            self?.openSubtitlesSearchSheet = nil
        }
        sheet.prepareAndPresent(asSheetOn: hostWindow)
    }

    /// Remux keeps sharp A/V. Prefer local PGS overlay (no API key); OpenSubtitles is optional.
    private func maybeTipBitmapSubtitlesOnly(sourceURL: URL?, playableTracks: [SubtitleTrackInfo]) {
        guard !mpvBackendActive else { return }
        guard !bitmapOverlayActive else { return }
        guard cachedBitmapProbeTracks.isEmpty else { return }
        guard !nativeSubtitleOverlay.usesSidecarPlayback else { return }
        guard let sourceURL, !isGeneratedFallbackURL(sourceURL) else { return }
        let path = sourceURL.standardizedFileURL.path
        guard bitmapSubtitlesTipShownForPath != path else { return }
        if IncompleteMediaProbe.looksLikeIncompleteDownload(at: sourceURL) { return }

        let hasPlayableText = playableTracks.contains { track in
            switch track.backendID {
            case .avFoundation, .companionSidecar, .externalMpv:
                return true
            case .mpv, .embeddedBitmapOverlay:
                return false
            }
        }
        guard !hasPlayableText else { return }
        guard playableTracks.isEmpty else { return }

        let url = sourceURL
        let hasCompanions = !cachedDiscoveredCompanions.isEmpty
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let streams = FFmpegVideoFallback.probeSubtitleStreams(for: url)
            let codecs = streams.map(\.codec)
            let bitmapOnly = FFmpegProbeParser.hasBitmapSubtitlesOnly(codecs: codecs)
            guard bitmapOnly else { return }

            let probeTracks = SubtitleTrackCatalog.tracks(fromBitmapStreams: streams)
            let shouldOverlay = EmbeddedBitmapOverlayPolicy.shouldAutoAttach(
                mpvBackendActive: false,
                playableTextTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasTextSidecarActive: hasCompanions,
                libmpvAvailable: MpvPlaybackController.isAvailable()
            )

            if shouldOverlay, !probeTracks.isEmpty {
                let started = await MainActor.run { () -> Bool in
                    guard (self.playbackSourceURL ?? self.currentMediaURL)?.standardizedFileURL.path == path else {
                        return false
                    }
                    guard !self.mpvBackendActive else { return false }
                    guard !self.nativeSubtitleOverlay.usesSidecarPlayback else { return false }
                    guard !self.bitmapOverlayActive else { return true }
                    self.publishBitmapProbeTracks(probeTracks)
                    self.startBitmapSubtitleOverlay(sourceURL: url)
                    return true
                }
                if started { return }
            }

            let decision = OpenSubtitlesAutoAttach.decision(
                hasApiKey: OpenSubtitlesConfig.hasApiKey,
                playableTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasCompanionSidecar: hasCompanions
            )

            switch decision {
            case .attempt:
                await MainActor.run {
                    guard self.bitmapSubtitlesTipShownForPath != path else { return }
                    guard (self.playbackSourceURL ?? self.currentMediaURL)?.standardizedFileURL.path == path else {
                        return
                    }
                    self.bitmapSubtitlesTipShownForPath = path
                    self.showCompatibilityFailure(
                        PlaybackUserNotice(
                            kind: .bitmapSubtitlesOnly,
                            message: "Downloading text subtitles for sharp playback…"
                        )
                    )
                }
                await self.autoAttachOpenSubtitles(for: url, path: path)
            case .skip(let reason):
                await MainActor.run {
                    guard self.bitmapSubtitlesTipShownForPath != path else { return }
                    guard (self.playbackSourceURL ?? self.currentMediaURL)?.standardizedFileURL.path == path else {
                        return
                    }
                    if self.bitmapOverlayActive || !self.cachedBitmapProbeTracks.isEmpty { return }
                    self.bitmapSubtitlesTipShownForPath = path
                    let canEmbedded = MpvPresentCapability.canPresentPicture
                    self.showCompatibilityFailure(
                        PlaybackErrorFormatter.bitmapSubtitlesOnlyNotice(canUseEmbedded: canEmbedded)
                    )
                    PlaybackTrace.emit(
                        "[DEBUG-subs] bitmap-only tip reason=\(reason) path=\(url.lastPathComponent)"
                    )
                }
            }
        }
    }

    @MainActor
    private func publishBitmapProbeTracks(_ tracks: [SubtitleTrackInfo]) {
        cachedBitmapProbeTracks = tracks
        cachedSubtitleTracks = mergeCompanionSubtitleTracks(with: tracks)
        applySubtitleUIDefaultIfNeeded(tracks: cachedSubtitleTracks)
        let primarySelected = primarySubtitlesEnabled
            ? preferredBitmapTrack(in: cachedSubtitleTracks)
            : nil
        populateSubtitleTrackPopUps(
            tracks: cachedSubtitleTracks,
            primarySelected: primarySelected,
            secondarySelected: nil
        )
        updateSubtitleControlsAvailability()
        updatePlaybackSubtitleToggle()
        PlaybackTrace.emit("[DEBUG-subs] seeded \(tracks.count) PGS tracks into Subs picker")
    }

    private func preferredBitmapTrack(in tracks: [SubtitleTrackInfo]) -> SubtitleTrackInfo? {
        tracks.first { track in
            let lang = (track.language ?? "").lowercased()
            return lang.contains("english") || lang.hasPrefix("en")
        } ?? tracks.first
    }

    private func installBitmapOverlayBlitViewIfNeeded() {
        guard bitmapOverlayBlitView.superview !== playerSurfaceView else { return }
        bitmapOverlayBlitView.configureAsTransparentOverlay()
        bitmapOverlayBlitView.translatesAutoresizingMaskIntoConstraints = false
        bitmapOverlayBlitView.isHidden = true
        playerSurfaceView.addSubview(bitmapOverlayBlitView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            bitmapOverlayBlitView.leadingAnchor.constraint(equalTo: playerSurfaceView.leadingAnchor),
            bitmapOverlayBlitView.trailingAnchor.constraint(equalTo: playerSurfaceView.trailingAnchor),
            bitmapOverlayBlitView.topAnchor.constraint(equalTo: playerSurfaceView.topAnchor),
            bitmapOverlayBlitView.bottomAnchor.constraint(equalTo: playerSurfaceView.bottomAnchor)
        ])
    }

    private func startBitmapSubtitleOverlay(sourceURL: URL) {
        guard MpvPlaybackController.isAvailable() else { return }
        installBitmapOverlayBlitViewIfNeeded()
        let path = sourceURL.standardizedFileURL.path
        bitmapOverlaySourcePath = path
        bitmapOverlayBlitView.isHidden = false
        bitmapOverlayActive = true
        bitmapSubtitlesTipShownForPath = path

        PlaybackTrace.emit("[DEBUG-subs] starting PGS overlay on remux path=\(sourceURL.lastPathComponent)")
        bitmapOverlayController.loadSubtitleOverlayOnly(
            url: sourceURL,
            blitView: bitmapOverlayBlitView
        ) { [weak self] result in
            guard let self else { return }
            guard (self.playbackSourceURL ?? self.currentMediaURL)?.standardizedFileURL.path == path else {
                self.stopBitmapSubtitleOverlay()
                return
            }
            switch result {
            case .success:
                self.setPrimarySubtitlesEnabled(true)
                self.startBitmapOverlaySyncTimer()
                if let sec = self.nativePlaybackTimeSec() {
                    self.bitmapOverlayController.seek(to: sec, exact: true)
                    self.bitmapOverlayBlitView.requestFrame()
                }
                Task { await self.refreshSubtitleSettings(syncPlayback: true, applyAppearance: false) }
                self.hideCompatibilityFailure()
                PlaybackTrace.emit("[DEBUG-subs] PGS overlay ready path=\(sourceURL.lastPathComponent)")
                PlaybackTrace.emit(
                    "[DEBUG-subs] overlay uses second decode (scaled black plate) — blits off-main @~12fps"
                )
            case .failed(let message):
                PlaybackTrace.emit("[DEBUG-subs] PGS overlay failed: \(message)")
                self.stopBitmapSubtitleOverlay()
                let canEmbedded = MpvPresentCapability.canPresentPicture
                self.showCompatibilityFailure(
                    PlaybackErrorFormatter.bitmapSubtitlesOnlyNotice(canUseEmbedded: canEmbedded)
                )
            }
        }
    }

    private func stopBitmapSubtitleOverlay() {
        bitmapOverlaySyncTimer?.invalidate()
        bitmapOverlaySyncTimer = nil
        if bitmapOverlayActive || bitmapOverlayController.isRunning {
            bitmapOverlayController.terminate()
        }
        bitmapOverlayActive = false
        bitmapOverlaySourcePath = nil
        bitmapOverlayBlitView.isHidden = true
        bitmapOverlayBlitView.onRenderFrame = nil
        // Keep probe tracks so Subs picker stays populated if overlay restarts; clear only on source change.
    }

    private func startBitmapOverlaySyncTimer() {
        bitmapOverlaySyncTimer?.invalidate()
        // Drift correction only — blits come from mpv's SW update callback (off-main).
        bitmapOverlaySyncTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.syncBitmapSubtitleOverlayClock()
        }
    }

    private func syncBitmapSubtitleOverlayClock() {
        guard bitmapOverlayActive, !mpvBackendActive else { return }
        let show = primarySubtitlesEnabled
        if bitmapOverlayBlitView.isHidden == show {
            bitmapOverlayBlitView.isHidden = !show
        }
        guard show else {
            if bitmapOverlayWantPlaying {
                bitmapOverlayWantPlaying = false
                bitmapOverlayController.pause()
            }
            return
        }
        guard let sec = nativePlaybackTimeSec() else { return }
        let playing = player.rate > 0.01
        if playing != bitmapOverlayWantPlaying {
            bitmapOverlayWantPlaying = playing
            if playing {
                bitmapOverlayController.play()
            } else {
                bitmapOverlayController.pause()
            }
        }
        if playing {
            let rate = player.rate
            if abs(rate - bitmapOverlayLastRate) > 0.01 {
                bitmapOverlayLastRate = rate
                bitmapOverlayController.setSpeed(rate)
            }
        }
        // Prefer cached time-pos — never ipcQueue.sync on the UI timer.
        let mpvSec = bitmapOverlayController.currentTimeSec()
        if abs(mpvSec - sec) > 0.45 {
            bitmapOverlayController.seek(to: sec, exact: true)
        }
    }

    private func fetchBitmapOverlaySubtitleTracks() async -> [SubtitleTrackInfo] {
        guard bitmapOverlayActive else { return [] }
        return await Task.detached { [bitmapOverlayController] in
            bitmapOverlayController.subtitleTracks()
        }.value
    }

    private func autoAttachOpenSubtitles(for videoURL: URL, path: String) async {
        let client = OpenSubtitlesClient()
        let query = OpenSubtitlesQueryCleaner.query(fromFileName: videoURL.lastPathComponent)
        let language = "en"
        do {
            let results = try await client.search(query: query, language: language)
            guard let best = OpenSubtitlesAutoAttach.pickBest(from: results, preferredLanguage: language) else {
                throw OpenSubtitlesClientError.emptyResults
            }
            let (link, fileName) = try await client.requestDownload(fileID: best.fileID)
            let data = try await client.downloadFile(from: link)
            let dest = OpenSubtitlesSidecarStore.destinationURL(
                forVideo: videoURL,
                language: language,
                suggestedFileName: fileName ?? best.fileName
            )
            let written = try OpenSubtitlesSidecarStore.write(data, to: dest)
            await MainActor.run {
                guard (self.playbackSourceURL ?? self.currentMediaURL)?.standardizedFileURL.path == path else {
                    return
                }
                self.hideCompatibilityFailure()
                self.applyExternalSubtitleURL(written)
                PlaybackTrace.emit(
                    "[DEBUG-subs] auto-attached OpenSubtitles file=\(written.lastPathComponent) query=\(query)"
                )
            }
        } catch let error as OpenSubtitlesClientError {
            await MainActor.run {
                guard (self.playbackSourceURL ?? self.currentMediaURL)?.standardizedFileURL.path == path else {
                    return
                }
                let canEmbedded = MpvPresentCapability.canPresentPicture
                self.showCompatibilityFailure(
                    PlaybackUserNotice(
                        kind: .bitmapSubtitlesOnly,
                        message: error.userMessage + (canEmbedded
                            ? " Or use Embedded subs for PGS (softer picture)."
                            : " Search online from Subs, or drop an .srt next to the file."),
                        action: canEmbedded ? .useEmbeddedBitmapSubs : .searchOnlineSubtitles
                    )
                )
                PlaybackTrace.emit("[DEBUG-subs] auto-attach failed: \(error.userMessage)")
            }
        } catch {
            await MainActor.run {
                self.showCompatibilityFailure(
                    PlaybackErrorFormatter.bitmapSubtitlesOnlyNotice(
                        canUseEmbedded: MpvPresentCapability.canPresentPicture
                    )
                )
            }
        }
    }

    /// Opt-in DirectMpv software-blit so PGS can show (softer picture until Metal present).
    private func restartWithEmbeddedBitmapSubs() {
        guard let url = playbackSourceURL ?? currentMediaURL, !isGeneratedFallbackURL(url) else { return }
        guard MpvPresentCapability.canPresentPicture else {
            searchOnlineSubtitlesPressed()
            return
        }
        let resume = player.currentTime()
        stopBitmapSubtitleOverlay()
        PlaybackTrace.emit("[DEBUG-route] user opted into embedded bitmap DirectMpv path=\(url.lastPathComponent)")
        loadVideo(url: url, replaceCurrent: true, startAt: resume, forceDirectMpv: true)
    }

    /// Shared attach path for Load file… and OpenSubtitles downloads.
    private func applyExternalSubtitleURL(_ url: URL) {
        lastExternalSubtitlePath = url.path
        subtitlesSettings.externalFileLabel.stringValue = url.lastPathComponent

        if mpvBackendActive, mpvPlaybackStarted {
            attachExternalSubtitleFile(url)
            return
        }

        guard SidecarSubtitleLoader.isNativeRenderableSidecar(url.path) else {
            let alert = NSAlert()
            alert.messageText = "Unsupported subtitle file"
            alert.informativeText = "LaughPlayer can load .srt and .vtt subtitle files while playing."
            alert.runModal()
            return
        }

        nativeSubtitleOverlay.loadSidecar(url: url)
        stopBitmapSubtitleOverlay()
        setPrimarySubtitlesEnabled(true)
        syncNativeSubtitleOverlay()
        if let currentSec = nativePlaybackTimeSec() {
            nativeSubtitleOverlay.updateSidecar(
                at: currentSec,
                enabled: true,
                store: SettingsStore.shared
            )
        }
        Task { await refreshSubtitleSettings() }
    }

    private func attachExternalSubtitleFile(_ url: URL) {
        _ = mpvController.addExternalSubtitle(url: url, select: true)
        setPrimarySubtitlesEnabled(true)
        Task { await refreshSubtitleSettings() }
    }

    @objc private func resetSubtitleAppearancePressed() {
        suppressSubtitleAppearanceCallback = true
        SettingsStore.shared.resetSubtitleAppearanceToDefaults()
        subtitlesSettings.applyDefaultsToControls()
        subtitlesSettings.saveAppearanceToStore()
        subtitlesSettings.updateValueLabels()
        suppressSubtitleAppearanceCallback = false

        Task { @MainActor in
            await self.applySubtitleAppearanceToPlayback()
            await self.refreshPrimarySubtitleAfterAppearanceReset()
        }
    }

    /// Re-select the active track so native subs recover after appearance reset.
    @MainActor
    private func refreshPrimarySubtitleAfterAppearanceReset() async {
        applyNativeSubtitleLiveStyle(from: SettingsStore.shared)
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

        if mpvBackendActive {
            Task { @MainActor in
                await self.applySubtitleAppearanceToPlayback()
            }
        } else if activeMediaKind == .video {
            applyNativeSubtitleLiveStyle(from: SettingsStore.shared)
        }
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
        playbackAccessoryToVolumeConstraint?.isActive = showVolume
        volumeToSettingsConstraint?.isActive = showVolume
        playbackAccessoryToSettingsConstraint?.isActive = !showVolume
        // Hidden sibling views still keep intrinsic width in the top row unless collapsed —
        // that shoved the trailing settings gear inward vs the leading folder.
        volumeClusterCollapsedWidthConstraint?.isActive = !showVolume
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
        guard audioOutputEnabled else { return }
        let volume = effectivePlaybackVolume()
        if mpvBackendActive {
            activeSession?.setVolume(volume)
        } else {
            player.isMuted = volume < 0.01
            player.volume = volume
        }
    }

    /// Clear an in-flight switch mute when the user (or a safety net) explicitly wants sound.
    private func clearSwitchMuteIfNeeded() {
        guard isMutedForSwitch else { return }
        isMutedForSwitch = false
        PlaybackTrace.emit("[DEBUG-playback] cleared stuck switch-mute")
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
        guard audioOutputEnabled else { return }
        clearSwitchMuteIfNeeded()
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
        // Flat EQ still ran lavfi and could color/glitch audio under SW present load.
        if bands.allSatisfy({ abs($0) < 0.05 }) {
            mpvController.clearPlaybackEQ()
        } else {
            mpvController.applyPlaybackEQ(gains: bands)
        }
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

    private func makeSettingsPopUpRow(title: String, popUp: NSPopUpButton) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)

        popUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popUp.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        row.addArrangedSubview(label)
        row.addArrangedSubview(popUp)
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
        guard !playbackPrepareActive, !fallbackInProgress else {
            pendingWindowAspectRefresh = true
            return
        }
        delegate?.playerViewController(self, didRequestWindowAspectRatio: resolvedWindowAspectRatio())
    }

    /// Aspect ratio to enforce on the main window, or nil when the library/empty/image studio should resize freely.
    func resolvedWindowAspectRatio() -> CGFloat? {
        // Image studio is a padded layout — never lock the window to the photo aspect
        // (that snaps the frame back after live resize).
        guard activeMediaKind == .video else { return nil }

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
        // Play must never leave a stuck switch-mute or zeroed AVPlayer volume behind —
        // common after freeze recovery / item rebind / long HEVC sessions.
        if isMutedForSwitch {
            restoreAudioAfterSwitchSmoothly()
        } else {
            ensureLaughVolumeIfPlaying()
        }
        if mpvBackendActive {
            activeSession?.setRate(preferredPlaybackRate)
            activeSession?.play()
        } else {
            player.play()
            if preferredPlaybackRate != 1.0 {
                player.rate = preferredPlaybackRate
            }
            // Re-assert volume after play(); some AVPlayer stalls clear mute flags only briefly.
            ensureLaughVolumeIfPlaying()
        }
        updatePlayPauseButtonIcon()
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

        if let source = playbackSourceURL ?? currentMediaURL, !isGeneratedFallbackURL(source) {
            PlaybackResumeStore.clear(for: source)
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
        rightSettingsSheet.addSubview(settingsColumnFillView, positioned: .below, relativeTo: settingsScrollClipHost)
        rightSettingsSheet.addSubview(videoSettingsTabsRow, positioned: .above, relativeTo: settingsScrollClipHost)
        rightSettingsSheet.addSubview(imageSettingsTabsRow, positioned: .above, relativeTo: settingsScrollClipHost)
        settingsScrollClipHost.addSubview(settingsTopOverflowFade, positioned: .above, relativeTo: settingsScrollView)
        settingsScrollClipHost.addSubview(settingsBottomOverflowFade, positioned: .above, relativeTo: settingsScrollView)
        rightSettingsSheet.addSubview(imageStudioCommitFooter, positioned: .above, relativeTo: settingsScrollClipHost)
    }

    func showSettingsSheet() {
        guard activeMediaKind != .empty else { return }
        guard playbackLibraryOverlay == .closed else { return }
        rightSettingsSheet.isHidden = false
        syncSettingsPanelGeometry()
        styleRightSettingsPanel()
        refreshImmersiveChromePinnedState()
        ensureSettingsTabRowsAboveContent()
        updateSettingsTabVisibility()
        applySettingsPanelAccentChrome()
        syncVideoSettingsControlsFromStore()
        if activeMediaKind == .video {
            if isSubtitlePlaybackReady() {
                Task { await refreshSubtitleSettings(syncPlayback: true, applyAppearance: false) }
            } else {
                syncSubtitleTrackPopUpsToCache()
            }
        }
        if activeMediaKind == .image {
            updateImageZoomPercentLabel()
            updateImageStudioLayoutInsets()
            updateImageStudioCommitFooter()
        }
        view.layoutSubtreeIfNeeded()
        raisePlaybackChromeToFront()
        installOutsideClickMonitor()
        syncEdgeHotZoneAffordances()
        scheduleSettingsContentBottomInsetUpdate()
        if activeMediaKind == .video, selectedVideoSettingsTabIndex == 2, !isSubtitlePlaybackReady() {
            Task { await refreshSubtitleSettings(syncPlayback: false, applyAppearance: false) }
        }
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
        // Mark hidden first so geometry sync keeps width collapsed (does not re-expand).
        rightSettingsSheet.isHidden = true
        syncSettingsPanelGeometry()
        if activeMediaKind == .image {
            updateImageStudioLayoutInsets()
        }
        if usesImmersiveChrome, playbackLibraryOverlay == .closed {
            noteImmersiveChromePointerActivity()
        }
        view.layoutSubtreeIfNeeded()
        raisePlaybackChromeToFront()
        removeOutsideClickMonitorIfNoSheetsVisible()
        syncEdgeHotZoneAffordances()
    }

    func showFullMediaLibrary() {
        installLibraryChromeIfNeeded()
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = false
        libraryBrowse.isHidden = false
        hidePlaybackMiniPreview()
        librarySidebar.reloadRoots()
        // Grid scan can be slow for large folders — keep UI responsive at launch.
        switch mediaLibraryController.sidebarMode {
        case .folder where mediaLibraryController.currentDirectoryURL != nil,
             .recentHeader,
             .favoritesHeader:
            libraryBrowse.reloadContent()
        case .none, .folder:
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
        // Image + video both use full folder management with media in the mini preview.
        showPlaybackLibraryPanel()
    }

    /// Full folder-management library during playback: sidebar + browse, current media in bottom-right mini preview.
    private func showPlaybackLibraryPanel() {
        if activeMediaKind == .image {
            showImageStudioLibraryPanel()
            return
        }
        guard activeMediaKind == .video else {
            showFullMediaLibrary()
            return
        }

        presentPlaybackLibraryOverlay()
    }

    /// Full folder-management library (like video), with the open photo in the bottom-right mini preview.
    private func showImageStudioLibraryPanel() {
        presentPlaybackLibraryOverlay()
    }

    /// Shared open path for video/image folder management during playback.
    private func presentPlaybackLibraryOverlay() {
        installLibraryChromeIfNeeded()
        // Mark overlay open before dismissing settings so immersive chrome does not
        // animate the playback bar back in (hideSettingsSheet notes pointer activity).
        playbackLibraryOverlay = .sidebarAndBrowse
        immersiveChromeHideWorkItem?.cancel()
        immersiveChromeHideWorkItem = nil
        immersiveChromeVisible = false

        hideSettingsSheet()
        applyLibraryBrowseLayoutMode(dockedForImageStudio: false)
        librarySidebar.isHidden = false
        libraryBrowse.isHidden = false
        librarySidebar.reloadRoots()
        revealCurrentMediaFolderInLibrary()
        if mediaLibraryController.sidebarMode == .none {
            selectFallbackLibrarySidebarDestination()
        }
        librarySidebar.refresh()
        libraryBrowse.reloadContent()

        playerSurfaceView.isHidden = true
        imageSurfaceView.isHidden = true
        imageFolderCarousel.isHidden = true
        imageStudioMetaBar.isHidden = true
        imageControlsContainer.isHidden = true
        controlsContainer.isHidden = true
        applyPlaybackBarVisible(false, animated: false)
        showPlaybackMiniPreview()
        if activeMediaKind == .image {
            updateImageStudioLayoutInsets()
        }
        installOutsideClickMonitor()
        raisePlaybackChromeToFront()
        relayoutLibraryChromeForTitleBar()
        syncPlaybackBarVisibilityForCurrentState()
        setImmersiveChromeVisible(false, animated: false)
        syncEdgeHotZoneAffordances()
        view.layoutSubtreeIfNeeded()
    }

    /// Point folder management at the open file's folder, whether or not it lives under a
    /// library root. Runs once per opened file: after that, wherever the user browsed to is
    /// where reopening the panel leaves them.
    private func revealCurrentMediaFolderInLibrary() {
        libraryBrowse.isHidden = false
        guard pendingLibraryFolderReveal else { return }
        guard let mediaURL = currentMediaURL ?? activePlaybackFileURL else {
            selectFallbackLibrarySidebarDestination()
            return
        }
        pendingLibraryFolderReveal = false
        let folder = mediaURL.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
        mediaLibraryController.revealFolder(folder)
    }

    private func selectFallbackLibrarySidebarDestination() {
        if !mediaLibraryController.roots.isEmpty {
            mediaLibraryController.selectSidebarRow(mediaLibraryController.firstRootRowIndex())
            return
        }
        // Recents header is always row 0.
        mediaLibraryController.selectSidebarRow(0)
    }

    private func syncPlaybackLibraryBrowseExpansion() {
        guard activeMediaKind != .empty else { return }

        switch mediaLibraryController.sidebarMode {
        case .folder, .recentHeader, .favoritesHeader:
            if playbackLibraryOverlay == .sidebarOnly {
                expandPlaybackLibraryBrowse()
            }
        case .none:
            // Keep browse visible during folder management. Hiding on `.none` raced with
            // `reloadRoots()` clearing selection and left an empty black content area.
            break
        }
    }

    private func expandPlaybackLibraryBrowse() {
        guard activeMediaKind != .empty else { return }
        presentPlaybackLibraryOverlay()
    }

    private func collapsePlaybackLibraryBrowseOnly() {
        // Playback library always keeps sidebar + browse together.
        guard playbackLibraryOverlay == .sidebarAndBrowse else { return }
    }

    func collapsePlaybackLibraryOverlay() {
        guard activeMediaKind != .empty else { return }
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = true
        libraryBrowse.isHidden = true
        hidePlaybackMiniPreview()
        restoreMainPlaybackSurface()
        if activeMediaKind == .image {
            syncImageStudioFilmstripVisibility()
            refreshImageStudioMetaBar()
            // Return to image-studio default: right adjust panel visible, padded photo.
            if rightSettingsSheet.isHidden {
                showSettingsSheet()
            }
            updateImageStudioLayoutInsets()
        }
        removeOutsideClickMonitorIfNoSheetsVisible()
        raisePlaybackChromeToFront()
        if usesImmersiveChrome {
            noteImmersiveChromePointerActivity()
        } else {
            refreshImmersiveChromePinnedState()
        }
        syncEdgeHotZoneAffordances()
        resyncPlaybackSurfaceGeometry()
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
            updatePlayPauseButtonIcon()
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

    private func hidePlaybackMiniPreview() {
        playbackMiniPreview.isHidden = true
        playbackMiniPreview.clearContent()
    }

    private func closePlaybackFromMiniPreview() {
        commandStopAndClose()
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

    private func activePlaybackBarInView() -> NSView {
        activeMediaKind == .image ? imageControlsContainer : controlsContainer
    }

    private func isClickOnPlaybackBar(for event: NSEvent) -> Bool {
        let bar = activePlaybackBarInView()
        guard !bar.isHidden else { return false }
        let pointInView = view.convert(event.locationInWindow, from: nil)
        return bar.frame.contains(pointInView)
    }

    private func isSettingsToggleButtonClick(for event: NSEvent) -> Bool {
        let pointInView = view.convert(event.locationInWindow, from: nil)
        guard let hitView = view.hitTest(pointInView) else { return false }
        let button = activeMediaKind == .image ? imageSettingsButton : settingsButton
        return hitView === button || hitView.isDescendant(of: button)
    }

    private func shouldKeepSettingsSheetOpen(for event: NSEvent) -> Bool {
        if suppressSettingsDismissForColorPicker { return true }
        let pointInView = view.convert(event.locationInWindow, from: nil)
        // Filmstrip / meta / tools always keep the column — even when they overlap the close strip.
        if isPointOverImageStudioBottomChrome(pointInView) { return true }
        if isPointInRightSettingsCloseZone(pointInView) { return false }
        if rightSettingsSheet.frame.contains(pointInView) { return true }
        // Image studio: keep the edit column open when clicking photo / chrome,
        // but allow the toolbar Settings gear to toggle it (handled separately).
        if activeMediaKind == .image {
            if !imageSurfaceView.isHidden, imageSurfaceView.frame.contains(pointInView) {
                return true
            }
            if !imageControlsContainer.isHidden, imageControlsContainer.frame.contains(pointInView) {
                // Let the Settings gear through so it can close the column.
                if isSettingsToggleButtonClick(for: event) { return false }
                return true
            }
            return true
        }
        if isClickOnPlaybackBar(for: event) { return false }
        if isTransientMenuWindow(event.window) { return true }
        if isColorPickerAuxiliaryWindow(event.window) { return true }
        return false
    }

    private func isSettingsPanelFullyOpen() -> Bool {
        !rightSettingsSheet.isHidden && (settingsPanelWidthConstraint?.constant ?? 0) > 1
    }

    private func isPointInLeftLibraryOpenZone(_ point: NSPoint) -> Bool {
        guard !isPointOverImageStudioBottomChrome(point) else { return false }
        return EdgeHotZoneGeometry.isInLeftOpenZone(point: point, bounds: view.bounds)
    }

    private func isPointInRightSettingsOpenZone(_ point: NSPoint) -> Bool {
        guard !isPointOverImageStudioBottomChrome(point) else { return false }
        guard !isSettingsPanelFullyOpen() else { return false }
        return EdgeHotZoneGeometry.isInRightOpenZone(point: point, bounds: view.bounds)
    }

    private func isPointInRightSettingsCloseZone(_ point: NSPoint) -> Bool {
        guard isSettingsPanelFullyOpen() else { return false }
        guard !isPointOverImageStudioBottomChrome(point) else { return false }
        return EdgeHotZoneGeometry.isInRightCloseZone(
            point: point,
            bounds: view.bounds,
            sheetLeadingX: rightSettingsSheet.frame.minX
        )
    }

    /// Resolve which panel action a point would trigger (does not perform it).
    private func edgeHotZoneAction(at point: NSPoint) -> (() -> Void)? {
        guard activeMediaKind != .empty, playbackLibraryOverlay == .closed else { return nil }
        // Outer rim is for window resize — never arm a panel toggle there.
        if EdgeHotZoneGeometry.isInWindowResizeRim(point: point, bounds: view.bounds) {
            return nil
        }
        if isPointInLeftLibraryOpenZone(point) {
            return { [weak self] in self?.showPlaybackLibrarySidebarOnly() }
        }
        if isPointInRightSettingsCloseZone(point) {
            return { [weak self] in self?.hideSettingsSheet() }
        }
        if isPointInRightSettingsOpenZone(point) {
            return { [weak self] in self?.showSettingsSheet() }
        }
        return nil
    }

    /// Track edge intent without consuming events — resize / window-drag always get the mouseDown.
    private func noteEdgeHotZoneMouseEvent(_ event: NSEvent) {
        let point = view.convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            pendingEdgeHotZoneAction = edgeHotZoneAction(at: point)
            edgeHotZoneMouseDownPoint = pendingEdgeHotZoneAction == nil ? nil : point
        case .leftMouseDragged:
            guard let start = edgeHotZoneMouseDownPoint else { return }
            if !EdgeHotZoneGeometry.isClickNotDrag(from: start, to: point) {
                pendingEdgeHotZoneAction = nil
                edgeHotZoneMouseDownPoint = nil
            }
        case .leftMouseUp:
            let action = pendingEdgeHotZoneAction
            let start = edgeHotZoneMouseDownPoint
            pendingEdgeHotZoneAction = nil
            edgeHotZoneMouseDownPoint = nil
            guard let action, let start else { return }
            guard EdgeHotZoneGeometry.isClickNotDrag(from: start, to: point) else { return }
            action()
        default:
            break
        }
    }

    private func isPointOverImageStudioBottomChrome(_ point: NSPoint) -> Bool {
        guard activeMediaKind == .image else { return false }
        if !imageFolderCarousel.isHidden {
            let rect = imageFolderCarousel.convert(imageFolderCarousel.bounds, to: view)
            if rect.contains(point) { return true }
        }
        if !imageStudioMetaBar.isHidden {
            let rect = imageStudioMetaBar.convert(imageStudioMetaBar.bounds, to: view)
            if rect.contains(point) { return true }
        }
        if !imageControlsContainer.isHidden {
            let rect = imageControlsContainer.convert(imageControlsContainer.bounds, to: view)
            if rect.contains(point) { return true }
        }
        return false
    }

    private func installEdgeHotZoneClickMonitorIfNeeded() {
        guard edgeHotZoneClickMonitor == nil else { return }
        edgeHotZoneClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        ) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.view.window else { return event }
            // Always pass the event through so window resize / drag can start.
            self.noteEdgeHotZoneMouseEvent(event)
            return event
        }
    }

    private func removeEdgeHotZoneClickMonitor() {
        if let edgeHotZoneClickMonitor {
            NSEvent.removeMonitor(edgeHotZoneClickMonitor)
            self.edgeHotZoneClickMonitor = nil
        }
        pendingEdgeHotZoneAction = nil
        edgeHotZoneMouseDownPoint = nil
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

            // Edge open/close is handled by the non-consuming edge monitor (click vs drag).
            // Do not steal mouseDown here — that breaks window resize.

            if !self.rightSettingsSheet.isHidden {
                if self.isSettingsToggleButtonClick(for: event) {
                    self.hideSettingsSheet()
                    return nil
                }
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
                if self.libraryButton.frame.contains(pointInView)
                    || self.imageLibraryButton.frame.contains(pointInView) {
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
            handlePointerLeftContentView()
            return
        }
        noteImmersiveChromePointerActivity()
        guard !dragSessionActive else {
            return
        }

        let isInLeftHotZone = isPointInLeftLibraryOpenZone(point)
        let isInRightOpenZone = isPointInRightSettingsOpenZone(point)
        let isInRightCloseZone = isPointInRightSettingsCloseZone(point)
        let inAnyEdgeZone = isInLeftHotZone || isInRightOpenZone || isInRightCloseZone

        // Soft hover strip + pointer cursor (click still handled by click-vs-drag monitor).
        syncLeftEdgeHotZoneAffordance(pointerInZone: isInLeftHotZone)
        syncRightEdgeHotZoneAffordance(pointerInZone: isInRightOpenZone || isInRightCloseZone)
        setEdgeHotZonePointerCursor(inAnyEdgeZone)
    }

    private func syncEdgeHotZoneAffordances() {
        syncEdgeHotZoneStripInsets()
        syncLeftEdgeHotZoneAffordance()
        syncRightEdgeHotZoneAffordance()
    }

    /// Lift the soft strip ends above the filmstrip / meta bar so rounding isn’t buried under chrome.
    private func syncEdgeHotZoneStripInsets() {
        let bottom = edgeHotZoneBottomChromeHeight()
        leftEdgeHotZoneAffordance.bottomContentInset = bottom
        rightEdgeHotZoneAffordance.bottomContentInset = bottom
    }

    private func edgeHotZoneBottomChromeHeight() -> CGFloat {
        guard activeMediaKind == .image else { return 0 }
        var height: CGFloat = 0
        if !imageFolderCarousel.isHidden, (imageCarouselHeightConstraint?.constant ?? 0) > 1 {
            height += imageCarouselHeight
        }
        if !imageStudioMetaBar.isHidden {
            height += imageMetaBarHeight
        }
        return height
    }

    private func syncLeftEdgeHotZoneAffordance(pointerInZone: Bool? = nil) {
        let canReveal = activeMediaKind != .empty && playbackLibraryOverlay == .closed
        guard canReveal else {
            leftEdgeHotZoneAffordance.setVisible(false, emphasized: false, animated: true)
            if playbackLibraryOverlay != .closed || activeMediaKind == .empty {
                setEdgeHotZonePointerCursor(false)
            }
            return
        }
        let inZone: Bool
        if let pointerInZone {
            inZone = pointerInZone
        } else if let window = view.window {
            let mouse = window.mouseLocationOutsideOfEventStream
            let point = view.convert(mouse, from: nil)
            inZone = isPointInLeftLibraryOpenZone(point)
        } else {
            inZone = false
        }
        leftEdgeHotZoneAffordance.setVisible(inZone, emphasized: true, animated: true)
    }

    private func syncRightEdgeHotZoneAffordance(pointerInZone: Bool? = nil) {
        let canReveal = activeMediaKind != .empty && playbackLibraryOverlay == .closed
        guard canReveal else {
            rightEdgeHotZoneAffordance.setVisible(false, emphasized: false, animated: true)
            return
        }

        let settingsOpen = isSettingsPanelFullyOpen()
        // Closed: strip on the window trailing edge (open). Open: strip just left of the column (close).
        rightEdgeHotZoneToWindowTrailingConstraint?.isActive = !settingsOpen
        rightEdgeHotZoneToSidebarLeadingConstraint?.isActive = settingsOpen

        let inZone: Bool
        if let pointerInZone {
            inZone = pointerInZone
        } else if let window = view.window {
            let mouse = window.mouseLocationOutsideOfEventStream
            let point = view.convert(mouse, from: nil)
            inZone = isPointInRightSettingsOpenZone(point) || isPointInRightSettingsCloseZone(point)
        } else {
            inZone = false
        }
        rightEdgeHotZoneAffordance.setVisible(inZone, emphasized: true, animated: true)
    }

    private func handlePointerLeftContentView() {
        scheduleImmersiveChromeHide()
        restoreImmersivePlaybackCursor()
        setEdgeHotZonePointerCursor(false)
        syncLeftEdgeHotZoneAffordance(pointerInZone: false)
        syncRightEdgeHotZoneAffordance(pointerInZone: false)
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
        titleBarChromeAlwaysVisible
            || immersiveChromeVisible
            || immersiveChromePinnedVisible
            || playbackLibraryOverlay != .closed
    }

    private var immersiveChromePinnedVisible: Bool {
        dragSessionActive
            || queuePopover?.isShown == true
            || (!rightSettingsSheet.isHidden && playbackLibraryOverlay == .closed)
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
        delegate?.playerViewController(self, didUpdatePlayingTitle: currentPlayingDisplayTitle())
    }

    private func syncPlaybackBarVisibilityForCurrentState() {
        guard activeMediaKind == .video || activeMediaKind == .image else { return }
        if playbackLibraryOverlay != .closed {
            applyPlaybackBarVisible(false, animated: false)
            return
        }
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
        let libraryOpen = playbackLibraryOverlay != .closed
        let shouldShowTitleBar = titleBarChromeAlwaysVisible || visible || immersiveChromePinnedVisible || libraryOpen
        let shouldShowPlaybackBar = usesImmersiveChrome
            && !libraryOpen
            && (visible || immersiveChromePinnedVisible)
        guard shouldShowTitleBar != isTitleBarChromeShowing else {
            if shouldShowTitleBar {
                delegate?.playerViewController(self, setImmersiveChromeVisible: true, animated: animated)
                updateTitleBarChromeStrip(visible: true, animated: animated)
                relayoutLibraryChromeForTitleBar()
            }
            if usesImmersiveChrome, shouldShowPlaybackBar != immersiveChromeVisible {
                immersiveChromeVisible = shouldShowPlaybackBar
                applyPlaybackBarVisible(shouldShowPlaybackBar, animated: animated)
            } else if libraryOpen {
                immersiveChromeVisible = false
                applyPlaybackBarVisible(false, animated: animated)
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
            // Cursor is gone — edge hover strip must go with it.
            hideEdgeHotZoneAffordancesForIdle()
        }
    }

    private func hideEdgeHotZoneAffordancesForIdle() {
        setEdgeHotZonePointerCursor(false)
        leftEdgeHotZoneAffordance.setVisible(false, emphasized: false, animated: true)
        rightEdgeHotZoneAffordance.setVisible(false, emphasized: false, animated: true)
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
        guard usesImmersiveChrome else {
            resyncPlaybackSurfaceGeometry()
            return
        }
        updatePlaybackBarWidth()
        updateMiniPreviewLayout()
        resyncPlaybackSurfaceGeometry()
        noteImmersiveChromePointerActivity()
    }

    /// Re-center chrome and re-bind mpv after fullscreen / display geometry changes.
    private func resyncPlaybackSurfaceGeometry() {
        guard playerInterfaceInstalled, activeMediaKind == .video else { return }
        view.layoutSubtreeIfNeeded()
        updatePlaybackBarWidth()
        // Left library overlay should not leave video chrome offset when closed.
        if playbackLibraryOverlay == .closed {
            librarySidebar.isHidden = true
            libraryBrowse.isHidden = true
        }
        controlsContainer.needsLayout = true
        playerSurfaceView.needsLayout = true
        view.layoutSubtreeIfNeeded()
        if mpvBackendActive {
            playerSurfaceView.forceMpvLayoutResync()
        }
        nativeSubtitleOverlay.install(in: playerSurfaceView)
    }

    private func installScreenParameterObserverIfNeeded() {
        guard screenParameterObserver == nil else { return }
        screenParameterObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.revealImmersiveChromeAfterDisplayChange()
        }
    }

    private func removeImmersiveCursorWindowObservers() {
        let center = NotificationCenter.default
        for token in immersiveCursorWindowObservers {
            center.removeObserver(token)
        }
        immersiveCursorWindowObservers.removeAll()
        if let screenParameterObserver {
            center.removeObserver(screenParameterObserver)
            self.screenParameterObserver = nil
        }
    }

    private func updateTitleBarChromeLayout() {
        titleBarChromeHeightConstraint?.constant = ImmersiveWindowChrome.titleBarChromeStripHeight(for: view.window)
        if activeMediaKind == .image {
            syncImageStudioSettingsPanelGeometry()
        }
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
        // Folder management never shows the floating transport / image tools bar.
        let allowVisible = visible && playbackLibraryOverlay == .closed
        let bar = activeMediaKind == .image ? imageControlsContainer : controlsContainer
        guard activeMediaKind == .video || activeMediaKind == .image else { return }
        // Drop any in-flight animator() alpha so a prior immersive show cannot win.
        bar.layer?.removeAllAnimations()

        if !animated || !allowVisible {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            bar.alphaValue = allowVisible ? 1 : 0
            bar.isHidden = !allowVisible
            NSAnimationContext.endGrouping()
            return
        }

        bar.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ImmersiveWindowChrome.animationDuration
            bar.animator().alphaValue = 1
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
        volumeCluster.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        // Far left: library. Left of transport: subs. Right of transport: queue + volume.
        // Far right: settings.
        playbackTopRowView.addSubview(libraryButton)
        playbackTopRowView.addSubview(playbackLeadingAccessoryCluster)
        playbackTopRowView.addSubview(transportClusterStack)
        playbackTopRowView.addSubview(playbackAccessoryCluster)
        playbackTopRowView.addSubview(volumeCluster)
        playbackTopRowView.addSubview(settingsButton)

        playbackAccessoryToVolumeConstraint = playbackAccessoryCluster.trailingAnchor.constraint(
            equalTo: volumeCluster.leadingAnchor,
            constant: -playbackControlClusterSpacing
        )
        volumeToSettingsConstraint = volumeCluster.trailingAnchor.constraint(
            equalTo: settingsButton.leadingAnchor,
            constant: -playbackControlClusterSpacing
        )
        playbackAccessoryToSettingsConstraint = playbackAccessoryCluster.trailingAnchor.constraint(
            equalTo: settingsButton.leadingAnchor,
            constant: -playbackControlClusterSpacing
        )

        NSLayoutConstraint.activate([
            playbackTopRowView.heightAnchor.constraint(equalToConstant: 28),

            libraryButton.leadingAnchor.constraint(equalTo: playbackTopRowView.leadingAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            playbackLeadingAccessoryCluster.trailingAnchor.constraint(
                equalTo: transportClusterStack.leadingAnchor,
                constant: -playbackControlClusterSpacing
            ),
            playbackLeadingAccessoryCluster.leadingAnchor.constraint(
                greaterThanOrEqualTo: libraryButton.trailingAnchor,
                constant: 8
            ),
            playbackLeadingAccessoryCluster.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            transportClusterStack.centerXAnchor.constraint(equalTo: playbackTopRowView.centerXAnchor),
            transportClusterStack.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            playbackAccessoryCluster.leadingAnchor.constraint(
                greaterThanOrEqualTo: transportClusterStack.trailingAnchor,
                constant: 8
            ),
            playbackAccessoryCluster.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            volumeCluster.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            settingsButton.trailingAnchor.constraint(equalTo: playbackTopRowView.trailingAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: playbackTopRowView.centerYAnchor),

            transportClusterStack.trailingAnchor.constraint(
                lessThanOrEqualTo: playbackAccessoryCluster.leadingAnchor,
                constant: -8
            ),

            playbackAccessoryToVolumeConstraint!,
            volumeToSettingsConstraint!
        ])
        volumeClusterCollapsedWidthConstraint = volumeCluster.widthAnchor.constraint(equalToConstant: 0)
        volumeClusterCollapsedWidthConstraint?.priority = .required
        playbackAccessoryToSettingsConstraint?.isActive = false
        updatePlaybackVolumeChromeVisibility()
        // Keep outer accessories above transport chrome so edge icons stay visually paired.
        playbackTopRowView.addSubview(libraryButton, positioned: .above, relativeTo: nil)
        playbackTopRowView.addSubview(settingsButton, positioned: .above, relativeTo: nil)
    }

    private enum SpeedBadgePin {
        case leading
        case trailing
    }

    /// Tiny speed badges on the step buttons — slow hugs bottom-left, fast hugs bottom-right.
    private func attachTransportSpeedIndicatorOverlays() {
        transportSpeedLeftCluster.clipsToBounds = false
        transportSpeedRightCluster.clipsToBounds = false
        attachTransportSpeedBadge(playbackSpeedSlowLabel, to: speedStepDownButton, pin: .leading)
        attachTransportSpeedBadge(playbackSpeedFastLabel, to: speedStepUpButton, pin: .trailing)
    }

    private func attachTransportSpeedBadge(_ label: NSTextField, to button: NSButton, pin: SpeedBadgePin) {
        guard button.superview != nil else { return }
        label.removeFromSuperview()
        button.clipsToBounds = false
        button.addSubview(label, positioned: .above, relativeTo: nil)
        let outward = Self.transportSpeedBadgeOutwardOffset
        let horizontal: NSLayoutConstraint
        switch pin {
        case .leading:
            horizontal = label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: -outward)
        case .trailing:
            horizontal = label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: outward)
        }
        NSLayoutConstraint.activate([
            horizontal,
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
        ])
    }

    private static let transportSpeedBadgeHeight: CGFloat = 10
    private static let transportSpeedBadgeOutwardOffset: CGFloat = 24

    private func configureTransportSpeedLabel(_ label: NSTextField, alignment: NSTextAlignment) {
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.font = .monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: Self.transportSpeedLabelReservedWidth).isActive = true
        label.heightAnchor.constraint(equalToConstant: Self.transportSpeedBadgeHeight).isActive = true
    }

    private func setTransportSpeedLabelText(_ text: String, on label: NSTextField, alignment: NSTextAlignment) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.minimumLineHeight = Self.transportSpeedBadgeHeight
        style.maximumLineHeight = Self.transportSpeedBadgeHeight
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
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
        (button.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
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
        // Image tools stay pinned above the meta bar (not the window bottom).
        imageBarBottomConstraint?.constant = -10
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
        playbackLeadingAccessoryCluster.arrangedSubviews.forEach { view in
            playbackLeadingAccessoryCluster.removeArrangedSubview(view)
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
        updateQueueTransportButtons()

        // Subs sit immediately left of the transport cluster — library is pinned far left.
        if libraryButton.superview !== playbackTopRowView {
            libraryButton.removeFromSuperview()
            playbackTopRowView.addSubview(libraryButton)
        }
        if settingsButton.superview !== playbackTopRowView {
            settingsButton.removeFromSuperview()
            playbackTopRowView.addSubview(settingsButton)
        }
        playbackLeadingAccessoryCluster.addArrangedSubview(playbackSubtitleToggle)
        MusicStylePlaybackBar.configureSubtitleToggleButton(playbackSubtitleToggle)
        playbackSubtitleToggle.target = self
        playbackSubtitleToggle.action = #selector(playbackSubtitleTogglePressed)
        updateQueueButtonState()

        if playbackTopRowView.superview != topControlsStack {
            topControlsStack.addArrangedSubview(playbackTopRowView)
            playbackTopRowView.widthAnchor.constraint(equalTo: topControlsStack.widthAnchor).isActive = true
        }
        playbackTopRowView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        attachTransportSpeedIndicatorOverlays()
        updatePlaybackSpeedTransportLabels()

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
        playbackMiniPreview.setPlaying(playing)
        syncIdleSleepGuard(isPlaying: playing)
    }

    private func syncIdleSleepGuard(isPlaying: Bool) {
        let shouldHold = PlaybackIdleSleepPolicy.shouldPreventIdleSleep(
            isPlaying: isPlaying,
            mediaKind: activeMediaKind
        )
        idleSleepGuard.update(shouldHold: shouldHold)
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
            persistPlaybackResumePosition()
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
        if !mpvBackendActive, primarySubtitlesEnabled, nativeSubtitleOverlay.usesSidecarPlayback {
            nativeSubtitleOverlay.updateSidecar(
                at: currentSec,
                enabled: true,
                store: SettingsStore.shared
            )
        }
        persistPlaybackResumePosition()
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

    private func tracePlaybackTick(seconds: Double) {
        let rounded = String(format: "%.2f", seconds)
        if mpvBackendActive {
            let playing = activeSession?.isPlaying == true
            PlaybackTrace.emit("[DEBUG-playback] t=\(rounded)s backend=mpv playing=\(playing)")
            return
        }
        let rate = player.rate
        // Auto-heal stuck mute while the clock is running (switch-mute left behind, AVPlayer hang).
        if rate > 0.01, audioOutputEnabled, !isUserVolumeMuted {
            if isMutedForSwitch || player.isMuted || player.volume < 0.01 {
                clearSwitchMuteIfNeeded()
                applyEffectivePlaybackVolume()
            }
        }
        if rate > 0.01 {
            checkSparseIncompleteRemuxFreeze()
        }
        guard let item = player.currentItem else {
            PlaybackTrace.emit("[DEBUG-playback] t=\(rounded)s rate=\(String(format: "%.2f", rate)) buffer=none")
            return
        }
        let health = PlaybackBufferHealth.classify(
            keepUp: item.isPlaybackLikelyToKeepUp,
            empty: item.isPlaybackBufferEmpty,
            full: item.isPlaybackBufferFull
        )
        PlaybackTrace.emit(
            "[DEBUG-playback] t=\(rounded)s rate=\(String(format: "%.2f", rate)) buffer=\(health.logLabel) keepUp=\(item.isPlaybackLikelyToKeepUp) empty=\(item.isPlaybackBufferEmpty) full=\(item.isPlaybackBufferFull)"
        )
    }

    private func checkSparseIncompleteRemuxFreeze() {
        guard let playable = activePlaybackFileURL, isGeneratedFallbackURL(playable) else { return }
        guard sparseRemuxFreezeCheckedPath != playable.path else { return }
        sparseRemuxFreezeCheckedPath = playable.path
        guard let source = playbackSourceURL ?? currentMediaURL,
              IncompleteMediaProbe.looksLikeIncompleteDownload(at: source) else { return }

        let playableURL = playable
        let sourceURL = source
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard FFmpegVideoFallback.remuxLooksTooSparseForPlayback(at: playableURL) else { return }
            await MainActor.run {
                guard self.activePlaybackFileURL?.path == playableURL.path else { return }
                self.player.pause()
                self.showCompatibilityFailure(PlaybackErrorFormatter.stillDownloadingNotice(for: sourceURL))
                PlaybackTrace.emit(
                    "[DEBUG-fallback] paused sparse remux freeze (clock advanced, picture stuck) path=\(playableURL.lastPathComponent)"
                )
            }
        }
    }

    private func logBufferStateChanges(item: AVPlayerItem) {
        let likely = item.isPlaybackLikelyToKeepUp
        let empty = item.isPlaybackBufferEmpty
        let full = item.isPlaybackBufferFull

        if lastLikelyToKeepUp != likely || lastBufferEmpty != empty || lastBufferFull != full {
            lastLikelyToKeepUp = likely
            lastBufferEmpty = empty
            lastBufferFull = full
            let health = PlaybackBufferHealth.classify(keepUp: likely, empty: empty, full: full)
            PlaybackTrace.emit("[DEBUG-qos] buffer_state \(health.logLabel) keepUp=\(likely) empty=\(empty) full=\(full)")
        }
    }

    private func logPlaybackHealthSnapshot(reason: String, item: AVPlayerItem) {
        let keepUp = item.isPlaybackLikelyToKeepUp
        let empty = item.isPlaybackBufferEmpty
        let full = item.isPlaybackBufferFull
        let health = PlaybackBufferHealth.classify(keepUp: keepUp, empty: empty, full: full)

        if let event = item.accessLog()?.events.last {
            PlaybackTrace.emit(String(
                format: "[DEBUG-qos] %@ buffer=%@ keepUp=%@ empty=%@ full=%@ bitrate=%.0f indicated=%.0f droppedFrames=%ld stalls=%ld transfer=%.3fs",
                reason,
                health.logLabel,
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
            PlaybackTrace.emit("[DEBUG-qos] \(reason) buffer=\(health.logLabel) keepUp=\(keepUp) empty=\(empty) full=\(full) (no access log events yet)")
        }
    }

    private func logErrorLogSnapshot(reason: String, item: AVPlayerItem) {
        guard let event = item.errorLog()?.events.last else {
            PlaybackTrace.emit("[DEBUG-qos] \(reason) no error log events")
            return
        }
        PlaybackTrace.emit(
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
        PlaybackTrace.emit(String(format: "[DEBUG-ui] seek_bar target=%.2fs rate=%.2f", targetSec, player.rate))
        if isPreviewPlaybackActive,
           targetSec > activePlayableDurationSec - 5,
           let sourceDuration = activePreviewSourceDurationSec,
           targetSec < sourceDuration - 5 {
            performProgressiveSeek(to: targetSec)
            return
        }
        let target = CMTime(seconds: targetSec, preferredTimescale: 600)
        // Precise seek for bar clicks — loose tolerance on HEVC remuxes often lands on a
        // non-decodable point and leaves a frozen frame at roughly the same look.
        performCooperativeSeek(to: target, precise: true) { [weak self] _ in
            guard let self else { return }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            PlaybackTrace.emit(String(
                format: "[DEBUG-ui] seek_bar done=%.0fms rate=%.2f t=%.2f",
                elapsedMs,
                self.player.rate,
                CMTimeGetSeconds(self.player.currentTime())
            ))
        }
        DispatchQueue.main.async { [weak self] in
            self?.focusPlaybackSurfaceForTransportShortcuts()
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
        DispatchQueue.main.async { [weak self] in
            self?.focusPlaybackSurfaceForTransportShortcuts()
        }
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
        updatePlayPauseButtonIcon()
        print("[DEBUG-playback] paused Laugh for video switch (player muted, volume unchanged)")
    }

    /// Stop Laugh audio/video output without `replaceCurrentItem(nil)` — that call can reset Core Audio for all apps.
    private func suspendPlayerOutputForStillOrEmpty() {
        stopMpvBackend()
        volumeRampToken += 1
        isMutedForSwitch = true
        renderMonitor.reset()
        freezeWatchdog.reset()
        detachCurrentPlayerItemObserver()
        lastPlaybackStartedItemID = nil
        player.pause()
        player.isMuted = true
        player.volume = 0
        disconnectPlayerFromVideoSurfaces()
        updatePlayPauseButtonIcon()
        print("[DEBUG-playback] suspended AVPlayer output (still image / empty — no item teardown)")
    }

    private func startFreezeWatchdog(for item: AVPlayerItem) {
        freezeWatchdog.isSeekingProvider = { [weak self] in
            self?.isSeekingFromUI == true
        }
        freezeWatchdog.isDisplaySuppressedProvider = { [weak self] in
            self?.isPlaybackDisplaySuppressed() ?? false
        }
        freezeWatchdog.onFreezeDetected = { [weak self] in
            self?.recoverFromPlaybackFreeze()
        }
        freezeWatchdog.begin(player: player, item: item)
    }

    /// VideoOutput stops delivering frames when Laugh is inactive or covered — not a real freeze.
    private func isPlaybackDisplaySuppressed() -> Bool {
        if NSApp.isActive == false { return true }
        guard let window = view.window else { return true }
        if window.occlusionState.contains(.visible) == false { return true }
        return false
    }

    /// Soft recovery when the clock advances but frames/audio have died (long-session AVPlayer hang).
    /// Seeks without pausing — cooperative pause was audible as playback "stopping" on false positives.
    private func recoverFromPlaybackFreeze() {
        guard !mpvBackendActive else { return }
        guard let item = player.currentItem, item === observedItem else { return }
        guard player.rate > 0.01 else { return }
        guard !isPlaybackDisplaySuppressed() else { return }

        let current = item.currentTime()
        let currentSec = CMTimeGetSeconds(current)
        guard currentSec.isFinite else { return }

        freezeWatchdog.noteRecoveryStarted()
        let nudge = CMTimeAdd(current, CMTime(seconds: 0.05, preferredTimescale: 600))
        let resumeRate = player.rate
        PlaybackTrace.emit(String(
            format: "[DEBUG-qos] freeze_watchdog recovering with seek nudge at %.2fs",
            currentSec
        ))
        player.seek(to: nudge, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.isMutedForSwitch {
                    self.restoreAudioAfterSwitchSmoothly()
                }
                self.ensureLaughVolumeIfPlaying()
                self.kickVideoDisplayAfterSeek()
                if finished, self.player.rate < 0.01, !self.isMutedForSwitch {
                    self.player.rate = resumeRate > 0.01 ? resumeRate : self.preferredPlaybackRate
                }
                // Force volume even if safety-net guards thought we were fine — freeze
                // recoveries often leave isMuted=true with volume still at the UI value.
                if self.audioOutputEnabled, !self.isUserVolumeMuted {
                    self.applyEffectivePlaybackVolume()
                }
                self.freezeWatchdog.noteRecoveryFinished()
            }
        }
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
        guard player.currentItem != nil else { return }
        // Also fix mute while paused — user often hits play after a freeze and expects sound.
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
        if isSettingsPanelFullyOpen() {
            hideSettingsSheet()
        } else {
            showSettingsSheet()
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
            showPlaybackLibraryPanel()
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
        } else if selectedVideoSettingsTabIndex == 2 {
            let syncPlayback = isSubtitlePlaybackReady()
            Task { await refreshSubtitleSettings(syncPlayback: syncPlayback, applyAppearance: false) }
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
        imageSurfaceView.setZoomScale(min(imageSurfaceView.zoomScale * 1.15, 24.0))
        updateImageZoomPercentLabel()
    }

    @objc func imageZoomOut() {
        imageSurfaceView.setZoomScale(max(imageSurfaceView.zoomScale / 1.15, 0.2))
        updateImageZoomPercentLabel()
    }

    @objc func imageFit() {
        imageSurfaceView.resetZoom()
        updateImageZoomPercentLabel()
    }

    @objc func imageCropPressed() {
        guard activeMediaKind == .image else { return }
        if isImageCropMode {
            cancelImageCropMode()
        } else {
            beginImageCropMode()
        }
    }

    @objc private func imageCropAspectChanged() {
        guard isImageCropMode else { return }
        imageSurfaceView.setCropAspect(imageCropBar.selectedAspect)
    }

    @objc private func imageCropCancelPressed() {
        cancelImageCropMode()
    }

    @objc private func imageCropApplyPressed() {
        guard isImageCropMode else { return }
        imageSurfaceView.applyCropDraft()
        isImageCropMode = false
        updateImageCropChrome()
        updateImageStudioCommitFooter()
        updateImageZoomPercentLabel()
    }

    private func beginImageCropMode() {
        guard imageSurfaceView.enterCropMode(aspect: imageCropBar.selectedAspect) else { return }
        isImageCropMode = true
        updateImageCropChrome()
        updateImageZoomPercentLabel()
    }

    private func cancelImageCropMode() {
        guard isImageCropMode || imageSurfaceView.isCropMode else { return }
        // Cancel abandons the session: clear crop/straighten and undo mid-session
        // rotate/flip (restored to orientation at crop entry).
        imageSurfaceView.cancelCropMode(restoreOriginal: true)
        isImageCropMode = false
        updateImageCropChrome()
        updateImageStudioCommitFooter()
        updateImageZoomPercentLabel()
    }

    private func updateImageCropChrome() {
        let cropping = isImageCropMode
        imageCropBar.isHidden = !cropping
        imageLeadingAccessoryCluster.isHidden = cropping
        imageTransportCluster.isHidden = cropping
        imageAccessoryCluster.isHidden = cropping
        imageRotateLeftButton.isEnabled = !cropping
        imageRotateRightButton.isEnabled = !cropping
        imageBarHeightConstraint?.constant = cropping
            ? ImageCropBarView.preferredChromeHeight
            : 52
        if cropping {
            // Crop chrome uses a compact aspect popup + transform actions.
            imageBarWidthConstraint?.constant = max(
                imageBarWidthConstraint?.constant ?? 420,
                420
            )
        } else {
            let contentWidth = view.bounds.width > 1 ? view.bounds.width : 1100
            imageBarWidthConstraint?.constant = MusicStylePlaybackBar.preferredBarWidth(
                forContentWidthPoints: contentWidth
            )
        }
        // Recrop the photo against the updated tools bar.
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        updateImageStudioLayoutInsets()
    }

    @objc func imageActualSize() {
        let scale = view.window?.backingScaleFactor
            ?? view.window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        imageSurfaceView.setActualSizeZoom(backingScaleFactor: scale)
        updateImageZoomPercentLabel()
    }

    @objc func imageRotateLeft() {
        imageSurfaceView.rotateLeft()
        updateImageStudioCommitFooter()
        updateImageZoomPercentLabel()
    }

    @objc func imageRotateRight() {
        imageSurfaceView.rotateRight()
        updateImageStudioCommitFooter()
        updateImageZoomPercentLabel()
    }

    @objc private func imageCropFlipHorizontal() {
        imageSurfaceView.flipHorizontalAxis()
        updateImageStudioCommitFooter()
        updateImageZoomPercentLabel()
    }

    @objc private func imageCropFlipVertical() {
        imageSurfaceView.flipVerticalAxis()
        updateImageStudioCommitFooter()
        updateImageZoomPercentLabel()
    }

    private func toggleImageFitActualSize() {
        guard activeMediaKind == .image else { return }
        let scale = view.window?.backingScaleFactor
            ?? view.window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        if imageSurfaceView.isApproximatelyFitZoom {
            imageSurfaceView.setActualSizeZoom(backingScaleFactor: scale)
        } else {
            imageSurfaceView.resetZoom()
        }
        updateImageZoomPercentLabel()
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
    private static let standardSeekSeconds = PlaybackTransportShortcuts.standardSeekSeconds
    private static let fineSeekSeconds = PlaybackTransportShortcuts.fineSeekSeconds
    private static let volumeStep = PlaybackTransportShortcuts.volumeStep

    func installVideoDoubleClickFullscreenMonitor() {
        guard videoDoubleClickMonitor == nil else { return }
        videoDoubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            guard event.clickCount == 2 else { return event }

            if self.shouldZoomWindowForTitleBarDoubleClick(at: event.locationInWindow) {
                self.zoomMainWindowToFillVisibleDesktop()
                return event
            }

            guard self.activeMediaKind == .video,
                  self.shouldToggleFullscreenForVideoDoubleClick(at: event.locationInWindow) else {
                return event
            }
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

    /// Double-click the immersive title-bar band to zoom the window (menu bar + Dock stay).
    /// Works in image studio and folder/library view — the chrome strip is hit-through, so
    /// library content underneath must not block this gesture.
    private func shouldZoomWindowForTitleBarDoubleClick(at windowLocation: NSPoint) -> Bool {
        let libraryOpen = playbackLibraryOverlay != .closed
        let imageStudio = activeMediaKind == .image
        let libraryHome = activeMediaKind == .empty
        guard libraryOpen || imageStudio || libraryHome else { return false }

        let point = view.convert(windowLocation, from: nil)
        guard view.bounds.contains(point) else { return false }
        let titleHeight = max(
            ImmersiveWindowChrome.titleBarChromeStripHeight(for: view.window),
            titleBarChromeStrip.isHidden ? 28 : titleBarChromeStrip.bounds.height
        )
        // NSView: y=0 at bottom — title bar occupies the top strip.
        guard point.y >= (view.bounds.maxY - titleHeight - 2) else { return false }

        // Ignore interactive chrome that can sit in/near the strip (settings, banners, etc.),
        // but allow library sidebar/browse which intentionally extend under the title bar.
        if isPointOverTitleBarBlockingChrome(windowLocation) { return false }
        return true
    }

    private func isPointOverTitleBarBlockingChrome(_ windowLocation: NSPoint) -> Bool {
        let blockers: [NSView] = [
            controlsContainer,
            imageControlsContainer,
            imageFolderCarousel,
            imageStudioMetaBar,
            rightSettingsSheet,
            compatibilityBanner,
            queueDropZone,
            openButton,
            hintLabel,
            playbackMiniPreview
        ]
        for chrome in blockers where !chrome.isHidden {
            let local = chrome.convert(windowLocation, from: nil)
            if chrome.bounds.contains(local) {
                return true
            }
        }
        return false
    }

    /// Fill the screen’s visible frame (excludes menu bar / Dock). Toggles back via `zoom`.
    private func zoomMainWindowToFillVisibleDesktop() {
        guard let window = view.window else { return }
        revealImmersiveChromeAfterDisplayChange()
        // Standard macOS zoom — fills visible desktop, does not enter Spaces fullscreen.
        if window.styleMask.contains(.resizable) {
            window.zoom(nil)
        }
    }

    private func isPointOverVideoChrome(_ windowLocation: NSPoint) -> Bool {
        let chrome: [NSView] = [
            controlsContainer,
            imageControlsContainer,
            imageFolderCarousel,
            imageStudioMetaBar,
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

    func installScrollShortcutMonitor() {
        guard scrollShortcutMonitor == nil else { return }
        scrollShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.view.window || self.view.window?.isKeyWindow == true else {
                return event
            }
            guard self.handlePlaybackScrollEvent(event) else { return event }
            return nil
        }
    }

    /// Vertical wheel → volume; horizontal / ⇧+vertical → seek.
    @discardableResult
    func handlePlaybackScrollEvent(_ event: NSEvent) -> Bool {
        guard activeMediaKind == .video else { return false }
        guard !keyboardFocusBlocksTransportShortcuts else { return false }
        guard shouldHandlePlaybackScroll(at: event.locationInWindow) else { return false }

        let flags = PlaybackTransportShortcuts.chordModifiers(from: event)
        guard !flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else {
            return false
        }

        var deltaX = event.scrollingDeltaX
        var deltaY = event.scrollingDeltaY
        if abs(deltaX) < 0.01, abs(deltaY) < 0.01 {
            deltaX = event.deltaX
            deltaY = event.deltaY
        }
        // Ignore pure momentum crumbs with no delta.
        guard abs(deltaX) > 0.01 || abs(deltaY) > 0.01 else { return false }

        let action = PlaybackTransportShortcuts.consumeScroll(
            deltaX: deltaX,
            deltaY: deltaY,
            shiftPressed: flags.contains(.shift),
            hasPreciseDeltas: event.hasPreciseScrollingDeltas,
            volumeAccumulator: &scrollVolumeAccumulator,
            seekAccumulator: &scrollSeekAccumulator
        )
        guard let action else { return false }

        switch action {
        case .volume(let delta):
            commandAdjustVolume(by: delta)
        case .seek(let seconds):
            commandSeek(bySeconds: seconds)
        }
        return true
    }

    private func shouldHandlePlaybackScroll(at windowLocation: NSPoint) -> Bool {
        guard !playerSurfaceView.isHidden else { return false }
        let pointInView = view.convert(windowLocation, from: nil)
        guard view.bounds.contains(pointInView) else { return false }

        // Let settings / library keep their own scrolling.
        if !rightSettingsSheet.isHidden {
            let local = rightSettingsSheet.convert(windowLocation, from: nil)
            if rightSettingsSheet.bounds.contains(local) { return false }
        }
        if playbackLibraryOverlay != .closed {
            if librarySidebar.frame.contains(pointInView) || libraryBrowse.frame.contains(pointInView) {
                return false
            }
        }
        return true
    }

    /// Keep the playback bar visible while seek / volume is being adjusted.
    private func noteTransportChromeActivity() {
        noteImmersiveChromePointerActivity()
    }

    /// Prefer keyboard focus on the video surface so chrome controls do not keep key focus.
    func focusPlaybackSurfaceForTransportShortcuts() {
        guard activeMediaKind == .video else { return }
        guard let window = view.window else { return }
        if keyboardFocusBlocksTransportShortcuts { return }
        window.makeFirstResponder(playerSurfaceView)
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
            showPlaybackLibraryPanel()
        }
    }

    func commandToggleSettingsInspector() {
        guard activeMediaKind != .empty, playbackLibraryOverlay == .closed else { return }
        if isSettingsPanelFullyOpen() {
            hideSettingsSheet()
        } else {
            showSettingsSheet()
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
        hidePlaybackMiniPreview()
        guard activeMediaKind != .empty else { return }
        showEmptySurface()
    }

    /// Stop all audio backends before the process exits. Window close does not reliably run `deinit`.
    func prepareForTermination() {
        persistPlaybackResumePosition(force: true)
        stopMpvBackend()
        MpvPlaybackController.terminateRunningProcesses()
        volumeRampToken += 1
        activeSession?.pause()
        player.pause()
        player.isMuted = true
        player.volume = 0
        FFmpegVideoFallback.terminateRunningProcesses()
    }

    /// Remember playhead for the current source video (UserDefaults). Skips remux cache paths.
    private func persistPlaybackResumePosition(force: Bool = false) {
        guard activeMediaKind == .video else { return }
        let source = playbackSourceURL ?? currentMediaURL
        guard let source, !isGeneratedFallbackURL(source) else { return }

        let now = CFAbsoluteTimeGetCurrent()
        if !force, (now - lastResumePersistAt) < 2.5 {
            return
        }

        let currentSec: Double
        let durationSec: Double?
        if mpvBackendActive, let session = activeSession {
            currentSec = session.currentTimeSec
            let d = session.durationSec
            durationSec = (d.isFinite && d > 0) ? d : nil
        } else {
            currentSec = CMTimeGetSeconds(player.currentTime())
            let itemDuration = player.currentItem.map { CMTimeGetSeconds($0.duration) }
            if let itemDuration, itemDuration.isFinite, itemDuration > 0 {
                durationSec = itemDuration
            } else if let preview = activePreviewSourceDurationSec, preview > 0 {
                durationSec = preview
            } else {
                durationSec = nil
            }
        }
        guard currentSec.isFinite, currentSec >= 0 else { return }
        lastResumePersistAt = now
        PlaybackResumeStore.save(seconds: currentSec, duration: durationSec, for: source)
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
        noteTransportChromeActivity()
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
        noteTransportChromeActivity()
        performCooperativeSeek(to: .zero)
    }

    func commandSeekToEnd() {
        guard activeMediaKind == .video else { return }
        noteTransportChromeActivity()
        let end = seekSlider.maxValue
        guard end > 0 else { return }
        performCooperativeSeek(to: CMTime(seconds: end, preferredTimescale: 600))
    }

    func commandAdjustVolume(by delta: Float) {
        guard activeMediaKind == .video, audioOutputEnabled else { return }
        noteTransportChromeActivity()
        clearSwitchMuteIfNeeded()
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
        // Ignore .numericPad / .function — arrow keys always carry them on macOS.
        let flags = PlaybackTransportShortcuts.chordModifiers(from: event)

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
        PlaybackTransportShortcuts.blocksTransportShortcuts(firstResponder: view.window?.firstResponder)
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
    var onDoubleClick: (() -> Void)?
    /// Fired whenever zoom changes (buttons, scroll, pinch).
    var onZoomScaleChanged: (() -> Void)?
    /// Fired when applied crop changes (apply / clear).
    var onCropChanged: (() -> Void)?
    /// Selection brush stroke in source pixel space (when brush enabled).
    var onSelectionBrushStroke: ((CGPoint) -> Void)?
    var onSelectionBrushStrokeEnded: (() -> Void)?
    /// Click Select: point in source pixels, negative flag, additive flag.
    var onSelectionClick: ((CGPoint, Bool, Bool) -> Void)?
    /// Click Select box in source pixels.
    var onSelectionBox: ((CGRect, Bool) -> Void)?

    private let imageView = NSImageView()
    private let cropOverlay = ImageCropOverlayView()
    private var baseImage: NSImage?
    private var baseCIImage: CIImage?
    private var previewCIImage: CIImage?
    private var cachedSourceToken: ObjectIdentifier?
    private(set) var naturalPixelSize: CGSize = .zero
    private(set) var zoomScale: CGFloat = 1.0
    private(set) var rotationQuarterTurns: Int = 0
    private(set) var flipHorizontal = false
    private(set) var flipVertical = false
    /// Normalized crop in post-rotation + straighten space (bottom-leading). `nil` = full frame.
    private(set) var appliedCropNormalized: CGRect?
    /// Fine straighten angle after quarter-turns (radians). Applied with crop.
    private(set) var appliedStraightenRadians: CGFloat = 0
    private var draftStraightenRadians: CGFloat = 0
    private(set) var isCropMode = false
    private var cropAspect: ImageCropAspect = .free
    /// Orientation at crop-mode entry — restored on Cancel so mid-session rotate/flip are abandoned.
    private var cropSessionRotationQuarterTurns = 0
    private var cropSessionFlipHorizontal = false
    private var cropSessionFlipVertical = false
    private var adjustParameters = ImageAdjustParameters.identity
    private var selectionMask: SelectionMask?
    private var selectionDisplayMode: SelectionDisplayMode = .none
    private var selectionRefine = SelectionRefineParameters.identity
    private var marchingAntsPhase: CGFloat = 0
    private var marchingAntsTimer: Timer?
    private let antsWhiteLayer = CAShapeLayer()
    private let antsBlackLayer = CAShapeLayer()
    /// Vision-normalized contour (0…1) in the current display matte space.
    private var antsNormalizedPath: CGPath?
    private var selectionBrushEnabled = false
    private var selectionClickEnabled = false
    private var selectionBrushRadius: CGFloat = 24
    private var isBrushing = false
    private var lastBrushPixelPoint: CGPoint?
    private var brushCursorViewPoint: CGPoint?
    private var brushTrackingArea: NSTrackingArea?
    private let brushRingLayer = CAShapeLayer()
    private var clickDragStartView: CGPoint?
    private var clickDragStartPixel: CGPoint?
    private var clickDragCurrentView: CGPoint?
    private let clickBoxLayer = CAShapeLayer()
    /// Offset from centered fit frame while zoomed in (points).
    private var panOffset: CGPoint = .zero
    private var isPanning = false
    private var panGestureStartMouse: CGPoint = .zero
    private var panGestureStartOffset: CGPoint = .zero
    private static let minZoom: CGFloat = 0.2
    private static let maxZoom: CGFloat = 24.0
    private static let boxDragThresholdPoints: CGFloat = 8
    /// Metal-backed when available — better quality/perf for interactive preview.
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false
            ])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()
    private var fullRenderGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 10.14, *) {
            imageView.layer?.contentsGravity = .resizeAspect
        }
        addSubview(imageView)

        brushRingLayer.fillColor = NSColor.clear.cgColor
        brushRingLayer.strokeColor = LaughTheme.interactiveAccent.withAlphaComponent(0.9).cgColor
        brushRingLayer.lineWidth = 1.25
        brushRingLayer.isHidden = true
        brushRingLayer.zPosition = 50
        layer?.addSublayer(brushRingLayer)

        clickBoxLayer.fillColor = LaughTheme.interactiveAccent.withAlphaComponent(0.12).cgColor
        clickBoxLayer.strokeColor = LaughTheme.interactiveAccent.withAlphaComponent(0.95).cgColor
        clickBoxLayer.lineWidth = 1.0
        clickBoxLayer.lineDashPattern = [4, 3]
        clickBoxLayer.isHidden = true
        clickBoxLayer.zPosition = 51
        layer?.addSublayer(clickBoxLayer)

        configureAntsOverlayLayer(antsWhiteLayer, color: .white, dashPhase: 0)
        configureAntsOverlayLayer(antsBlackLayer, color: .black, dashPhase: 5)
        layer?.addSublayer(antsWhiteLayer)
        layer?.addSublayer(antsBlackLayer)

        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.isHidden = true
        cropOverlay.onDraftChanged = { [weak self] _ in
            self?.needsDisplay = true
        }
        cropOverlay.onStraightenChanged = { [weak self] radians in
            guard let self, self.isCropMode else { return }
            self.draftStraightenRadians = radians
            self.refreshDisplayedImage(quality: .preview)
            self.needsLayout = true
        }
        cropOverlay.onStraightenDragEnded = { [weak self] in
            guard let self, self.isCropMode else { return }
            self.refreshDisplayedImage(quality: .full)
            self.needsLayout = true
        }
        cropOverlay.onApplyRequested = { [weak self] in
            self?.applyCropDraft()
        }
        addSubview(cropOverlay)
        NSLayoutConstraint.activate([
            cropOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            cropOverlay.topAnchor.constraint(equalTo: topAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    /// Keep pan / crop drags from becoming a window move under full-size content chrome.
    override var mouseDownCanMoveWindow: Bool { false }

    var image: NSImage? {
        imageView.image
    }

    var isApproximatelyFitZoom: Bool {
        abs(zoomScale - 1.0) < 0.02
    }

    var hasNonIdentityCrop: Bool {
        !ImageCropGeometry.isIdentity(appliedCropNormalized)
            || !ImageCropGeometry.isIdentityStraighten(appliedStraightenRadians)
            || flipHorizontal
            || flipVertical
    }

    var draftCropNormalized: CGRect {
        cropOverlay.draftNormalized
    }

    /// Oriented full-frame pixel size (before applied crop), including live straighten in crop mode.
    private var orientedPixelSize: CGSize {
        let base: CGSize
        if rotationQuarterTurns % 2 != 0 {
            base = CGSize(width: naturalPixelSize.height, height: naturalPixelSize.width)
        } else {
            base = naturalPixelSize
        }
        let straighten = isCropMode ? draftStraightenRadians : appliedStraightenRadians
        guard !ImageCropGeometry.isIdentityStraighten(straighten) else { return base }
        // Bounding box of a rect rotated about center.
        let cosA = abs(cos(straighten))
        let sinA = abs(sin(straighten))
        return CGSize(
            width: base.width * cosA + base.height * sinA,
            height: base.width * sinA + base.height * cosA
        )
    }

    private var displayPixelSize: CGSize {
        let oriented = orientedPixelSize
        guard !isCropMode, let crop = appliedCropNormalized, !ImageCropGeometry.isIdentity(crop) else {
            return oriented
        }
        let pixel = ImageCropGeometry.pixelRect(normalized: crop, imageSize: oriented)
        return CGSize(width: max(pixel.width, 1), height: max(pixel.height, 1))
    }

    func setImage(_ image: NSImage, naturalSize: CGSize) {
        baseImage = image
        naturalPixelSize = naturalSize
        rotationQuarterTurns = 0
        flipHorizontal = false
        flipVertical = false
        appliedCropNormalized = nil
        appliedStraightenRadians = 0
        draftStraightenRadians = 0
        exitCropMode(apply: false)
        zoomScale = 1.0
        panOffset = .zero
        selectionMask = nil
        selectionDisplayMode = .none
        syncMarchingAntsAnimation()
        rebuildSourceCIImages(from: image)
        refreshDisplayedImage(quality: .full)
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        onZoomScaleChanged?()
        onCropChanged?()
    }

    func clearImage() {
        baseImage = nil
        baseCIImage = nil
        previewCIImage = nil
        cachedSourceToken = nil
        imageView.image = nil
        naturalPixelSize = .zero
        zoomScale = 1.0
        panOffset = .zero
        isPanning = false
        rotationQuarterTurns = 0
        flipHorizontal = false
        flipVertical = false
        appliedCropNormalized = nil
        appliedStraightenRadians = 0
        draftStraightenRadians = 0
        exitCropMode(apply: false)
        adjustParameters = .identity
        selectionMask = nil
        selectionDisplayMode = .none
        syncMarchingAntsAnimation()
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        onZoomScaleChanged?()
        onCropChanged?()
    }

    func resetZoom() {
        panOffset = .zero
        applyZoomScale(1.0)
    }

    func setZoomScale(_ scale: CGFloat) {
        applyZoomScale(scale)
    }

    func setActualSizeZoom(backingScaleFactor: CGFloat) {
        applyZoomScale(actualSizeZoomScale(backingScaleFactor: backingScaleFactor))
    }

    func actualSizeZoomScale(backingScaleFactor: CGFloat) -> CGFloat {
        let fit = fitSize(in: bounds)
        guard fit.width > 0 else { return 1 }
        let targetWidth = displayPixelSize.width / max(backingScaleFactor, 1)
        return max(targetWidth / fit.width, Self.minZoom)
    }

    override func resetCursorRects() {
        if selectionBrushEnabled, selectionMask != nil {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }
        if selectionClickEnabled {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }
        if canPanImage {
            addCursorRect(bounds, cursor: isPanning ? .closedHand : .openHand)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let brushTrackingArea {
            removeTrackingArea(brushTrackingArea)
            self.brushTrackingArea = nil
        }
        guard selectionBrushEnabled || selectionClickEnabled else { return }
        let options: NSTrackingArea.Options = [
            .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        brushTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        if selectionBrushEnabled, selectionMask != nil {
            let viewPoint = convert(event.locationInWindow, from: nil)
            brushCursorViewPoint = viewPoint
            updateBrushRing()
            return
        }
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        if selectionBrushEnabled {
            brushRingLayer.isHidden = false
            updateBrushRing()
        }
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        brushCursorViewPoint = nil
        brushRingLayer.isHidden = true
        super.mouseExited(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard baseImage != nil, !isCropMode else {
            super.scrollWheel(with: event)
            return
        }
        // Trackpad / mouse wheel over the photo zooms fit size.
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 12
        guard abs(dy) > 0.05 else { return }
        // Scroll up / pinch-out feel → zoom in.
        let factor = exp(dy * 0.012)
        applyZoomScale(zoomScale * factor)
    }

    override func magnify(with event: NSEvent) {
        guard baseImage != nil, !isCropMode else {
            super.magnify(with: event)
            return
        }
        applyZoomScale(zoomScale * (1 + event.magnification))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isCropMode { return }
        if event.clickCount == 2 {
            isPanning = false
            isBrushing = false
            clearClickDrag()
            onDoubleClick?()
            return
        }
        if selectionBrushEnabled, selectionMask != nil {
            let viewPoint = convert(event.locationInWindow, from: nil)
            brushCursorViewPoint = viewPoint
            updateBrushRing()
            if let pixel = selectionPixelPoint(fromViewPoint: viewPoint) {
                isBrushing = true
                lastBrushPixelPoint = pixel
                onSelectionBrushStroke?(pixel)
                return
            }
        }
        if selectionClickEnabled {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let pixel = selectionPixelPoint(fromViewPoint: viewPoint) {
                clickDragStartView = viewPoint
                clickDragStartPixel = pixel
                clickDragCurrentView = viewPoint
                updateClickBoxOverlay()
                return
            }
        }
        if canPanImage {
            isPanning = true
            panGestureStartMouse = event.locationInWindow
            panGestureStartOffset = panOffset
            NSCursor.closedHand.set()
            window?.invalidateCursorRects(for: self)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isBrushing {
            let viewPoint = convert(event.locationInWindow, from: nil)
            brushCursorViewPoint = viewPoint
            updateBrushRing()
            guard let pixel = selectionPixelPoint(fromViewPoint: viewPoint) else { return }
            if let last = lastBrushPixelPoint {
                let dx = pixel.x - last.x
                let dy = pixel.y - last.y
                let dist = hypot(dx, dy)
                let step = max(2, selectionBrushRadius * 0.35)
                if dist < step { return }
            }
            lastBrushPixelPoint = pixel
            onSelectionBrushStroke?(pixel)
            return
        }
        if clickDragStartView != nil {
            let viewPoint = convert(event.locationInWindow, from: nil)
            clickDragCurrentView = viewPoint
            updateClickBoxOverlay()
            return
        }
        guard isPanning else {
            super.mouseDragged(with: event)
            return
        }
        let loc = event.locationInWindow
        let proposed = CGPoint(
            x: panGestureStartOffset.x + (loc.x - panGestureStartMouse.x),
            y: panGestureStartOffset.y + (loc.y - panGestureStartMouse.y)
        )
        let clamped = clampPanOffset(proposed)
        guard abs(clamped.x - panOffset.x) > 0.05 || abs(clamped.y - panOffset.y) > 0.05 else { return }
        panOffset = clamped
        needsLayout = true
    }

    override func mouseUp(with event: NSEvent) {
        if isBrushing {
            isBrushing = false
            lastBrushPixelPoint = nil
            onSelectionBrushStrokeEnded?()
            return
        }
        if let startView = clickDragStartView, let startPixel = clickDragStartPixel {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let dragDist = hypot(viewPoint.x - startView.x, viewPoint.y - startView.y)
            let flags = event.modifierFlags.intersection([.shift, .option])
            let additive = flags.contains(.shift)
            let negative = flags.contains(.option)
            if dragDist >= Self.boxDragThresholdPoints,
               let endPixel = selectionPixelPoint(fromViewPoint: viewPoint)
            {
                let box = CGRect(
                    x: min(startPixel.x, endPixel.x),
                    y: min(startPixel.y, endPixel.y),
                    width: abs(endPixel.x - startPixel.x),
                    height: abs(endPixel.y - startPixel.y)
                )
                if box.width > 2, box.height > 2 {
                    onSelectionBox?(box, additive)
                } else {
                    onSelectionClick?(startPixel, negative, additive)
                }
            } else {
                onSelectionClick?(startPixel, negative, additive)
            }
            clearClickDrag()
            return
        }
        if isPanning {
            isPanning = false
            window?.invalidateCursorRects(for: self)
            if canPanImage {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        super.mouseUp(with: event)
    }

    private func applyZoomScale(_ scale: CGFloat) {
        let clamped = min(max(scale, Self.minZoom), Self.maxZoom)
        let zoomChanged = abs(clamped - zoomScale) > 0.0005
        zoomScale = clamped
        if canPanImage {
            panOffset = clampPanOffset(panOffset)
        } else {
            panOffset = .zero
        }
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        if zoomChanged {
            onZoomScaleChanged?()
        }
    }

    func setAdjustParameters(_ parameters: ImageAdjustParameters, quality: ImageAdjustRenderQuality = .full) {
        let paramsChanged = parameters != adjustParameters
        adjustParameters = parameters
        guard paramsChanged || quality == .full else { return }
        refreshDisplayedImage(quality: quality)
    }

    func setSelectionPreview(
        mask: SelectionMask?,
        displayMode: SelectionDisplayMode,
        refine: SelectionRefineParameters = .identity,
        quality: ImageAdjustRenderQuality = .full
    ) {
        selectionMask = mask
        selectionDisplayMode = displayMode
        selectionRefine = refine
        rebuildAntsContour()
        syncMarchingAntsAnimation()
        refreshDisplayedImage(quality: quality)
    }

    private func syncMarchingAntsAnimation() {
        let shouldAnimate = selectionMask != nil && selectionDisplayMode == .marchingAnts
        if shouldAnimate {
            updateAntsOverlayGeometry()
            guard marchingAntsTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.marchingAntsPhase += 1.25
                // Opposite phase on black/white layers → classic ------ ants along the path.
                self.antsWhiteLayer.lineDashPhase = self.marchingAntsPhase
                self.antsBlackLayer.lineDashPhase = self.marchingAntsPhase + 5
            }
            RunLoop.main.add(timer, forMode: .common)
            marchingAntsTimer = timer
        } else {
            marchingAntsTimer?.invalidate()
            marchingAntsTimer = nil
            marchingAntsPhase = 0
            antsWhiteLayer.isHidden = true
            antsBlackLayer.isHidden = true
            antsWhiteLayer.path = nil
            antsBlackLayer.path = nil
        }
    }

    /// Extract exact silhouette path (display-space matte) for CAShapeLayer ants.
    private func rebuildAntsContour() {
        guard let selectionMask,
              selectionDisplayMode == .marchingAnts,
              let baseCIImage
        else {
            antsNormalizedPath = nil
            updateAntsOverlayGeometry()
            return
        }

        let crop = effectiveCropForDisplay()
        let straighten = effectiveStraightenForDisplay()
        var maskCI = selectionMask.ciImageMatching(extent: baseCIImage.extent)
        maskCI = selectionRefine.applying(to: maskCI, extent: baseCIImage.extent)
        maskCI = Self.rotatedCIImage(maskCI, quarterTurns: rotationQuarterTurns)
        maskCI = Self.flippedCIImage(maskCI, horizontal: flipHorizontal, vertical: flipVertical)
        maskCI = Self.straightenedCIImage(maskCI, radians: straighten)
        if let crop, !ImageCropGeometry.isIdentity(crop) {
            let size = CGSize(width: maskCI.extent.width, height: maskCI.extent.height)
            let pixel = ImageCropGeometry.pixelRect(normalized: crop, imageSize: size)
            let cropInExtent = pixel.offsetBy(dx: maskCI.extent.minX, dy: maskCI.extent.minY)
            maskCI = maskCI.cropped(to: cropInExtent)
            if maskCI.extent.origin != .zero {
                maskCI = maskCI.transformed(
                    by: CGAffineTransform(translationX: -maskCI.extent.minX, y: -maskCI.extent.minY)
                )
            }
        }
        let plateExtent = maskCI.extent.integral
        var plate = SelectionMatteNormalization.opaqueCoverage(
            matte: maskCI,
            extent: plateExtent,
            context: ciContext
        )
        plate = SelectionCompositor.hardBinaryMatte(mask: plate, extent: plateExtent)

        let longEdge = max(plateExtent.width, plateExtent.height)
        if longEdge > SelectionAntsContour.plateMaxEdge {
            let scale = SelectionAntsContour.plateMaxEdge / longEdge
            plate = plate.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let renderExtent = plate.extent.integral
        // Re-threshold after downscale so the boundary stays on the half-coverage line,
        // then fill pinholes that would otherwise read as spurious interior contours.
        plate = SelectionCompositor.hardBinaryMatte(mask: plate, extent: renderExtent)
        plate = SelectionAntsContour.cleanedHardMatte(plate, extent: renderExtent)
        guard let cg = ciContext.createCGImage(plate, from: renderExtent) else {
            antsNormalizedPath = nil
            updateAntsOverlayGeometry()
            return
        }
        antsNormalizedPath = SelectionAntsContour.normalizedPath(fromHardMatte: cg)
        updateAntsOverlayGeometry()
    }

    private func updateAntsOverlayGeometry() {
        guard let antsNormalizedPath,
              selectionMask != nil,
              selectionDisplayMode == .marchingAnts
        else {
            antsWhiteLayer.isHidden = true
            antsBlackLayer.isHidden = true
            antsWhiteLayer.path = nil
            antsBlackLayer.path = nil
            return
        }
        let frame = photoFrameInOverlay()
        guard let viewPath = SelectionAntsContour.pathInView(
            normalized: antsNormalizedPath,
            photoFrame: frame
        ) else {
            antsWhiteLayer.isHidden = true
            antsBlackLayer.isHidden = true
            return
        }
        antsWhiteLayer.path = viewPath
        antsBlackLayer.path = viewPath
        antsWhiteLayer.isHidden = false
        antsBlackLayer.isHidden = false
        antsWhiteLayer.lineDashPhase = marchingAntsPhase
        antsBlackLayer.lineDashPhase = marchingAntsPhase + 5
    }

    /// Base CIImage in source pixel space for selection providers.
    var selectionSourceCIImage: CIImage? { baseCIImage }

    func setSelectionBrushEnabled(_ enabled: Bool) {
        selectionBrushEnabled = enabled
        if enabled { selectionClickEnabled = false }
        if !enabled {
            isBrushing = false
            lastBrushPixelPoint = nil
            brushCursorViewPoint = nil
            brushRingLayer.isHidden = true
        } else {
            brushRingLayer.isHidden = brushCursorViewPoint == nil
            updateBrushRing()
        }
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    func setSelectionClickEnabled(_ enabled: Bool) {
        selectionClickEnabled = enabled
        if enabled {
            selectionBrushEnabled = false
            brushRingLayer.isHidden = true
        }
        if !enabled {
            clearClickDrag()
        }
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    func setSelectionBrushRadius(_ radius: CGFloat) {
        selectionBrushRadius = min(120, max(4, radius))
        updateBrushRing()
    }

    private func clearClickDrag() {
        clickDragStartView = nil
        clickDragStartPixel = nil
        clickDragCurrentView = nil
        clickBoxLayer.isHidden = true
        clickBoxLayer.path = nil
    }

    private func updateClickBoxOverlay() {
        guard let start = clickDragStartView, let current = clickDragCurrentView else {
            clickBoxLayer.isHidden = true
            return
        }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard rect.width >= Self.boxDragThresholdPoints || rect.height >= Self.boxDragThresholdPoints else {
            clickBoxLayer.isHidden = true
            return
        }
        clickBoxLayer.path = CGPath(rect: rect, transform: nil)
        clickBoxLayer.isHidden = false
    }

    /// View-space radius matching `selectionBrushRadius` image pixels on the fitted photo.
    private func brushRadiusInViewPoints() -> CGFloat {
        let photo = photoFrameInOverlay()
        let pixelW = max(orientedPixelSize.width, 1)
        return selectionBrushRadius * (photo.width / pixelW)
    }

    private func updateBrushRing() {
        guard selectionBrushEnabled, selectionMask != nil, let point = brushCursorViewPoint else {
            brushRingLayer.isHidden = true
            return
        }
        let photo = photoFrameInOverlay()
        guard photo.contains(point) else {
            brushRingLayer.isHidden = true
            return
        }
        let r = brushRadiusInViewPoints()
        // Layer-backed NSView geometry matches view coords (origin bottom-left).
        let path = CGPath(
            ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2),
            transform: nil
        )
        brushRingLayer.path = path
        brushRingLayer.strokeColor = LaughTheme.interactiveAccent.withAlphaComponent(0.95).cgColor
        brushRingLayer.isHidden = false
    }

    /// Map a view point onto source (base) pixel space. Best when orientation is identity.
    func selectionPixelPoint(fromViewPoint viewPoint: CGPoint) -> CGPoint? {
        guard let baseCIImage else { return nil }
        let photo = photoFrameInOverlay()
        guard photo.width > 1, photo.height > 1, photo.contains(viewPoint) else { return nil }
        let nx = (viewPoint.x - photo.minX) / photo.width
        let ny = (viewPoint.y - photo.minY) / photo.height
        let oriented = orientedPixelSize
        guard oriented.width > 1, oriented.height > 1 else { return nil }
        var ox = nx * oriented.width
        var oy = ny * oriented.height
        // Undo flip (applied after rotate in the display pipeline).
        if flipHorizontal { ox = oriented.width - ox }
        if flipVertical { oy = oriented.height - oy }
        // Undo quarter-turns (CI rotates CCW by turns * 90°).
        let turns = ((rotationQuarterTurns % 4) + 4) % 4
        let baseSize = naturalPixelSize
        let bx: CGFloat
        let by: CGFloat
        switch turns {
        case 1: // 90° CCW display ← inverse 90° CW
            bx = oy
            by = oriented.width - ox
        case 2:
            bx = oriented.width - ox
            by = oriented.height - oy
        case 3: // 270° CCW ← inverse 90° CCW
            bx = oriented.height - oy
            by = ox
        default:
            bx = ox
            by = oy
        }
        let extent = baseCIImage.extent
        return CGPoint(
            x: extent.minX + min(max(bx, 0), baseSize.width - 0.5),
            y: extent.minY + min(max(by, 0), baseSize.height - 0.5)
        )
    }

    func rotateLeft() {
        rotationQuarterTurns = (rotationQuarterTurns + 3) % 4
        applyOrientationChange()
    }

    func rotateRight() {
        rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
        applyOrientationChange()
    }

    func flipHorizontalAxis() {
        flipHorizontal.toggle()
        applyOrientationChange()
    }

    func flipVerticalAxis() {
        flipVertical.toggle()
        applyOrientationChange()
    }

    /// Shared path for rotate / flip: clears crop+straighten draft and refreshes.
    private func applyOrientationChange() {
        appliedStraightenRadians = 0
        draftStraightenRadians = 0
        if !isCropMode {
            appliedCropNormalized = nil
        }
        panOffset = .zero
        rebuildAntsContour()
        refreshDisplayedImage(quality: .full)
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateAntsOverlayGeometry()
        if isCropMode {
            let draft = ImageCropGeometry.defaultNormalizedRect(
                aspect: cropAspect,
                imageSize: orientedPixelSize
            )
            layoutCropOverlay(draft: draft)
            window?.invalidateCursorRects(for: cropOverlay)
        }
        window?.invalidateCursorRects(for: self)
        onCropChanged?()
    }

    @discardableResult
    func enterCropMode(aspect: ImageCropAspect = .free) -> Bool {
        guard baseImage != nil else { return false }
        isCropMode = true
        cropAspect = aspect
        cropSessionRotationQuarterTurns = rotationQuarterTurns
        cropSessionFlipHorizontal = flipHorizontal
        cropSessionFlipVertical = flipVertical
        draftStraightenRadians = appliedStraightenRadians
        resetZoom()
        isPanning = false
        cropOverlay.isHidden = false
        let draft = appliedCropNormalized ?? ImageCropGeometry.defaultNormalizedRect(
            aspect: aspect,
            imageSize: orientedPixelSize
        )
        layoutCropOverlay(draft: draft)
        refreshDisplayedImage(quality: .full)
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        window?.invalidateCursorRects(for: cropOverlay)
        return true
    }

    func setCropAspect(_ aspect: ImageCropAspect) {
        guard isCropMode else { return }
        cropAspect = aspect
        cropOverlay.setAspect(aspect)
        layoutCropOverlay(draft: cropOverlay.draftNormalized)
    }

    func applyCropDraft() {
        guard isCropMode else { return }
        let draft = ImageCropGeometry.sanitized(cropOverlay.draftNormalized)
        appliedCropNormalized = ImageCropGeometry.isIdentity(draft) ? nil : draft
        appliedStraightenRadians = ImageCropGeometry.clampStraightenRadians(draftStraightenRadians)
        if ImageCropGeometry.isIdentityStraighten(appliedStraightenRadians) {
            appliedStraightenRadians = 0
        }
        exitCropMode(apply: true)
        onCropChanged?()
    }

    /// - Parameter restoreOriginal: when true (Cancel), clears applied crop/straighten and
    ///   restores rotation/flips to the values from crop-mode entry.
    func cancelCropMode(restoreOriginal: Bool = false) {
        if restoreOriginal {
            appliedCropNormalized = nil
            appliedStraightenRadians = 0
            draftStraightenRadians = 0
            rotationQuarterTurns = cropSessionRotationQuarterTurns
            flipHorizontal = cropSessionFlipHorizontal
            flipVertical = cropSessionFlipVertical
        }
        exitCropMode(apply: false)
        if restoreOriginal {
            onCropChanged?()
        }
    }

    /// Clears crop, straighten, flips, and quarter-turn rotation.
    func resetDisplayGeometry() {
        if isCropMode {
            exitCropMode(apply: false)
        }
        appliedCropNormalized = nil
        appliedStraightenRadians = 0
        draftStraightenRadians = 0
        rotationQuarterTurns = 0
        flipHorizontal = false
        flipVertical = false
        panOffset = .zero
        zoomScale = 1.0
        refreshDisplayedImage(quality: .full)
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        onZoomScaleChanged?()
        onCropChanged?()
    }

    private func exitCropMode(apply: Bool) {
        guard isCropMode || !cropOverlay.isHidden else { return }
        isCropMode = false
        if !apply {
            draftStraightenRadians = appliedStraightenRadians
        }
        cropOverlay.isHidden = true
        refreshDisplayedImage(quality: .full)
        needsLayout = true
        window?.invalidateCursorRects(for: self)
    }

    private func layoutCropOverlay(draft: CGRect? = nil) {
        guard isCropMode else { return }
        let draftRect = draft ?? cropOverlay.draftNormalized
        let preSize = ImageCropGeometry.preStraightenSize(
            natural: naturalPixelSize,
            quarterTurns: rotationQuarterTurns
        )
        cropOverlay.configure(
            draftNormalized: draftRect,
            aspect: cropAspect,
            imageSize: orientedPixelSize,
            preStraightenSize: preSize,
            imageFrameInOverlay: photoFrameInOverlay(),
            straightenRadians: draftStraightenRadians
        )
    }

    /// Visible photo rect inside the surface (accounts for aspect-fit letterboxing in the image view).
    private func photoFrameInOverlay() -> CGRect {
        let frame = imageView.frame
        guard let image = imageView.image else { return frame }
        let fitted = Self.aspectFitRect(imageSize: image.size, in: frame.size)
        return fitted.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    private static func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0.5, imageSize.height > 0.5,
              container.width > 0.5, container.height > 0.5 else {
            return CGRect(origin: .zero, size: container)
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        if imageAspect > containerAspect {
            let height = container.width / imageAspect
            return CGRect(
                x: 0,
                y: (container.height - height) / 2,
                width: container.width,
                height: height
            )
        }
        let width = container.height * imageAspect
        return CGRect(
            x: (container.width - width) / 2,
            y: 0,
            width: width,
            height: container.height
        )
    }

    override func layout() {
        super.layout()
        guard displayPixelSize.width > 0, displayPixelSize.height > 0 else {
            imageView.frame = bounds
            return
        }

        let viewWidth = bounds.width
        let viewHeight = bounds.height
        guard viewWidth > 0, viewHeight > 0 else { return }

        let displayed = displayedImageSize(in: bounds)
        panOffset = isCropMode ? .zero : clampPanOffset(panOffset)
        imageView.frame = NSRect(
            x: (viewWidth - displayed.width) / 2 + panOffset.x,
            y: (viewHeight - displayed.height) / 2 + panOffset.y,
            width: displayed.width,
            height: displayed.height
        )
        if isCropMode {
            layoutCropOverlay()
        }
        updateBrushRing()
        updateAntsOverlayGeometry()
    }

    private func configureAntsOverlayLayer(_ layer: CAShapeLayer, color: NSColor, dashPhase: CGFloat) {
        layer.fillColor = nil
        layer.strokeColor = color.cgColor
        layer.lineWidth = 1.5
        layer.lineJoin = .round
        layer.lineCap = .butt
        layer.lineDashPattern = [5, 5]
        layer.lineDashPhase = dashPhase
        layer.isHidden = true
        layer.zPosition = 45
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    private var canPanImage: Bool {
        guard baseImage != nil, !isCropMode, bounds.width > 1, bounds.height > 1 else { return false }
        let displayed = displayedImageSize(in: bounds)
        return displayed.width > bounds.width + 0.5 || displayed.height > bounds.height + 0.5
    }

    private func displayedImageSize(in bounds: NSRect) -> CGSize {
        let fit = fitSize(in: bounds)
        let contentScale: CGFloat = 0.92
        return CGSize(
            width: fit.width * zoomScale * contentScale,
            height: fit.height * zoomScale * contentScale
        )
    }

    private func clampPanOffset(_ proposed: CGPoint) -> CGPoint {
        guard bounds.width > 1, bounds.height > 1 else { return .zero }
        let displayed = displayedImageSize(in: bounds)
        let maxX = max(0, (displayed.width - bounds.width) / 2)
        let maxY = max(0, (displayed.height - bounds.height) / 2)
        return CGPoint(
            x: min(max(proposed.x, -maxX), maxX),
            y: min(max(proposed.y, -maxY), maxY)
        )
    }

    private func fitSize(in bounds: NSRect) -> CGSize {
        let viewWidth = bounds.width
        let viewHeight = bounds.height
        guard viewWidth > 0, viewHeight > 0,
              displayPixelSize.width > 0, displayPixelSize.height > 0 else {
            return .zero
        }

        let imageAspect = displayPixelSize.width / displayPixelSize.height
        let viewAspect = viewWidth / viewHeight
        if imageAspect > viewAspect {
            return CGSize(width: viewWidth, height: viewWidth / imageAspect)
        }
        return CGSize(width: viewHeight * imageAspect, height: viewHeight)
    }

    private func rebuildSourceCIImages(from image: NSImage) {
        cachedSourceToken = ObjectIdentifier(image)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            baseCIImage = nil
            previewCIImage = nil
            return
        }
        let full = CIImage(cgImage: cgImage)
        baseCIImage = full
        previewCIImage = Self.scaledCIImage(full, maxEdge: ImageAdjustRenderQuality.preview.maxPixelEdge)
    }

    private func refreshDisplayedImage(quality: ImageAdjustRenderQuality) {
        guard let baseImage else {
            imageView.image = nil
            return
        }
        if cachedSourceToken != ObjectIdentifier(baseImage) {
            rebuildSourceCIImages(from: baseImage)
        }

        let crop = effectiveCropForDisplay()
        let straighten = effectiveStraightenForDisplay()
        let hasSelectionPreview = selectionMask != nil && selectionDisplayMode != .none
        let needsPipeline = !adjustParameters.isIdentity
            || crop != nil
            || rotationQuarterTurns != 0
            || flipHorizontal
            || flipVertical
            || !ImageCropGeometry.isIdentityStraighten(straighten)
            || hasSelectionPreview

        if !needsPipeline {
            imageView.image = baseImage
            return
        }

        // Always render orientation via CI — the NSImage CGContext path silently
        // no-ops for many still formats when no crop/adjusts are active yet.
        let generation = fullRenderGeneration + 1
        fullRenderGeneration = generation
        let parameters = adjustParameters
        let turns = rotationQuarterTurns
        let flipH = flipHorizontal
        let flipV = flipVertical
        let cropRect = crop
        let straightenRadians = straighten

        if quality == .preview {
            if let preview = renderAdjustedImage(
                parameters: parameters,
                quarterTurns: turns,
                flipHorizontal: flipH,
                flipVertical: flipV,
                straightenRadians: straightenRadians,
                cropNormalized: cropRect,
                quality: .preview
            ) {
                imageView.image = preview
            }
            return
        }

        // Keep rotate/flip snappy: run sync when develop is identity (crop chrome / toolbar).
        if parameters.isIdentity {
            if let rendered = renderAdjustedImage(
                parameters: parameters,
                quarterTurns: turns,
                flipHorizontal: flipH,
                flipVertical: flipV,
                straightenRadians: straightenRadians,
                cropNormalized: cropRect,
                quality: .full
            ) {
                imageView.image = rendered
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let rendered = self.renderAdjustedImage(
                parameters: parameters,
                quarterTurns: turns,
                flipHorizontal: flipH,
                flipVertical: flipV,
                straightenRadians: straightenRadians,
                cropNormalized: cropRect,
                quality: .full
            )
            DispatchQueue.main.async {
                guard self.fullRenderGeneration == generation else { return }
                if let rendered {
                    self.imageView.image = rendered
                }
            }
        }
    }

    /// Crop applied to the on-screen bitmap. Skipped while editing crop so the full frame stays visible.
    private func effectiveCropForDisplay() -> CGRect? {
        if isCropMode { return nil }
        guard let crop = appliedCropNormalized, !ImageCropGeometry.isIdentity(crop) else { return nil }
        return crop
    }

    private func effectiveStraightenForDisplay() -> CGFloat {
        if isCropMode { return draftStraightenRadians }
        return appliedStraightenRadians
    }

    private func renderAdjustedImage(
        parameters: ImageAdjustParameters,
        quarterTurns: Int,
        flipHorizontal: Bool,
        flipVertical: Bool,
        straightenRadians: CGFloat,
        cropNormalized: CGRect?,
        quality: ImageAdjustRenderQuality
    ) -> NSImage? {
        guard let baseCIImage else { return nil }
        let source: CIImage
        if quality == .preview, let previewCIImage {
            source = previewCIImage
        } else {
            source = baseCIImage
        }
        var current = Self.rotatedCIImage(source, quarterTurns: quarterTurns)
        current = Self.flippedCIImage(current, horizontal: flipHorizontal, vertical: flipVertical)
        current = Self.straightenedCIImage(current, radians: straightenRadians)
        // Empty AABB corners after straighten must not render as black — match the studio floor.
        if cropNormalized == nil,
           !ImageCropGeometry.isIdentityStraighten(straightenRadians) || isCropMode {
            current = Self.compositeOverStudioFloor(current, appearance: effectiveAppearance)
        }
        if let cropNormalized, !ImageCropGeometry.isIdentity(cropNormalized) {
            let size = CGSize(width: current.extent.width, height: current.extent.height)
            let pixel = ImageCropGeometry.pixelRect(normalized: cropNormalized, imageSize: size)
            let cropInExtent = pixel.offsetBy(dx: current.extent.minX, dy: current.extent.minY)
            current = current.cropped(to: cropInExtent)
            if current.extent.origin != .zero {
                current = current.transformed(
                    by: CGAffineTransform(translationX: -current.extent.minX, y: -current.extent.minY)
                )
            }
        }
        if let output = parameters.applying(to: current) {
            current = output
        }
        if let selectionMask, selectionDisplayMode != .none {
            // Mask is in source pixel space; transform like the photo into the display frame.
            let pipelineSource = quality == .preview ? (previewCIImage ?? baseCIImage) : baseCIImage
            var maskCI = selectionMask.ciImageMatching(extent: pipelineSource.extent)
            maskCI = Self.rotatedCIImage(maskCI, quarterTurns: quarterTurns)
            maskCI = Self.flippedCIImage(maskCI, horizontal: flipHorizontal, vertical: flipVertical)
            maskCI = Self.straightenedCIImage(maskCI, radians: straightenRadians)
            if let cropNormalized, !ImageCropGeometry.isIdentity(cropNormalized) {
                let size = CGSize(width: maskCI.extent.width, height: maskCI.extent.height)
                let pixel = ImageCropGeometry.pixelRect(normalized: cropNormalized, imageSize: size)
                let cropInExtent = pixel.offsetBy(dx: maskCI.extent.minX, dy: maskCI.extent.minY)
                maskCI = maskCI.cropped(to: cropInExtent)
                if maskCI.extent.origin != .zero {
                    maskCI = maskCI.transformed(
                        by: CGAffineTransform(translationX: -maskCI.extent.minX, y: -maskCI.extent.minY)
                    )
                }
            }
            current = SelectionCompositor.apply(
                image: current,
                maskCI: maskCI,
                mode: selectionDisplayMode,
                appearance: effectiveAppearance,
                refine: selectionRefine,
                antsPhase: marchingAntsPhase
            )
        }
        return nsImage(from: current)
    }

    private func nsImage(from ciImage: CIImage) -> NSImage? {
        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgImage = ciContext.createCGImage(
            ciImage,
            from: extent,
            format: .RGBA8,
            colorSpace: colorSpace,
            deferred: false
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Fill transparent straighten corners with the image-studio floor (never hard black).
    private static func compositeOverStudioFloor(
        _ image: CIImage,
        appearance: NSAppearance
    ) -> CIImage {
        let floor = LaughTheme.imageStudioFloorColor(appearance: appearance)
        guard let rgb = floor.usingColorSpace(.deviceRGB) else { return image }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let backdrop = CIImage(color: CIColor(red: r, green: g, blue: b, alpha: 1))
            .cropped(to: image.extent)
        return image.composited(over: backdrop)
    }

    private static func scaledCIImage(_ image: CIImage, maxEdge: CGFloat) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private static func rotatedCIImage(_ image: CIImage, quarterTurns: Int) -> CIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let radians = CGFloat(turns) * (.pi / 2)
        let extent = image.extent
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: extent.midX, y: extent.midY)
        transform = transform.rotated(by: radians)
        transform = transform.translatedBy(x: -extent.midX, y: -extent.midY)
        let rotated = image.transformed(by: transform)
        return normalizeExtent(rotated.cropped(to: rotated.extent.integral))
    }

    private static func flippedCIImage(
        _ image: CIImage,
        horizontal: Bool,
        vertical: Bool
    ) -> CIImage {
        guard horizontal || vertical else { return image }
        let extent = image.extent
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: extent.midX, y: extent.midY)
        transform = transform.scaledBy(x: horizontal ? -1 : 1, y: vertical ? -1 : 1)
        transform = transform.translatedBy(x: -extent.midX, y: -extent.midY)
        let flipped = image.transformed(by: transform)
        return normalizeExtent(flipped.cropped(to: flipped.extent.integral))
    }

    private static func straightenedCIImage(_ image: CIImage, radians: CGFloat) -> CIImage {
        let angle = ImageCropGeometry.clampStraightenRadians(radians)
        guard !ImageCropGeometry.isIdentityStraighten(angle) else { return image }
        let extent = image.extent
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: extent.midX, y: extent.midY)
        transform = transform.rotated(by: angle)
        transform = transform.translatedBy(x: -extent.midX, y: -extent.midY)
        let rotated = image.transformed(by: transform)
        // Keep transparent corners (don’t bake black). Crop chrome dims the pad instead.
        return normalizeExtent(rotated.cropped(to: rotated.extent.integral))
    }

    private static func normalizeExtent(_ image: CIImage) -> CIImage {
        var out = image
        if out.extent.origin != .zero {
            out = out.transformed(
                by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY)
            )
        }
        return out
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
    var onTogglePlayPause: (() -> Void)?

    private let videoSurface = MiniPlayerSurfaceView()
    private let imageSurface = NSImageView()
    private let expandBackdrop = NSView()
    private let expandButton = NSButton()
    private let closeBackdrop = NSView()
    private let closeButton = NSButton()
    private let playPauseBackdrop = NSView()
    private let playPauseButton = NSButton()
    private var isPlaying = false
    private var showsPlayPause = false

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
        styleChromeBackdrop(playPauseBackdrop)

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

        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.bezelStyle = .accessoryBarAction
        playPauseButton.isBordered = false
        playPauseButton.setButtonType(.momentaryPushIn)
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseClicked)
        playPauseButton.title = ""

        addSubview(videoSurface)
        addSubview(imageSurface)
        addSubview(expandBackdrop)
        addSubview(expandButton)
        addSubview(closeBackdrop)
        addSubview(closeButton)
        addSubview(playPauseBackdrop)
        addSubview(playPauseButton)

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

            playPauseBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            playPauseBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            playPauseBackdrop.widthAnchor.constraint(equalToConstant: 26),
            playPauseBackdrop.heightAnchor.constraint(equalToConstant: 26),

            playPauseButton.centerXAnchor.constraint(equalTo: playPauseBackdrop.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: playPauseBackdrop.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 26),
            playPauseButton.heightAnchor.constraint(equalToConstant: 26),

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
        setPlaying(false)
        setPlayPauseVisible(false)
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
        if showsPlayPause, hit === playPauseButton || hit === playPauseBackdrop {
            return playPauseButton
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
        setPlayPauseVisible(true)
    }

    func detachVideoPlayer() {
        clearContent()
    }

    func clearContent() {
        videoSurface.player = nil
        imageSurface.image = nil
        imageSurface.isHidden = true
        videoSurface.isHidden = false
        setPlayPauseVisible(false)
    }

    func showImage(_ image: NSImage?) {
        videoSurface.isHidden = true
        videoSurface.player = nil
        imageSurface.isHidden = false
        imageSurface.image = image
        setPlayPauseVisible(false)
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        let symbol = playing ? "pause.fill" : "play.fill"
        let label = playing ? "Pause" : "Play"
        playPauseButton.toolTip = label
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            playPauseButton.image = image.withSymbolConfiguration(config)
            playPauseButton.contentTintColor = .white
        }
        playPauseButton.title = ""
    }

    private func setPlayPauseVisible(_ visible: Bool) {
        showsPlayPause = visible
        playPauseBackdrop.isHidden = !visible
        playPauseButton.isHidden = !visible
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

    @objc private func playPauseClicked() {
        onTogglePlayPause?()
    }
}

/// Flat title-bar plate — matches the left library sidebar (`windowBackgroundColor`).
/// Visual only: clicks pass through so the window can drag / zoom and fullscreen double-click works.
private final class TitleBarChromeStripView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func refreshPlate() {
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.backgroundColor = LaughTheme.librarySidebarBackground(appearance: effectiveAppearance).cgColor
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
    var iconTintColor: NSColor = .secondaryLabelColor {
        didSet { updateTabAppearance() }
    }
    /// When true, icon is a rainbow gradient (selected image Edits/Presets tabs).
    var usesRainbowIcon: Bool = false {
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
        // Keep icon + label as one side-by-side group; a little air beyond a thin space.
        let titleWithGap = "\u{2009}\u{2009}" + tabLabel
        title = titleWithGap
        attributedTitle = NSAttributedString(
            string: titleWithGap,
            attributes: [
                .foregroundColor: textColor,
                .font: baseFont
            ]
        )
        setAccessibilityLabel(tabLabel)
        imageHugsTitle = true
        imagePosition = .imageLeading
        let pointSize = 11 * uiScale
        if usesRainbowIcon,
           let rainbow = LaughTheme.rainbowGradientSymbolImage(
            systemName: symbolName,
            pointSize: pointSize,
            weight: .medium
           ) {
            contentTintColor = nil
            image = rainbow
        } else if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: tabLabel) {
            contentTintColor = iconTintColor
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            image = symbol.withSymbolConfiguration(config)
            image?.isTemplate = true
        } else {
            contentTintColor = iconTintColor
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
        activeUnderline.isHidden = true
        addSubview(activeUnderline)
        applyActiveUnderlineColor()

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            button.bottomAnchor.constraint(equalTo: activeUnderline.topAnchor, constant: -Self.activeUnderlineGap),
            activeUnderline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            activeUnderline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyActiveUnderlineColor()
    }

    private func applyActiveUnderlineColor() {
        activeUnderline.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55).cgColor
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
    private let studioGradientLayer = CAGradientLayer()
    private var imageStudioGradientActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyChromeBackdrop()
        registerForDraggedTypes([.fileURL])
    }

    func setPlaybackBackdropActive(_ active: Bool) {
        if active {
            setImageStudioGradientActive(false)
            layer?.backgroundColor = NSColor.black.cgColor
        } else if !imageStudioGradientActive {
            applyChromeBackdrop()
        }
    }

    /// Soft diagonal wash for image studio (must stay very subtle).
    func setImageStudioGradientActive(_ active: Bool) {
        imageStudioGradientActive = active
        studioGradientLayer.isHidden = true
        if active {
            layer?.backgroundColor = LaughTheme.imageStudioFloorColor(appearance: effectiveAppearance).cgColor
        } else if layer?.backgroundColor == NSColor.black.cgColor {
            // Keep playback letterbox black when leaving image mode.
        } else {
            applyChromeBackdrop()
        }
        needsLayout = true
    }

    private func installStudioGradientIfNeeded() {
        guard studioGradientLayer.superlayer == nil else { return }
        studioGradientLayer.name = "imageStudioBackdrop"
        // True corner-to-corner diagonal (top-leading → bottom-trailing).
        studioGradientLayer.startPoint = CGPoint(x: 0, y: 1)
        studioGradientLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.insertSublayer(studioGradientLayer, at: 0)
    }

    private func refreshStudioGradientColors() {
        let colors = LaughTheme.imageStudioBackdropColors(appearance: effectiveAppearance)
        studioGradientLayer.colors = [colors.leading.cgColor, colors.mid.cgColor, colors.trailing.cgColor]
        studioGradientLayer.locations = [0, 0.55, 1]
    }

    private func applyChromeBackdrop() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func layout() {
        super.layout()
        if imageStudioGradientActive {
            studioGradientLayer.frame = bounds
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if imageStudioGradientActive {
            refreshStudioGradientColors()
        } else if layer?.backgroundColor != NSColor.black.cgColor {
            applyChromeBackdrop()
        }
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
    /// Backup scroll handler when the local monitor does not consume the event.
    var onScrollWheel: ((NSEvent) -> Bool)?
    private var mpvEmbeddingActive = false
    private var lastReportedMpvBounds: CGRect = .null
    private let avPlayerLayer = AVPlayerLayer()
    private let mpvHostView = MpvRenderHostView()

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if onScrollWheel?(event) == true { return }
        super.scrollWheel(with: event)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        avPlayerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        avPlayerLayer.videoGravity = .resizeAspect
        avPlayerLayer.backgroundColor = NSColor.black.cgColor
        mpvHostView.isHidden = true
        mpvHostView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mpvHostView)
        NSLayoutConstraint.activate([
            mpvHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mpvHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mpvHostView.topAnchor.constraint(equalTo: topAnchor),
            mpvHostView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let container = CALayer()
        container.backgroundColor = NSColor.black.cgColor
        avPlayerLayer.frame = bounds
        container.addSublayer(avPlayerLayer)
        return container
    }

    override func layout() {
        super.layout()
        avPlayerLayer.frame = bounds
        notifyMpvLayoutIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lastReportedMpvBounds = .null
        notifyMpvLayoutIfNeeded()
    }

    /// In-process libmpv draws into this layer. `--wid` is not used on modern macOS mpv.
    var mpvRenderLayer: MpvOpenGLLayer? {
        guard mpvEmbeddingActive else { return nil }
        return mpvHostView.renderLayer
    }

    var mpvHostViewIfEmbedded: MpvRenderHostView? {
        guard mpvEmbeddingActive else { return nil }
        return mpvHostView
    }

    var mpvEmbeddingWindowID: Int {
        guard mpvEmbeddingActive else { return 0 }
        return 1
    }

    func setMpvEmbeddingActive(_ active: Bool) {
        mpvEmbeddingActive = active
        lastReportedMpvBounds = .null
        if active {
            avPlayerLayer.player = nil
            avPlayerLayer.isHidden = true
            mpvHostView.isHidden = false
            mpvHostView.presentCapability = MpvPresentCapability.preferred
            mpvHostView.requestPresentRefresh()
        } else {
            mpvHostView.isHidden = true
            avPlayerLayer.isHidden = false
        }
        applyLetterboxBackground()
        notifyMpvLayoutIfNeeded()
    }

    /// Force mpv to re-bind after fullscreen / display changes (avoids drifted video + subs).
    func forceMpvLayoutResync() {
        lastReportedMpvBounds = .null
        notifyMpvLayoutIfNeeded()
        if mpvEmbeddingActive {
            mpvHostView.requestPresentRefresh()
        }
    }

    private func notifyMpvLayoutIfNeeded() {
        guard mpvEmbeddingActive else { return }
        let bounds = self.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        if !lastReportedMpvBounds.isNull,
           abs(lastReportedMpvBounds.minX - bounds.minX) < 0.5,
           abs(lastReportedMpvBounds.minY - bounds.minY) < 0.5,
           abs(lastReportedMpvBounds.width - bounds.width) < 0.5,
           abs(lastReportedMpvBounds.height - bounds.height) < 0.5 {
            return
        }
        lastReportedMpvBounds = bounds
        onMpvLayoutChanged?()
        mpvHostView.requestPresentRefresh()
    }

    var player: AVPlayer? {
        get { mpvEmbeddingActive ? nil : avPlayerLayer.player }
        set {
            guard !mpvEmbeddingActive else { return }
            avPlayerLayer.player = newValue
        }
    }

    var videoGravity: AVLayerVideoGravity {
        get { avPlayerLayer.videoGravity }
        set { avPlayerLayer.videoGravity = newValue }
    }

    private func applyLetterboxBackground() {
        avPlayerLayer.backgroundColor = NSColor.black.cgColor
        layer?.backgroundColor = NSColor.black.cgColor
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

