import SwiftUI

struct DictionaryMatcherExperimentSettings: View {
    @Environment(\.theme) private var theme
    @AppStorage("DictionaryTemporalMatcherEnabled") private var temporal = false
    @AppStorage("DictionaryNegativeLearningEnabled") private var learning = false
    @AppStorage("DictionaryNegativeComparisonEnabled") private var comparison = false
    @State private var clearing = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dictionary matching experiments", systemImage: "waveform.badge.magnifyingglass")
                .font(self.theme.typography.bodyStrong)
            Toggle("Compare the whole pronunciation", isOn: self.$temporal)
            Text("Checks the whole word using three voice recordings. Parakeet only. These experiments keep new voice-training recordings locally; words without saved audio use existing matching until you record them again.")
                .font(self.theme.typography.caption).foregroundStyle(.secondary)
            Toggle("Learn from confirmed wrong matches", isOn: self.$learning)
            Text("After you edit an inserted word, confirm whether you said a different word. Saves only audio features locally. Requires the whole-pronunciation experiment (or legacy edge matching) and an app that supports correction detection.")
                .font(self.theme.typography.caption).foregroundStyle(.secondary)
            Toggle("Use saved wrong-match examples", isOn: self.$comparison)
            Text("Rejects a close match to a confirmed mistake. You can collect examples with this switched off, or disable either comparison at any time.")
                .font(self.theme.typography.caption).foregroundStyle(.secondary)
            Button("Clear wrong-match examples", role: .destructive) {
                self.clearing = true
                Task {
                    defer { clearing = false }
                    do {
                        try await DictionaryNegativeExampleStore.shared.clear()
                        self.message = "Wrong-match examples cleared. Your dictionary and voice recordings are unchanged."
                    } catch { self.message = "Couldn’t clear examples: \(error.localizedDescription)" }
                }
            }
            .fluidGlassAction()
            .disabled(self.clearing)
            if !self.message.isEmpty {
                Text(self.message).font(self.theme.typography.caption).foregroundStyle(.secondary)
            }
            Text("All three experiments are off by default. Turning them off restores the existing matcher. These are experimental comparisons, not guaranteed improvements.")
                .font(self.theme.typography.caption).foregroundStyle(.secondary)
        }
    }
}
