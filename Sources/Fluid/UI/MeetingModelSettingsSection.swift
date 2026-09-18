import AppKit
import SwiftUI

struct MeetingModelSettingsSection: View {
    @Environment(\.theme) private var theme
    @State private var installed: MeetingNemotronModelArtifact?
    @State private var isBusy = true
    @State private var message: String?

    var body: some View {
        FluidManagementGroup(title: "Speaker separation model") {
            VStack(alignment: .leading, spacing: self.theme.metrics.spacing.md) {
                HStack(spacing: self.theme.metrics.spacing.lg) {
                    VStack(alignment: .leading, spacing: self.theme.metrics.spacing.xs) {
                        if self.isBusy {
                            HStack { ProgressView().controlSize(.small); Text("Validating model…") }
                        } else if let installed {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(self.theme.palette.success)
                            Text("Nemotron FP16 · \(ByteCountFormatter.string(fromByteCount: installed.totalByteCount, countStyle: .file))")
                                .font(self.theme.typography.caption)
                                .foregroundStyle(self.theme.palette.secondaryText)
                        } else {
                            Text("Not installed").font(self.theme.typography.bodyStrong)
                        }
                    }
                    Spacer(minLength: self.theme.metrics.spacing.md)
                    Button(self.installed == nil ? "Load model…" : "Replace model…", action: self.choosePackage)
                        .fluidGlassAction()
                        .disabled(self.isBusy || !CPUArchitecture.isAppleSilicon)
                }
                Text(CPUArchitecture.isAppleSilicon
                    ? "Beta: choose the supplied .mlpackage. A copy is saved in FluidVoice and stays ready after restarting. No recording starts."
                    : "Speaker separation requires an Apple silicon Mac.")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
                if let message {
                    Text(message).font(self.theme.typography.caption).foregroundStyle(self.theme.palette.warning)
                }
            }
        }
        .task {
            let result = await Task.detached(priority: .utility) {
                try? MeetingModelInstaller.validate(MeetingNemotronModelLocator().resolvedPackageURL())
            }.value
            self.installed = result
            self.isBusy = false
        }
    }

    private func choosePackage() {
        guard MeetingNemotronModelLocator().resolvedPackageURL().standardizedFileURL
            == MeetingNemotronModelLocator.defaultPackageURL().standardizedFileURL
        else {
            self.message = "A development model path is active. Remove that override and restart FluidVoice before importing."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Load speaker separation model"
        panel.message = "Choose nemotron_diar_fp16.mlpackage from the beta model download."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        // CoreML package types are not registered on every beta tester's Mac.
        // Let the installer validate the selection instead of greying out valid packages.
        panel.begin { response in
            guard response == .OK, let source = panel.url else { return }
            self.isBusy = true
            self.message = nil
            Task {
                do {
                    self.installed = try await Task.detached(priority: .utility) {
                        try MeetingModelInstaller.install(from: source)
                    }.value
                } catch {
                    self.message = error.localizedDescription
                }
                self.isBusy = false
            }
        }
    }
}
