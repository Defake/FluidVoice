import SwiftUI

// MARK: - Bottom Waveform View (reads from NotchContentState)

struct BottomWaveformView: View {
    let color: Color
    let layout: BottomOverlayView.LayoutConstants
    let visibleBarCount: Int?

    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var audioLevel = OverlayAudioLevelState.shared
    private var isWaitingForMicrophone: Bool {
        !self.audioLevel.isLive && !self.contentState.isProcessing && !self.isReleaseAnimationActive
    }

    // Initialize with max possible bar count (11 for large) to prevent index-out-of-range before onAppear
    @State private var barHeights: [CGFloat] = Array(repeating: 6, count: 11)
    @State private var noiseThreshold: CGFloat = .init(SettingsStore.shared.visualizerNoiseThreshold)

    private var barCount: Int {
        self.visibleBarCount ?? self.layout.barCount
    }

    private var barWidth: CGFloat {
        self.layout.barWidth
    }

    private var barSpacing: CGFloat {
        self.layout.barSpacing
    }

    private var minHeight: CGFloat {
        self.layout.minBarHeight
    }

    private var maxHeight: CGFloat {
        self.layout.maxBarHeight
    }

    private var isPillStyle: Bool {
        !self.layout.showsModeLabel
    }

    private var isProcessingVisualActive: Bool {
        self.contentState.isProcessing || self.isReleaseAnimationActive
    }

    private var currentGlowIntensity: CGFloat {
        if self.isPillStyle {
            return 0.0
        }
        return self.isProcessingVisualActive ? 0.0 : 0.5
    }

    private var currentGlowRadius: CGFloat {
        if self.isPillStyle {
            return 0.0
        }
        return self.isProcessingVisualActive ? 0.0 : 4
    }

    private var barFillColor: Color {
        if self.isPillStyle {
            return Color.white.opacity(self.isProcessingVisualActive ? 0.32 : 0.88)
        }
        return self.color.opacity(self.isProcessingVisualActive ? 0.16 : 1.0)
    }

    private var isReleaseAnimationActive: Bool {
        self.contentState.isBottomOverlayReleaseTransitioning || self.contentState.isBottomOverlayDismissing
    }

    /// Safe accessor for bar heights to prevent index-out-of-range crashes
    private func safeBarHeight(at index: Int) -> CGFloat {
        guard index >= 0 && index < self.barHeights.count else {
            return self.minHeight
        }
        return self.barHeights[index]
    }

    var body: some View {
        ZStack {
            self.barsView
                .foregroundStyle(self.barFillColor)

            if self.isProcessingVisualActive {
                CompositorShimmerSweep(duration: 1.05, peakOpacity: 0.9)
                    .mask {
                        self.barsView
                    }
                    .shadow(color: .white.opacity(0.28), radius: 2.5, x: 0, y: 0)
            }
        }
        .opacity(self.isWaitingForMicrophone ? 0.45 : 1)
        .animation(.easeOut(duration: 0.22), value: self.isWaitingForMicrophone)
        .onChange(of: self.audioLevel.level) { _, level in
            guard !self.isReleaseAnimationActive else { return }
            if !self.contentState.isProcessing {
                self.updateBars(level: level)
            }
        }
        .onChange(of: self.contentState.isProcessing) { _, processing in
            guard !self.isReleaseAnimationActive else { return }
            if processing {
                self.setFlatProcessingBars()
            } else {
                // Resume from silence; next audio tick will animate up.
                self.updateBars(level: 0)
            }
        }
        .onChange(of: self.layout.barCount) { _, newCount in
            self.barHeights = Array(repeating: self.minHeight, count: newCount)
        }
        .onAppear {
            // Ensure bar count matches current layout
            if self.barHeights.count != self.barCount {
                self.barHeights = Array(repeating: self.minHeight, count: self.barCount)
            }
            if self.isReleaseAnimationActive {
                self.barHeights = Array(repeating: self.minHeight, count: self.barCount)
            } else if self.contentState.isProcessing {
                self.setFlatProcessingBars()
            } else {
                self.updateBars(level: 0)
            }
        }
        .onDisappear {
            // No timers to clean up.
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // Update threshold when user changes sensitivity setting
            let newThreshold = CGFloat(SettingsStore.shared.visualizerNoiseThreshold)
            if newThreshold != self.noiseThreshold {
                self.noiseThreshold = newThreshold
            }
        }
    }

    private var barsView: some View {
        HStack(spacing: self.barSpacing) {
            ForEach(0..<self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: self.barWidth / 2)
                    .frame(width: self.barWidth, height: self.displayHeight(at: index))
                    .shadow(
                        color: self.color.opacity(self.isReleaseAnimationActive ? 0 : self.currentGlowIntensity),
                        radius: self.isReleaseAnimationActive ? 0 : self.currentGlowRadius,
                        x: 0,
                        y: 0
                    )
            }
        }
    }

    private func displayHeight(at index: Int) -> CGFloat {
        if self.isReleaseAnimationActive || self.contentState.isProcessing {
            return self.minHeight
        }
        return self.safeBarHeight(at: index)
    }

    private func visualizerPeakHeight(at index: Int) -> CGFloat {
        let centerDistance = abs(CGFloat(index) - CGFloat(self.barCount - 1) / 2)
        let maxDistance = max(CGFloat(self.barCount - 1) / 2, 1)
        let normalizedDistance = min(centerDistance / maxDistance, 1)
        let factor = max(0.18, 0.96 - normalizedDistance * 0.78)
        return self.minHeight + (self.maxHeight - self.minHeight) * factor
    }

    private func setFlatProcessingBars() {
        // Ensure array is properly sized before modifying
        guard self.barHeights.count >= self.barCount else { return }

        // During AI processing we want the visualizer to settle to silence (flat).
        withAnimation(.easeOut(duration: 0.18)) {
            for i in 0..<self.barCount {
                self.barHeights[i] = self.minHeight
            }
        }
    }

    private func updateBars(level: CGFloat) {
        // Ensure array is properly sized before modifying
        guard self.barHeights.count >= self.barCount else { return }

        let normalizedLevel = min(max(level, 0), 1)
        let denominator = max(1.0 - self.noiseThreshold, 0.001)
        let adjustedLevel = max(min((normalizedLevel - self.noiseThreshold) / denominator, 1.0), 0.0)
        // Lower exponent => normal speech pushes the bars higher (taller "waves" while talking).
        let amplifiedLevel = pow(adjustedLevel, 0.55)

        withAnimation(.easeOut(duration: 0.08)) {
            for i in 0..<self.barCount {
                let peakHeight = self.visualizerPeakHeight(at: i)
                let variation = 0.92 + 0.08 * cos(CGFloat(i) * 1.45)
                let nextHeight = self.minHeight + (peakHeight - self.minHeight) * amplifiedLevel * variation
                self.barHeights[i] = min(self.maxHeight, max(self.minHeight, nextHeight))
            }
        }
    }
}
