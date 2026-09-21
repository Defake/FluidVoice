import AppKit
@testable import FluidVoice_Debug
import Foundation
import SwiftUI
import XCTest
#if arch(arm64)
import FluidAudio
#endif

@MainActor
final class CustomDictionaryManualEntryTests: XCTestCase {
    func testVoiceTrainingKeepsPronunciationWithoutEverydayTextAliases() async {
        let filtered = await VoiceTrainingAliasFilter.filter(["but", "now", "right now"]) { _ in .checked([]) }
        let entries = CustomDictionaryTrainingMerge.mergedEntries(
            current: [], replacement: "Lyft", triggers: filtered.accepted, savePronunciation: true
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.replacement, "Lyft")
        XCTAssertEqual(entries.first?.triggers, ["lyft"], "Only the canonical spelling anchors the voice profile")
    }

    func testVoiceTrainingFilterPreservesExistingManualRules() async {
        let manual = SettingsStore.CustomDictionaryEntry(triggers: ["now"], replacement: "Lyft")
        let unrelated = SettingsStore.CustomDictionaryEntry(triggers: ["but"], replacement: "ManualChoice")
        let filtered = await VoiceTrainingAliasFilter.filter(["now", "hello"]) { _ in .checked([]) }
        let entries = CustomDictionaryTrainingMerge.mergedEntries(
            current: [manual, unrelated], replacement: "Lyft", triggers: filtered.accepted, savePronunciation: true
        )
        XCTAssertEqual(entries, [manual, unrelated])
        XCTAssertEqual(CustomDictionaryManualEntry.normalizedTriggers(["but", "now", "right now"]), ["but", "now", "right now"])
    }

    func testUnavailableVocabularyCannotCreateTextOnlyTrainingRules() async {
        let filtered = await VoiceTrainingAliasFilter.filter(["now"]) { _ in .unavailable }
        let entries = CustomDictionaryTrainingMerge.mergedEntries(
            current: [], replacement: "Lyft", triggers: filtered.accepted
        )
        XCTAssertTrue(entries.isEmpty)
    }

