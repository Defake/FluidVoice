import SwiftUI

/// Mirrors the iOS practice composition using the Mac onboarding palette.
struct OnboardingPolishPracticeView: View {
    let practice: OnboardingPolishPractice
    let isRunning: Bool
    let isProcessing: Bool
    let isRecordingShortcut: Bool
    let shortcutDisplay: String
    let shortcutRecordingMessage: String?
    let onToggleShortcut: () -> Void

    private var blue: Color { FluidOnboardingLandingColors.blue }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ForEach(0..<OnboardingPolishPractice.examples.count, id: \.self) { index in
                    let done = self.practice.results[index] != nil
                    ZStack {
                        Circle().fill(done || index == self.practice.index ? self.blue : .white.opacity(0.1))
                        if done {
                            Image(systemName: "checkmark").font(.fluidSystem(size: 11, weight: .bold))
                        } else {
                            Text("\(index + 1)").font(.fluidSystem(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white.opacity(done || index == self.practice.index ? 1 : 0.45))
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Step \(index + 1), \(done ? "complete" : (index == self.practice.index ? "current" : "upcoming"))")
                }
            }
            self.exampleText("Try saying this", text: self.practice.example.spoken, accent: false)
            self.exampleText("It should come out as", text: self.practice.example.expected, accent: true)
            Text(self.practice.result ?? "Your polished words appear here")
                .font(.fluidSystem(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(self.practice.result == nil ? 0.35 : 0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 105)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15)))
                .accessibilityLabel("Your dictation result")
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Text(self.isRecordingShortcut ? "Press your new shortcut…" : self.shortcutDisplay)
                        .font(.fluidSystem(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Button(self.isRecordingShortcut ? "Cancel" : "Change shortcut", action: self.onToggleShortcut)
                        .buttonStyle(.plain)
                        .font(.fluidSystem(size: 12, weight: .semibold))
                        .foregroundStyle(self.blue)
                        .disabled(self.isRunning || self.isProcessing)
                }
                Text(self.status)
                    .font(.fluidSystem(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
                if let message = self.shortcutRecordingMessage, self.isRecordingShortcut {
                    Text(message).font(.fluidSystem(size: 12)).foregroundStyle(.orange)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 500)
    }

    private var status: String {
        if self.isRunning { return "Press your shortcut again when you’re done." }
        if self.isProcessing { return "Polishing your words…" }
        return self.practice.result == nil ? "Choose Smart mode below, then press your shortcut to try this one." : "Press your shortcut to try it again."
    }

    private func exampleText(_ label: String, text: String, accent: Bool) -> some View {
        VStack(spacing: 8) {
            Text(label.uppercased())
                .font(.fluidSystem(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(accent ? self.blue : .white.opacity(0.4))
            Text(text)
                .font(.fluidSystem(size: accent ? 17 : 18, weight: accent ? .regular : .semibold))
                .foregroundStyle(.white.opacity(accent ? 0.6 : 0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
