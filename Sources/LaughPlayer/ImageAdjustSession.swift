import Foundation

/// Source of truth for the current ImageMedia develop state (ADR 0004).
/// Sliders, Presets, and the surface are adapters; they do not own parameter values.
final class ImageAdjustSession {
    private var parameters: ImageAdjustParameters = .identity
    private var bypassedSections: Set<ImageAdjustSection> = []
    private var showingBefore = false
    private var settleWorkItem: DispatchWorkItem?

    /// Fired for surface renders (preview while dragging; full after settle / commits).
    var onChange: ((_ quality: ImageAdjustRenderQuality) -> Void)?
    /// Fired when section chrome or dirty state should refresh.
    var onChromeChange: (() -> Void)?
    /// Fired when parameters were committed outside continuous slider edits (presets, reset, bypass).
    /// Slider adapters should pull widget values from `rawParameters`.
    var onParametersCommitted: (() -> Void)?

    /// Raw parameters including values in bypassed sections.
    var rawParameters: ImageAdjustParameters { parameters }

    /// Parameters with bypassed sections treated as identity (export / After).
    var effectiveParameters: ImageAdjustParameters {
        parameters.bypassing(bypassedSections)
    }

    /// What the surface should show right now (identity while Before is held).
    var presentationParameters: ImageAdjustParameters {
        showingBefore ? .identity : effectiveParameters
    }

    var isShowingBefore: Bool { showingBefore }

    var isDirty: Bool { !effectiveParameters.isIdentity }

    func isSectionEdited(_ section: ImageAdjustSection) -> Bool {
        parameters.isEdited(section)
    }

    func isSectionBypassed(_ section: ImageAdjustSection) -> Bool {
        bypassedSections.contains(section)
    }

    /// Continuous edit from sliders: preview now, full after settle.
    func replaceParameters(_ next: ImageAdjustParameters) {
        parameters = next
        notifyChrome()
        emitChange(quality: .preview)
        scheduleFullQualitySettle()
    }

    /// Commit a full parameter set (presets, Reset All, programmatic apply).
    func apply(
        _ next: ImageAdjustParameters,
        quality: ImageAdjustRenderQuality = .full,
        clearBypasses: Bool = true
    ) {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        if clearBypasses {
            bypassedSections.removeAll()
        }
        parameters = next
        notifyChrome()
        notifyParametersCommitted()
        emitChange(quality: quality)
    }

    func resetAll() {
        apply(.identity, quality: .full, clearBypasses: true)
    }

    func resetSection(_ section: ImageAdjustSection) {
        bypassedSections.remove(section)
        apply(parameters.resetting(section), quality: .full, clearBypasses: false)
    }

    func toggleSectionBypass(_ section: ImageAdjustSection) {
        guard isSectionEdited(section) else { return }
        if bypassedSections.contains(section) {
            bypassedSections.remove(section)
        } else {
            bypassedSections.insert(section)
        }
        settleWorkItem?.cancel()
        settleWorkItem = nil
        notifyChrome()
        notifyParametersCommitted()
        emitChange(quality: .full)
    }

    /// Before/After: toggles presentation only; does not clear edits.
    func setShowingBefore(_ value: Bool) {
        guard showingBefore != value else { return }
        showingBefore = value
        settleWorkItem?.cancel()
        settleWorkItem = nil
        emitChange(quality: .full)
    }

    func toggleShowingBefore() {
        setShowingBefore(!showingBefore)
    }

    private func notifyChrome() {
        onChromeChange?()
    }

    private func notifyParametersCommitted() {
        onParametersCommitted?()
    }

    private func emitChange(quality: ImageAdjustRenderQuality) {
        onChange?(quality)
    }

    private func scheduleFullQualitySettle() {
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.emitChange(quality: .full)
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }
}