    func testKeepsWhitespaceOnlyReplacements() {
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement("\n"), "\n")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement(" "), " ")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement("\t"), "\t")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement(""), "")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement("  FluidVoice \n"), "FluidVoice")
    }

    func testRendersWhitespaceReplacementsVisibly() {
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText("\n"), "⏎")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText(" "), "␣")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText("\t"), "⇥")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText(" \n"), "␣⏎")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText("FluidVoice"), "FluidVoice")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText(""), "")
    }

    func testInstantReplacementDoesNotEnterParakeetBoostVocabulary() {
        let replacement = SettingsStore.CustomDictionaryEntry(
            triggers: ["sean"],
            replacement: "Shaun"
        )
        let explicitBoost = ParakeetVocabularyStore.VocabularyConfig.Term(
            text: "FluidVoice",
            weight: 10,
            aliases: ["fluid voice"]
        )

        self.withRestoredDictionary([replacement]) {
            let terms = ParakeetVocabularyStore.normalizedBoostTerms([explicitBoost])

            XCTAssertEqual(terms.map(\.text), ["FluidVoice"])
            XCTAssertEqual(terms.first?.aliases, ["fluid voice"])
            XCTAssertFalse(terms.contains { $0.text.caseInsensitiveCompare("Shaun") == .orderedSame })
            XCTAssertFalse(terms.contains { $0.aliases.contains("sean") })
        }
    }

    func testInstantReplacementStillRequiresExactWholeWordTrigger() {
        let replacement = SettingsStore.CustomDictionaryEntry(
            triggers: ["sean"],
            replacement: "Shaun"
        )

        self.withRestoredDictionary([replacement]) {
            XCTAssertEqual(ASRService.applyCustomDictionary("Did you mean Monday?"), "Did you mean Monday?")
            XCTAssertEqual(ASRService.applyCustomDictionary("Ask sean Monday."), "Ask Shaun Monday.")
        }
    }

    func testWhitespaceReplacementSurvivesTransferAndReplacement() throws {
        let document = DictionaryTransferDocument(
            replacements: [DictionaryTransferReplacement(from: ["new line"], to: "\n")],
            customWords: []
        )

        let data = try DictionaryTransferService.shared.encode(document)
        let decoded = try DictionaryTransferService.shared.decode(data)
        let state = try DictionaryTransferService.importState(
            document: decoded,
            mode: .replace,
            currentReplacements: [],
            currentCustomWords: []
        )

        XCTAssertEqual(state.replacements.first?.replacement, "\n")
        self.withRestoredDictionary(state.replacements) {
            XCTAssertEqual(ASRService.applyCustomDictionary("first new line second"), "first\nsecond")
        }
    }

    func testWhitespaceReplacementsOwnAdjacentHorizontalSeparators() {
        let entries = [
            SettingsStore.CustomDictionaryEntry(triggers: ["new line"], replacement: "\n"),
            SettingsStore.CustomDictionaryEntry(triggers: ["new paragraph"], replacement: "\n\n"),
            SettingsStore.CustomDictionaryEntry(triggers: ["tab over"], replacement: "\t"),
            SettingsStore.CustomDictionaryEntry(triggers: ["little space"], replacement: " "),
        ]

        self.withRestoredDictionary(entries) {
            XCTAssertEqual(ASRService.applyCustomDictionary("first new line second"), "first\nsecond")
            XCTAssertEqual(ASRService.applyCustomDictionary("first  new paragraph  second"), "first\n\nsecond")
            XCTAssertEqual(ASRService.applyCustomDictionary("first tab over second"), "first\tsecond")
            XCTAssertEqual(ASRService.applyCustomDictionary("first   little space   second"), "first second")
            XCTAssertEqual(ASRService.applyCustomDictionary("first\n  new line  second"), "first\n\nsecond")
        }
    }

    func testTransferStillRejectsEmptyAndTrimsVisibleReplacement() throws {
        let document = DictionaryTransferDocument(
            replacements: [
                DictionaryTransferReplacement(from: ["empty"], to: ""),
                DictionaryTransferReplacement(from: ["fluid voice"], to: " FluidVoice \n"),
            ],
            customWords: []
        )

        let decoded = try DictionaryTransferService.shared.decode(DictionaryTransferService.shared.encode(document))

        XCTAssertEqual(decoded.replacements.count, 1)
        XCTAssertEqual(decoded.replacements.first?.to, "FluidVoice")
    }

    func testLocalAPIAcceptsWhitespaceReplacementAndRejectsEmpty() async throws {
        let body = Data(#"{"mode":"replace","entries":[{"triggers":["new line"],"replacement":"\n"},{"triggers":["empty"],"replacement":""}]}"#.utf8)
        let request = LocalAPI.Request(
            method: "POST",
            path: "/v1/dictionary/replacements",
            query: [:],
            headers: ["content-type": "application/json"],
            body: body
        )

        try await self.withRestoredDictionaryAsync {
            let response = await DictionaryAPIController().handle(request)

            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(SettingsStore.shared.customDictionaryEntries.count, 1)
            XCTAssertEqual(SettingsStore.shared.customDictionaryEntries.first?.triggers, ["new line"])
            XCTAssertEqual(SettingsStore.shared.customDictionaryEntries.first?.replacement, "\n")
        }
    }

    private func withRestoredDictionary(_ entries: [SettingsStore.CustomDictionaryEntry], run: () -> Void) {
        let original = SettingsStore.shared.customDictionaryEntries
        defer {
            SettingsStore.shared.customDictionaryEntries = original
            ASRService.invalidateDictionaryCache()
        }
        SettingsStore.shared.customDictionaryEntries = entries
        ASRService.invalidateDictionaryCache()
        run()
    }

    private func withRestoredDictionaryAsync(run: () async throws -> Void) async throws {
        let original = SettingsStore.shared.customDictionaryEntries
        defer {
            SettingsStore.shared.customDictionaryEntries = original
            ASRService.invalidateDictionaryCache()
        }
        try await run()
    }
}

