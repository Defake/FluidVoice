import AppKit

/// One immutable decision for a normal dictation, made before awaiting ASR finalization.
struct DictationStopSnapshot {
    let target: TypingService.RecordingTargetContext?
    let appInfo: (name: String, bundleId: String, windowTitle: String)
    let route: DictationProviderRoute
    let usesAI: Bool
    let systemPrompt: String
    let hasCustomPrompt: Bool
    let precedingText: String

    var focusTarget: TypingService.CapturedFocusTarget? {
        guard let target, let element = target.element else { return nil }
        return .init(pid: target.pid, window: target.window, element: element)
    }

    static func selectTarget(
        current: TypingService.RecordingTargetContext?,
        original: TypingService.RecordingTargetContext?,
        returnToStartingField: Bool,
        ownOverlayFocused: Bool
    ) -> TypingService.RecordingTargetContext? {
        returnToStartingField || ownOverlayFocused ? original : current
    }

    @MainActor
    static func capture(
        target: TypingService.RecordingTargetContext?,
        appInfo: (name: String, bundleId: String, windowTitle: String),
        slot: SettingsStore.DictationShortcutSlot,
        precedingText: String
    ) -> Self {
        let settings = SettingsStore.shared
        let customPrompt = settings.resolvedDictationPromptProfile(for: slot, appBundleID: appInfo.bundleId)
            .flatMap { settings.shortcutOverrideSystemPrompt(for: $0) }
        return Self(
            target: target,
            appInfo: appInfo,
            route: DictationProviderRoute.resolve(settings: settings, dictationSlot: slot, appBundleID: appInfo.bundleId),
            usesAI: target != nil && DictationAIPostProcessingGate.isConfigured(for: slot, appBundleID: appInfo.bundleId),
            systemPrompt: customPrompt ?? settings.effectiveDictationSystemPrompt(for: slot, appBundleID: appInfo.bundleId),
            hasCustomPrompt: customPrompt != nil,
            precedingText: precedingText
        )
    }

    @MainActor
    func prepareDelivery(_ text: String, keepBackup: Bool) async -> Bool {
        guard let target else { return false }
        return await PasteDeliveryCoordinator.shared.prepareForDelivery(text, preserveTranscriptOnClipboard: keepBackup) {
            await TypingService.prepareTargetForDelivery(target).isReady
        }
    }
}
