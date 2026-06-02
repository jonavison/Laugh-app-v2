import AppKit
import AVKit
import AVFoundation
import CoreMedia

protocol PlayerViewControllerDelegate: AnyObject {
    func playerViewController(_ controller: PlayerViewController, didLoadMediaWithAspectRatio ratio: CGFloat)
    func playerViewControllerDidRequestOpenVideo(_ controller: PlayerViewController)
    func playerViewControllerDidRequestOpenSettings(_ controller: PlayerViewController)
}

final class PlayerViewController: NSViewController, MediaLibraryDelegate {
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
    private let topControlsStack = NSStackView()
    private let bottomControlsStack = NSStackView()
    private var playbackBarWidthConstraint: NSLayoutConstraint?
    private var imageBarWidthConstraint: NSLayoutConstraint?
    private let previousButton = NSButton(title: "Previous", target: nil, action: nil)
    private let playPauseButton = NSButton(title: "Play", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let queueButton = NSButton(title: "Queue", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Settings", target: nil, action: nil)
    private let libraryButton = NSButton(title: "Library", target: nil, action: nil)
    private let mediaLibraryController = MediaLibraryController()
    private lazy var librarySidebar = LibrarySidebarView(controller: mediaLibraryController)
    private lazy var libraryBrowse = LibraryBrowseView(controller: mediaLibraryController)
    private let playbackMiniPreview = PlaybackMiniPreviewView()
    private let rightSettingsSheet = NSVisualEffectView()
    private let videoSettingsTabsControl = NSSegmentedControl(labels: ["VIDEO", "AUDIO", "SUBTITLES"], trackingMode: .selectOne, target: nil, action: nil)
    private let imageSettingsTabsControl = NSSegmentedControl(labels: ["IMAGE", "FIT"], trackingMode: .selectOne, target: nil, action: nil)
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
    private let codecLabel = NSTextField(labelWithString: "Codec: --")
    private let sizeLabel = NSTextField(labelWithString: "Size: --")
    private var queue: [URL] = []
    private var playbackHistory: [URL] = []
    private var failedToPlayObserver: NSObjectProtocol?
    private weak var observedItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private let renderMonitor = PlaybackRenderMonitor()
    private let compatibilityBanner = CompatibilityBannerView()
    private var currentMediaURL: URL?
    private var lastVideoCodecFourCC: String?
    private var lastVideoSize: CGSize?
    private var lastImageSize: CGSize?
    private var lastAudioSummary: String = "Unknown"
    private var isSeekingFromUI = false
    private var currentControlTier: ControlDensityTier = .regular
    private var outsideClickMonitor: Any?
    private var settingsContentBottomConstraint: NSLayoutConstraint?
    private var securityScopedMediaURL: URL?
    private var videoLoadGeneration = 0
    private let settingsPanelWidth: CGFloat = 320
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

    override func viewDidLoad() {
        super.viewDidLoad()

        playerSurfaceView.player = player
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

        librarySidebar.isHidden = true
        librarySidebar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(librarySidebar)

        libraryBrowse.isHidden = true
        libraryBrowse.translatesAutoresizingMaskIntoConstraints = false
        libraryBrowse.onOpenMediaPanel = { [weak self] in
            guard let self else { return }
            self.delegate?.playerViewControllerDidRequestOpenVideo(self)
        }
        view.addSubview(libraryBrowse)

        playbackMiniPreview.isHidden = true
        playbackMiniPreview.translatesAutoresizingMaskIntoConstraints = false
        playbackMiniPreview.onExpand = { [weak self] in
            self?.collapsePlaybackLibraryOverlay()
        }
        view.addSubview(playbackMiniPreview)

        mediaLibraryController.delegate = self
        mediaLibraryController.onChange = { [weak self] in
            self?.librarySidebar.refresh()
            self?.libraryBrowse.refresh()
            self?.syncPlaybackLibraryBrowseExpansion()
        }

        styleRightSettingsPanel()
        rightSettingsSheet.isHidden = true
        rightSettingsSheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightSettingsSheet)

        videoSettingsTabsControl.selectedSegment = 0
        videoSettingsTabsControl.target = self
        videoSettingsTabsControl.action = #selector(settingsTabChanged)
        videoSettingsTabsControl.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(videoSettingsTabsControl)

        imageSettingsTabsControl.selectedSegment = 0
        imageSettingsTabsControl.target = self
        imageSettingsTabsControl.action = #selector(settingsTabChanged)
        imageSettingsTabsControl.isHidden = true
        imageSettingsTabsControl.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(imageSettingsTabsControl)

        settingsContentContainer.translatesAutoresizingMaskIntoConstraints = false
        rightSettingsSheet.addSubview(settingsContentContainer)

        configureSettingsTabViews()

        controlsStack.orientation = .vertical
        controlsStack.alignment = .centerX
        controlsStack.distribution = .fill
        controlsStack.spacing = 10
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(controlsStack)

        transportClusterStack.orientation = .horizontal
        transportClusterStack.alignment = .centerY
        transportClusterStack.distribution = .fill
        transportClusterStack.spacing = 20

        topControlsStack.orientation = .horizontal
        topControlsStack.alignment = .centerY
        topControlsStack.distribution = .equalCentering
        topControlsStack.spacing = 12

        bottomControlsStack.orientation = .horizontal
        bottomControlsStack.alignment = .centerY
        bottomControlsStack.distribution = .fill
        bottomControlsStack.spacing = 10

        configureControls()

        let initialBarWidth = MusicStylePlaybackBar.preferredBarWidth(forContentWidthPoints: 960)
        playbackBarWidthConstraint = controlsContainer.widthAnchor.constraint(equalToConstant: initialBarWidth)
        imageBarWidthConstraint = imageControlsContainer.widthAnchor.constraint(equalToConstant: min(420, initialBarWidth))

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

            librarySidebar.topAnchor.constraint(equalTo: view.topAnchor),
            librarySidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            librarySidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            librarySidebar.widthAnchor.constraint(equalToConstant: LibrarySidebarView.width),

            libraryBrowse.topAnchor.constraint(equalTo: view.topAnchor),
            libraryBrowse.leadingAnchor.constraint(equalTo: librarySidebar.trailingAnchor),
            libraryBrowse.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            libraryBrowse.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            playbackMiniPreview.widthAnchor.constraint(equalToConstant: 264),
            playbackMiniPreview.heightAnchor.constraint(equalToConstant: 148),
            playbackMiniPreview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            playbackMiniPreview.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),

            rightSettingsSheet.topAnchor.constraint(equalTo: view.topAnchor),
            rightSettingsSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightSettingsSheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rightSettingsSheet.widthAnchor.constraint(equalToConstant: settingsPanelWidth),

            videoSettingsTabsControl.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor, constant: settingsPanelInnerInset),
            videoSettingsTabsControl.centerXAnchor.constraint(equalTo: rightSettingsSheet.centerXAnchor),