extension CustomDictionaryManualEntryTests {
    func testMatchLevelPersistsOnlyForSelectedWordAndSurvivesMoreTraining() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profiles.json")
        let store = PronunciationDictionaryStore(fileURL: url)
        let targetID = UUID(), otherID = UUID()
        let capture = PronunciationEnrollmentCapture(values: [1, 0], sourceFrameCount: 4, modelKey: "parakeet-v2")
        try await store.upsert(dictionaryEntryID: targetID, label: "Target", modelKey: capture.modelKey, enrollments: [capture, capture, capture])
        try await store.upsert(dictionaryEntryID: otherID, label: "Other", modelKey: capture.modelKey, enrollments: [capture, capture, capture])
        let original = await store.allProfiles()
        try await store.setMatchThreshold(0.45, dictionaryEntryID: targetID)
        let reloaded = await PronunciationDictionaryStore(fileURL: url).allProfiles()
        XCTAssertEqual(reloaded.first { $0.dictionaryEntryID == targetID }?.matchThreshold, 0.45)
        XCTAssertEqual(reloaded.first { $0.dictionaryEntryID == otherID }, original.first { $0.dictionaryEntryID == otherID })
        XCTAssertEqual(reloaded.first?.enrollments, original.first?.enrollments)
        try await store.upsert(dictionaryEntryID: targetID, label: "Target", modelKey: capture.modelKey, enrollments: [capture])
        let updated = await store.allProfiles()
        XCTAssertEqual(updated.first { $0.dictionaryEntryID == targetID }?.matchThreshold, 0.45)
        do {
            try await store.setMatchThreshold(.nan, dictionaryEntryID: targetID)
            XCTFail("Invalid levels must not be persisted")
        } catch {}
        do {
            try await store.setMatchThreshold(0.45, dictionaryEntryID: UUID())
            XCTFail("A deleted word must not be recreated by a pending save")
        } catch {}
        let afterInvalid = await store.allProfiles()
        XCTAssertEqual(afterInvalid, updated)
    }
}

extension CustomDictionaryManualEntryTests {
    private func inspectionFixture() -> DictionaryAudioInspection {
        DictionaryAudioInspection(
            samples: Array(repeating: 0, count: 320) + Array(repeating: 0.2, count: 1280) + Array(repeating: 0, count: 960),
            recordedSampleCount: 2400,
            frames: [.init(offset: 0, frameDuration: 0.08, hiddenSize: 2, values: [1, 0, 0, 1])],
            words: [.init(text: "word", start: 0, end: 0.16)],
            selectedStart: 0,
            selectedEnd: 0.16
        )
    }

    func testAudioInspectionCutsAreBoundedAndDoNotMutateEvidence() async throws {
        let audio = self.inspectionFixture()
        XCTAssertTrue(audio.isValid)
        XCTAssertEqual(audio.embedding(start: 0, end: 0.08), [1, 0])
        XCTAssertEqual(audio.embedding(start: 0.08, end: 0.16), [0, 1])
        XCTAssertNil(audio.embedding(start: .nan, end: 0.16))
        XCTAssertNil(audio.embedding(start: 0, end: 1))
        XCTAssertNil(audio.embedding(start: 0.08, end: 0.08))
        let original = audio
        let score = await DictionaryAudioInspector.shared.score(test: audio, testCut: .init(start: 0, end: 0.08), reference: nil, referenceCut: nil, storedVector: [0, 1])
        XCTAssertEqual(score, 0)
        let changed = await DictionaryAudioInspector.shared.score(test: audio, testCut: .init(start: 0.08, end: 0.16), reference: nil, referenceCut: nil, storedVector: [0, 1])
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(audio, original)
        let full = try await DictionaryAudioInspector.shared.wav(audio, cut: nil)
        XCTAssertEqual(full.count, 44 + audio.recordedSampleCount * 2, "Padding must not be played as captured audio")
        let cut = try await DictionaryAudioInspector.shared.wav(audio, cut: .init(start: 0, end: 0.08))
        XCTAssertEqual(cut.count, 44 + 1280 * 2)
        let metrics = await DictionaryAudioInspector.shared.metrics(audio, cut: .init(start: 0, end: 0.16))
        XCTAssertEqual(metrics.leadingQuiet, 0.02, accuracy: 0.001)
        XCTAssertEqual(metrics.trailingQuiet, 0.05, accuracy: 0.001)
    }

