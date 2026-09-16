import Foundation

// MARK: - Local diagnostics trigger

extension GlobalHotkeyManager {
    /// Lets a local script run the exact hotkey toggle path for latency
    /// reproduction. Inert unless the defaults flag is set on this machine.
    func registerDebugToggleTriggerIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "FluidDebugRemoteToggleEnabled") else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.FluidApp.debug.toggleRecording"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                DebugLogger.shared.info("Debug toggle trigger received", source: "GlobalHotkeyManager")
                self?.toggleRecording()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.FluidApp.debug.pasteLastTranscript"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                DebugLogger.shared.info("Debug paste-last trigger received", source: "GlobalHotkeyManager")
                self?.triggerPasteLastTranscription(isAutorepeat: false)
            }
        }
        DebugLogger.shared.info("Debug toggle trigger enabled", source: "GlobalHotkeyManager")
    }
}