            imageSettingsTabsControl.topAnchor.constraint(equalTo: rightSettingsSheet.topAnchor, constant: settingsPanelInnerInset),
            imageSettingsTabsControl.centerXAnchor.constraint(equalTo: rightSettingsSheet.centerXAnchor),

            settingsContentContainer.topAnchor.constraint(equalTo: videoSettingsTabsControl.bottomAnchor, constant: settingsPanelInnerInset),
            settingsContentContainer.leadingAnchor.constraint(equalTo: rightSettingsSheet.leadingAnchor, constant: settingsPanelInnerInset),
            settingsContentContainer.trailingAnchor.constraint(equalTo: rightSettingsSheet.trailingAnchor, constant: -settingsPanelInnerInset)
        ])

        settingsContentBottomConstraint = settingsContentContainer.bottomAnchor.constraint(
            equalTo: rightSettingsSheet.bottomAnchor,
            constant: -settingsPanelInnerInset
        )
        settingsContentBottomConstraint?.isActive = true

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

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds >= 0 {
                let rounded = String(format: "%.2f", seconds)
                print("[DEBUG-playback] t=\(rounded)s rate=\(self.player.rate)")
                self.updateTimelineUI()
            }
        }

        updateSettingsContentBottomInset()
        showEmptySurface()
    }

    func loadVideo(url: URL, replaceCurrent: Bool = true) {
        print("[DEBUG-playback] Loading video: \(url.path)")
        videoLoadGeneration += 1
        let generation = videoLoadGeneration

        hideCompatibilityFailure()
        renderMonitor.reset()
        currentMediaURL = url
        lastVideoCodecFourCC = nil
        lastVideoSize = nil
        lastImageSize = nil
        lastAudioSummary = "Loading..."
        renderMonitor.videoCodecFourCC = nil

        if replaceCurrent, let currentMediaURL {
            playbackHistory.append(currentMediaURL)
        }

        if let observedItem {
            observedItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            self.observedItem = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)

        Task {
            let result = await VideoAssetLoader.resolvePlayableAsset(for: url)
            await MainActor.run {
                guard generation == self.videoLoadGeneration else { return }
                switch result {
                case .success(let asset):
                    self.attachResolvedVideo(asset: asset, url: url)
                case .failure(let failure):
                    print("[DEBUG-playback] open failed: \(failure.debugDetails)")
                    self.showCompatibilityFailure(failure.userMessage)
                }
            }
        }
    }

    private func attachResolvedVideo(asset: AVURLAsset, url: URL) {
        beginSecurityScopedAccess(for: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        item.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new, .initial], context: nil)
        observedItem = item

        activeMediaKind = .video
        showVideoChrome(hideOpenHint: false)
        RecentlyViewedStore.shared.record(url: url, kind: .video)
        updateAspectRatio(asset: asset)
        player.play()
        updatePlayPauseButtonIcon()
        updateTimelineUI()
    }

    func loadImage(url: URL) {
        guard let loaded = ImageDisplayLoader.loadDisplayImage(at: url) else {
            showUnsupportedFileMessage("Could not open this image file.")
            return
        }
        if let currentMediaURL {
            playbackHistory.append(currentMediaURL)
        }
        currentMediaURL = url
        if let observedItem {
            observedItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            self.observedItem = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)

        lastImageSize = loaded.pixelSize
        lastVideoSize = nil
        imageSurfaceView.setImage(loaded.image, naturalSize: loaded.pixelSize)
        activeMediaKind = .image
        RecentlyViewedStore.shared.record(url: url, kind: .image)
        showImageChrome()

        let ratio = loaded.pixelSize.width / max(loaded.pixelSize.height, 1)
        delegate?.playerViewController(self, didLoadMediaWithAspectRatio: ratio)
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
        if let observer = failedToPlayObserver {
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
                print("[DEBUG-playback] Ready to play")
                self.showVideoChrome(hideOpenHint: true)
                self.player.seek(to: .zero)
                self.player.play()
                self.updatePlayPauseButtonIcon()
                self.updateTimelineUI()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if self.player.rate == 0 {
                        print("[DEBUG-playback] rate still 0, retrying play()")
                        self.player.play()
                        self.updatePlayPauseButtonIcon()
                    }
                }
                self.renderMonitor.videoCodecFourCC = self.lastVideoCodecFourCC
                self.renderMonitor.beginMonitoring(player: self.player, item: item) { [weak self] message in
                    self?.showCompatibilityFailure(message)
                }
            }
        case .failed:
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
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentMediaURL = nil
        imageSurfaceView.clearImage()
        lastImageSize = nil
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
        rightSettingsSheet.material = .underWindowBackground
        rightSettingsSheet.blendingMode = .behindWindow
        rightSettingsSheet.state = .active
        rightSettingsSheet.wantsLayer = true
        rightSettingsSheet.layer?.cornerRadius = 0
        rightSettingsSheet.layer?.masksToBounds = false
    }

    private func raisePlaybackChromeToFront() {
        view.addSubview(controlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
        view.addSubview(imageControlsContainer, positioned: .above, relativeTo: rightSettingsSheet)
        view.addSubview(queueDropZone, positioned: .above, relativeTo: rightSettingsSheet)
        if !openButton.isHidden {
            view.addSubview(openButton, positioned: .above, relativeTo: libraryBrowse)
            view.addSubview(hintLabel, positioned: .above, relativeTo: libraryBrowse)
        }
        view.addSubview(librarySidebar, positioned: .above, relativeTo: playerSurfaceView)
        view.addSubview(libraryBrowse, positioned: .above, relativeTo: playerSurfaceView)
        view.addSubview(playbackMiniPreview, positioned: .above, relativeTo: libraryBrowse)
    }

    private func updateSettingsContentBottomInset() {
        let clearance = activeMediaKind == .empty ? settingsPanelInnerInset : settingsContentBottomClearance
        settingsContentBottomConstraint?.constant = -clearance
    }

    private func applyContextualSettingsTabs() {
        let isVideo = activeMediaKind == .video
        let isImage = activeMediaKind == .image
        videoSettingsTabsControl.isHidden = !isVideo
        imageSettingsTabsControl.isHidden = !isImage
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
                        self.codecLabel.stringValue = "Codec: \(fourCC)"
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
                    self.sizeLabel.stringValue = "Size: \(Int(width))x\(Int(height))"
                    self.delegate?.playerViewController(self, didLoadMediaWithAspectRatio: width / height)
                }
            } catch {
                // Ignore bad metadata and keep current layout behavior.
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePlaybackBarWidth()
        applyResponsiveControlsLayout()
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
        styleIconButton(previousButton, symbol: "backward.fill", label: "Previous")
        styleIconButton(nextButton, symbol: "forward.fill", label: "Next")
        styleIconButton(queueButton, symbol: "list.bullet", label: "Queue")
        styleIconButton(settingsButton, symbol: "gearshape", label: "Settings")
        styleIconButton(libraryButton, symbol: "folder", label: "Library")
        queueButton.isHidden = true

        playPauseButton.bezelStyle = .accessoryBarAction
        playPauseButton.isBordered = false
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        playPauseButton.setButtonType(.momentaryPushIn)
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
        seekSlider.controlSize = .mini

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged)
        volumeSlider.controlSize = .mini
        player.volume = 1

        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        currentTimeLabel.textColor = .secondaryLabelColor
        currentTimeLabel.alignment = .right
        totalTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        totalTimeLabel.textColor = .secondaryLabelColor
        totalTimeLabel.alignment = .left
        currentTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        seekSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        codecLabel.font = .systemFont(ofSize: 11)
        codecLabel.textColor = .secondaryLabelColor
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor
    }

    private func configureSettingsTabViews() {
        [videoTabView, audioTabView, subtitlesTabView].forEach { stack in
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.distribution = .fill
            stack.spacing = 10
            stack.translatesAutoresizingMaskIntoConstraints = false
        }

        let videoTitle = NSTextField(labelWithString: "Video Settings")
        videoTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let videoHint = NSTextField(labelWithString: "Aspect ratio and rendering options will appear here.")
        videoHint.textColor = .secondaryLabelColor
        videoHint.maximumNumberOfLines = 0
        videoTabView.addArrangedSubview(videoTitle)
        videoTabView.addArrangedSubview(videoHint)

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
            let index = videoSettingsTabsControl.selectedSegment
            videoTabView.isHidden = index != 0
            audioTabView.isHidden = index != 1
            subtitlesTabView.isHidden = index != 2
        case .image:
            let index = imageSettingsTabsControl.selectedSegment
            imageTabView.isHidden = index != 0
            imageFitTabView.isHidden = index != 1
        case .empty:
            break
        }
    }

    private func showSettingsSheet() {
        guard activeMediaKind != .empty else { return }
        guard playbackLibraryOverlay == .closed else { return }
        guard rightSettingsSheet.isHidden else { return }
        rightSettingsSheet.isHidden = false
        raisePlaybackChromeToFront()
        installOutsideClickMonitor()
    }

    private func hideSettingsSheet() {
        guard !rightSettingsSheet.isHidden else { return }
        rightSettingsSheet.isHidden = true
        removeOutsideClickMonitorIfNoSheetsVisible()
    }

    private func showFullMediaLibrary() {
        playbackLibraryOverlay = .closed
        librarySidebar.isHidden = false
        libraryBrowse.isHidden = false
        playbackMiniPreview.isHidden = true
        librarySidebar.reloadRoots()
        libraryBrowse.reloadContent()
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
        transportClusterStack.addArrangedSubview(previousButton)
        transportClusterStack.addArrangedSubview(playPauseButton)
        transportClusterStack.addArrangedSubview(nextButton)
        topControlsStack.addArrangedSubview(libraryButton)
        topControlsStack.addArrangedSubview(transportClusterStack)

        queueButton.isHidden = queue.isEmpty
        if !queue.isEmpty {
            topControlsStack.addArrangedSubview(queueButton)
        }
        topControlsStack.addArrangedSubview(settingsButton)

        bottomControlsStack.addArrangedSubview(currentTimeLabel)
        bottomControlsStack.addArrangedSubview(seekSlider)
        bottomControlsStack.addArrangedSubview(totalTimeLabel)
        bottomControlsStack.addArrangedSubview(volumeSlider)

        currentTimeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        totalTimeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        volumeSlider.widthAnchor.constraint(equalToConstant: tier == .compact ? 72 : 88).isActive = true
        bottomControlsStack.widthAnchor.constraint(equalTo: controlsStack.widthAnchor).isActive = true
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

    @objc private func togglePlayPause() {
        let start = CFAbsoluteTimeGetCurrent()
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
        updatePlayPauseButtonIcon()
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[DEBUG-ui] playPause=%.2fms", elapsedMs))
    }

    @objc private func seekSliderChanged() {
        let start = CFAbsoluteTimeGetCurrent()
        isSeekingFromUI = true
        let target = CMTime(seconds: seekSlider.doubleValue, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            self.isSeekingFromUI = false
            self.updateTimelineUI()
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print(String(format: "[DEBUG-ui] seek=%.2fms", elapsedMs))
        }
    }

    @objc private func volumeSliderChanged() {
        let start = CFAbsoluteTimeGetCurrent()
        player.volume = Float(volumeSlider.doubleValue)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "[DEBUG-ui] volume=%.2fms", elapsedMs))
    }

    @objc private func previousPressed() {
        guard let previous = playbackHistory.popLast() else { return }
        switch MediaKindDetector.kind(for: previous) {
        case .video:
            loadVideo(url: previous, replaceCurrent: false)
        case .image:
            loadImage(url: previous)
        case .unsupported:
            break
        }
    }

    @objc private func nextPressed() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        loadVideo(url: next, replaceCurrent: true)
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

    @objc private func settingsTabChanged() {
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