    func testAudioInspectionRejectsCrossChunkAndSilentSelections() async {
        let audio = DictionaryAudioInspection(
            samples: Array(repeating: 0, count: 5120),
            recordedSampleCount: 5120,
            frames: [
                .init(offset: 0, frameDuration: 0.08, hiddenSize: 2, values: [1, 0, 1, 0]),
                .init(offset: 0.16, frameDuration: 0.08, hiddenSize: 2, values: [0, 1, 0, 1]),
            ],
            words: [],
            selectedStart: 0,
            selectedEnd: 0.32
        )
        XCTAssertTrue(audio.isValid)
        XCTAssertNil(audio.embedding(start: 0.08, end: 0.24), "Do not pool independent encoder contexts")
        let metrics = await DictionaryAudioInspector.shared.metrics(audio, cut: .init(start: 0, end: 0.32))
        XCTAssertNil(metrics.suggested, "Silent audio must not produce a fabricated word boundary")
    }

    func testTrainingInspectionPersistsSeparatelyAndFollowsEnrollmentLifetime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profiles.json")
        let store = PronunciationDictionaryStore(fileURL: url)
        let entryID = UUID()
        var capture = PronunciationEnrollmentCapture(values: [1, 0], sourceFrameCount: 1, modelKey: "parakeet-v2")
        capture.pendingInspection = self.inspectionFixture()
        try await store.upsert(dictionaryEntryID: entryID, label: "word", modelKey: capture.modelKey, enrollments: [capture])
        let initial = await store.allProfiles()
        let id = try XCTUnwrap(initial.first?.enrollments.first?.inspectionID)
        XCTAssertNil(initial.first?.enrollments.first?.pendingInspection)
        XCTAssertNil(initial.first?.enrollments.first?.originalAudioID, "Diagnostics must not change original-audio matching eligibility")
        XCTAssertFalse(try XCTUnwrap(initial.first).isEligibleForMatching)
        XCTAssertNil(initial.first?.matchThreshold)
        let reloaded = PronunciationDictionaryStore(fileURL: url)
        let evidence = try await reloaded.inspection(for: id)
        XCTAssertEqual(evidence, capture.pendingInspection)
        let metadata = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(metadata.contains("samples"), "Do not inflate production profile reads with PCM or encoder matrices")
        for _ in 0..<10 {
            try await store.upsert(dictionaryEntryID: entryID, label: "word", modelKey: capture.modelKey, enrollments: [capture])
        }
        let kept = await store.allProfiles()
        XCTAssertEqual(kept.first?.enrollments.count, 10)
        do { _ = try await store.inspection(for: id); XCTFail("Evicted enrollment evidence must be removed") } catch {}
        let latestID = try XCTUnwrap(kept.first?.enrollments.last?.inspectionID)
        try await store.delete(dictionaryEntryID: entryID)
        do { _ = try await store.inspection(for: latestID); XCTFail("Deleting a word must remove diagnostic audio") } catch {}
    }

    func testInvalidInspectionDoesNotWriteOrChangeProfiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PronunciationDictionaryStore(fileURL: directory.appendingPathComponent("profiles.json"))
        let entryID = UUID()
        let legacy = PronunciationEnrollmentCapture(values: [1, 0], sourceFrameCount: 1, modelKey: "parakeet-v2")
        try await store.upsert(dictionaryEntryID: entryID, label: "word", modelKey: legacy.modelKey, enrollments: [legacy])
        let before = await store.allProfiles()
        var invalid = legacy
        var evidence = self.inspectionFixture()
        evidence.recordedSampleCount = Int.max
        invalid.pendingInspection = evidence
        do {
            try await store.upsert(dictionaryEntryID: entryID, label: "word", modelKey: legacy.modelKey, enrollments: [invalid])
            XCTFail("Invalid evidence should fail before activation")
        } catch {}
        let after = await store.allProfiles()
        XCTAssertEqual(after, before)
        XCTAssertNil(after.first?.enrollments.first?.inspectionID)
    }
}

