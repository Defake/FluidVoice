import Combine
import Foundation

/// Owns one explicit setup attempt. Reads and cancelled work never commit a model selection.
@MainActor
final class OnboardingAISetupController: ObservableObject {
    struct Model: Equatable, Sendable {
        let id: String
        let name: String
        let byteCount: Int64?
        let installed: Bool
    }

    struct Progress: Equatable, Sendable {
        let fraction: Double?
        let status: String
        let bytes: String?
    }

    enum Phase: Equatable {
        case checking, offered, downloading, loading, cancelling, ready, unavailable
    }

    struct Dependencies {
        var recommend: () async throws -> Model
        var prepare: (Model, @escaping @Sendable (Progress) async -> Void) async throws -> Void
        var load: (Model) async throws -> Void
    }

    @Published private(set) var model: Model?
    @Published private(set) var phase: Phase = .checking
    @Published private(set) var progress: Progress?
    @Published private(set) var errorMessage: String?
    private let dependencies: Dependencies
    private var task: Task<Void, Never>?
    private var operationID = UUID()

    var isBusy: Bool { [.downloading, .loading, .cancelling].contains(self.phase) }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func refresh() {
        guard self.task == nil, self.phase != .ready else { return }
        let operation = UUID()
        self.operationID = operation
        self.phase = .checking
        self.errorMessage = nil
        self.task = Task { @MainActor in
            defer { if self.operationID == operation { self.task = nil } }
            do {
                let model = try await self.dependencies.recommend()
                try Task.checkCancellation()
                guard self.operationID == operation else { return }
                self.model = model
                self.phase = .offered
            } catch {
                guard self.operationID == operation else { return }
                self.phase = .unavailable
                if !Task.isCancelled { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func enable(onReady: @escaping (Model) throws -> Void) {
        guard self.task == nil, self.phase == .offered, let model else { return }
        let operation = UUID()
        self.operationID = operation
        self.progress = nil
        self.errorMessage = nil
        self.phase = model.installed ? .loading : .downloading
        self.task = Task { @MainActor in
            defer { if self.operationID == operation { self.task = nil } }
            do {
                if !model.installed {
                    try await self.dependencies.prepare(model) { progress in
                        await MainActor.run {
                            guard self.operationID == operation, self.phase == .downloading else { return }
                            self.progress = progress
                        }
                    }
                }
                try Task.checkCancellation()
                guard self.operationID == operation else { return }
                self.phase = .loading
                self.progress = nil
                try await self.dependencies.load(model)
                try Task.checkCancellation()
                guard self.operationID == operation else { return }
                // Persistence is performed only here, after readiness and cancellation checks.
                try onReady(model)
                self.phase = .ready
            } catch {
                guard self.operationID == operation else { return }
                self.phase = .offered
                self.progress = nil
                if !Task.isCancelled, !(error is CancellationError) {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancel() {
        guard self.task != nil else { return }
        self.task?.cancel()
        self.progress = nil
        self.errorMessage = nil
        if self.isBusy { self.phase = .cancelling }
    }
}