extension CustomDictionaryManualEntryTests {
    func testAudioInspectorRendersWithoutChangingProductionState() async throws {
        var recordingRequests = 0
        let before = SettingsStore.shared.customDictionaryEntries
        let audio = self.inspectionFixture()
        let capture = PronunciationEnrollmentCapture(values: [1, 0], sourceFrameCount: 1, modelKey: "parakeet-v2", inspectionID: UUID())
        let profile = PronunciationDictionaryProfile(dictionaryEntryID: UUID(), label: "Manimekalai", modelKey: "parakeet-v2", hiddenSize: 2, enrollments: [capture, capture, capture])
        let candidate = DictionaryMatchReport.Candidate(id: "sample", word: profile.label, sampleNumber: 1, enrollmentCount: 1, eligible: false, score: 0.6, start: 0, end: 0.08)
        let report = DictionaryMatchReport(
            createdAt: Date(),
            recordingID: UUID(),
            audioPath: "",
            targetWord: profile.label,
            modelKey: profile.modelKey,
            duration: audio.duration,
            rawTranscript: "word",
            savedTranscript: "word",
            availableProfileCount: 1,
            candidates: [candidate],
            targetSamples: [candidate],
            profiles: [profile],
            inspection: audio
        )
        for width in [420.0, 640.0] {
            for scheme in [ColorScheme.light, .dark] {
                let view = DictionaryAudioInspectionView(report: report, recordingBusy: false, loadReference: { _ in audio }, onRecordMore: { recordingRequests += 1 })
                    .padding(20).frame(width: width)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
                    .appTheme(.adaptive(accent: FluidBrandColors.blue, colorScheme: scheme))
                    .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1250), styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(450))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: "/tmp/dictionary-inspector-\(Int(width))-\(scheme).png"))
                window.orderOut(nil)
            }
        }
        XCTAssertEqual(SettingsStore.shared.customDictionaryEntries, before)
        XCTAssertEqual(profile.matchThreshold, nil)
        XCTAssertEqual(recordingRequests, 0, "Loading reference audio must not start training")
    }
}

extension CustomDictionaryManualEntryTests {
    func testTrainingCaptureRetainsAudioWithoutChangingTheEmbedding() async throws {
        #if arch(arm64)
        guard let path = ProcessInfo.processInfo.environment["FV_INSPECTION_AUDIO"] else {
            throw XCTSkip("Opt-in local replay requires FV_INSPECTION_AUDIO and cached Parakeet v2")
        }
        let key = "DictionaryPronunciationDebugCapture"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let provider = FluidAudioProvider(modelOverride: .parakeetTDTv2, configureWordBoosting: false)
        try await provider.prepare()
        let samples = try AudioConverter().resampleAudioFile(path: path)
        UserDefaults.standard.set(true, forKey: key)
        let result = try await provider.transcribeDictionaryTraining(samples, capturePronunciation: true)
        let capture = try XCTUnwrap(result.pronunciationEnrollment)
        let evidence = try XCTUnwrap(capture.pendingInspection)
        XCTAssertTrue(evidence.isValid)
        XCTAssertEqual(evidence.samples, samples)
        XCTAssertEqual(evidence.frames.first?.hiddenSize, 1024)
        let vector = try XCTUnwrap(evidence.embedding(start: evidence.selectedStart, end: evidence.selectedEnd))
        XCTAssertEqual(try XCTUnwrap(DictionaryAudioInspection.similarity(vector, capture.values)), 1, accuracy: 0.00_001)
        UserDefaults.standard.set(false, forKey: key)
        let disabled = try await provider.transcribeDictionaryTraining(samples, capturePronunciation: true)
        let disabledCapture = try XCTUnwrap(disabled.pronunciationEnrollment)
        XCTAssertNil(disabledCapture.pendingInspection)
        XCTAssertEqual(try XCTUnwrap(DictionaryAudioInspection.similarity(disabledCapture.values, capture.values)), 1, accuracy: 0.00_001)
        XCTAssertEqual(disabled.text, result.text)
        #else
        throw XCTSkip("Parakeet encoder replay requires Apple Silicon")
        #endif
    }
}

extension CustomDictionaryManualEntryTests {
    func testOneCutComparesEveryEnrollmentWithoutChangingTheCut() async throws {
        let audio = self.inspectionFixture()
        let cut = DictionaryAudioCut(start: 0, end: 0.08)
        let originals: [[Float]] = [[1, 0], [0, 1], [1, 1]]
        let scores = await DictionaryAudioInspector.shared.scores(test: audio, testCut: cut, references: [], referenceCuts: [], storedVectors: originals)
        XCTAssertEqual(scores.count, 3)
        XCTAssertEqual(scores[0], 1)
        XCTAssertEqual(scores[1], 0)
        XCTAssertEqual(try XCTUnwrap(scores[2]), 1 / sqrt(2), accuracy: 0.00_001)
        let moved = await DictionaryAudioInspector.shared.scores(test: audio, testCut: .init(start: 0.08, end: 0.16), references: [], referenceCuts: [], storedVectors: originals)
        XCTAssertEqual(moved[0], 0)
        XCTAssertEqual(moved[1], 1)
        XCTAssertEqual(moved[2], scores[2])
        let adjustedReference = await DictionaryAudioInspector.shared.scores(
            test: audio,
            testCut: cut,
            references: [nil, audio, nil],
            referenceCuts: [nil, cut, nil],
            storedVectors: originals
        )
        XCTAssertEqual(adjustedReference[0], scores[0])
        XCTAssertEqual(adjustedReference[1], 1)
        XCTAssertEqual(adjustedReference[2], scores[2])
        XCTAssertEqual(cut, DictionaryAudioCut(start: 0, end: 0.08), "Loading or adjusting a reference cannot reset the user's test cut")
        XCTAssertEqual(originals, [[1, 0], [0, 1], [1, 1]])
        let invalid = await DictionaryAudioInspector.shared.scores(test: audio, testCut: .init(start: 0.08, end: 0.08), references: [], referenceCuts: [], storedVectors: originals)
        XCTAssertEqual(invalid.count, 3)
        XCTAssertTrue(invalid.allSatisfy { $0 == nil })
    }

    func testAddingContextCanRaiseSimilarityWithoutImprovingTheWordCut() async throws {
        let audio = self.inspectionFixture()
        let clean = await DictionaryAudioInspector.shared.scores(test: audio, testCut: .init(start: 0, end: 0.08), references: [], referenceCuts: [], storedVectors: [[1, 1]])
        let withContext = await DictionaryAudioInspector.shared.scores(test: audio, testCut: .init(start: 0, end: 0.16), references: [], referenceCuts: [], storedVectors: [[1, 1]])
        XCTAssertGreaterThan(try XCTUnwrap(withContext[0]), try XCTUnwrap(clean[0]), "Mean-pooled similarity is not a measure of word-boundary correctness")
    }
}

extension CustomDictionaryManualEntryTests {
    func testEdgeTrimmingPreservesQuietInsideAndOriginalSamples() throws {
        let samples = [Float](repeating: 0, count: 16_000) + [Float](repeating: 0.1, count: 3200)
            + [Float](repeating: 0, count: 3200) + [Float](repeating: 0.1, count: 3200)
            + [Float](repeating: 0, count: 16_000)
        let range = try XCTUnwrap(DictionaryPronunciationExperiment.trimmedRange(samples))
        XCTAssertEqual(range, 14_080..<27_520)
        XCTAssertEqual(Array(samples[19_200..<22_400]), [Float](repeating: 0, count: 3200))
        XCTAssertNil(DictionaryPronunciationExperiment.trimmedRange([Float](repeating: 0, count: 3200)))
        XCTAssertNil(DictionaryPronunciationExperiment.trimmedRange(samples, within: -1..<10))
        XCTAssertEqual(samples.count, 41_600)
    }

    func testRelativeCalibrationUsesPairwiseAverageAndOneNormalizedCenter() throws {
        let vectors: [[Float]] = [[1, 0], [0.8, 0.6], [0.8, -0.6]]
        let result = try XCTUnwrap(DictionaryPronunciationExperiment.calibration(vectors))
        XCTAssertEqual(result.baseline, (0.8 + 0.8 + 0.28) / 3, accuracy: 0.00_001)
        XCTAssertEqual(result.center[0], 1, accuracy: 0.00_001)
        XCTAssertEqual(result.center[1], 0, accuracy: 0.00_001)
        XCTAssertEqual(Float(0.63) / Float(0.9), 0.7, accuracy: 0.00_001)
        XCTAssertNil(DictionaryPronunciationExperiment.calibration([[0, 0], [1, 0], [1, 0]]))
        XCTAssertNil(DictionaryPronunciationExperiment.calibration([[1], [1, 0], [1, 0]]))
        XCTAssertNil(DictionaryPronunciationExperiment.calibration([[1, 0], [1, 0]]))
    }

    func testEdgeCaptureFieldsPersistWithoutDiagnosticAudio() throws {
        var capture = PronunciationEnrollmentCapture(values: [1, 0], sourceFrameCount: 20, modelKey: "test")
        capture.edgeEmbedding = [0.8, 0.6]
        capture.edgeFrameCount = 10
        let decoded = try JSONDecoder().decode(PronunciationEnrollmentCapture.self, from: JSONEncoder().encode(capture))
        XCTAssertEqual(decoded.edgeEmbedding, capture.edgeEmbedding)
        XCTAssertEqual(decoded.edgeFrameCount, 10)
        XCTAssertNil(decoded.pendingInspection)
        XCTAssertEqual(decoded.values, [1, 0])
    }
}

extension CustomDictionaryManualEntryTests {
    func testEdgeMatchingRealAudioReplay() async throws {
        #if arch(arm64)
        guard let directory = ProcessInfo.processInfo.environment["FV_EDGE_REPLAY_DIR"] else {
            throw XCTSkip("Local-only audio replay requires FV_EDGE_REPLAY_DIR")
        }
        struct Clip: Decodable { let id: String; let path: String; let kind: String }
        let clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("clips.json")))
        let keys = ["DictionaryEdgeMatchingEnabled", "DictionaryPronunciationDebugCapture"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        } }
        UserDefaults.standard.set(true, forKey: keys[0])
        UserDefaults.standard.set(false, forKey: keys[1])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PronunciationDictionaryStore(fileURL: folder.appendingPathComponent("profiles.json"))
        let entry = SettingsStore.CustomDictionaryEntry(triggers: ["manimekalai"], replacement: "Manimekalai")
        let provider = FluidAudioProvider(
            modelOverride: .parakeetTDTv2,
            configureWordBoosting: false,
            enhancementOptions: FluidAudioProviderEnhancementOptions(experimentalUnifiedFinalEnabled: false, pronunciationMatchingEnabled: true, customDictionaryEntries: [entry]),
            pronunciationStore: store
        )
        try await provider.prepare()
        var captures: [PronunciationEnrollmentCapture] = []
        for clip in clips where clip.kind == "reference" {
            let samples = try AudioConverter().resampleAudioFile(path: clip.path)
            let result = try await provider.transcribeDictionaryTraining(samples, capturePronunciation: true)
            let capture = try XCTUnwrap(result.pronunciationEnrollment)
            XCTAssertEqual(capture.edgeEmbedding?.count, 1024)
            XCTAssertNil(capture.pendingInspection)
            captures.append(capture)
        }
        try await store.upsert(dictionaryEntryID: entry.id, label: entry.replacement, modelKey: "parakeet-v2", enrollments: captures)
        let profiles = await store.profiles(modelKey: "parakeet-v2")
        XCTAssertEqual(DictionaryPronunciationReferences.make(profiles: profiles).count, 1)
        for clip in clips where clip.kind != "reference" {
            let result = try await provider.transcribeFinal(AudioConverter().resampleAudioFile(path: clip.path))
            print("EDGE_REPLAY \(clip.id) \(clip.kind): \(result.text)")
            if clip.kind == "negative" { XCTAssertFalse(result.text.lowercased().contains("manimekalai"), clip.id) } else {
                XCTAssertTrue(result.text.lowercased().contains("manimekalai"), clip.id)
                XCTAssertFalse(result.text.lowercased().contains("megala"), "Must replace the complete misheard name")
            }
        }
        UserDefaults.standard.set(false, forKey: keys[0])
        XCTAssertEqual(DictionaryPronunciationReferences.make(profiles: profiles).count, 3)
        #endif
    }
}

extension CustomDictionaryManualEntryTests {
    func testDictionaryDebugCaptureSwitchStopsNewWrites() async throws {
        let key = "DictionaryPronunciationDebugCapture"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = DictionaryPronunciationDebugArchive(directory: root)
        UserDefaults.standard.set(false, forKey: key)
        await archive.save(kind: "test", model: "test", samples: [0.1], transcript: "test", profiles: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        UserDefaults.standard.set(true, forKey: key)
        await archive.save(kind: "test", model: "test", samples: [0.1], transcript: "test", profiles: [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        UserDefaults.standard.set(false, forKey: key)
        await archive.save(kind: "test", model: "test", samples: [0.1], transcript: "test", profiles: [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }
}
