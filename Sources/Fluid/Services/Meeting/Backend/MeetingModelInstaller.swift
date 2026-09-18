import CryptoKit
import Darwin
import Foundation

/// Temporary offline beta installer. Checksums identify the shipped FP16 package,
/// not an arbitrary CoreML model with a matching filename. Run off the main actor.
nonisolated enum MeetingModelInstaller {
    private static let installationLock = NSLock()
    private static let expectedFiles = [
        "Manifest.json": "419130ae729d97aa5eba50abf9439cf01c1d5971821ddc1899b5c54728b3f302",
        "Data/com.apple.CoreML/model.mlmodel": "c6112ac5ec5e217d2cebaba9e1d961f6df6e3bbb8e063188423c8e1575dca029",
        "Data/com.apple.CoreML/weights/weight.bin": "d4838b028504ab3f9df8d733380cb1241c6c19896c17142e42fd6396a67de6c5",
    ]

    enum InstallError: LocalizedError {
        case wrongPackage
        var errorDescription: String? {
            "Choose the supplied beta Nemotron FP16 .mlpackage. This package is different or damaged."
        }
    }

    static func validate(_ package: URL) throws -> MeetingNemotronModelArtifact {
        let artifact = try MeetingNemotronModelLocator.validatePackage(at: package.standardizedFileURL)
        for (path, expected) in Self.expectedFiles {
            let handle = try FileHandle(forReadingFrom: package.appendingPathComponent(path))
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
                throw InstallError.wrongPackage
            }
        }
        return artifact
    }

    static func install(from source: URL, to destination: URL = MeetingNemotronModelLocator.defaultPackageURL()) throws -> MeetingNemotronModelArtifact {
        self.installationLock.lock()
        defer { self.installationLock.unlock() }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        _ = try Self.validate(source)
        if source.standardizedFileURL == destination.standardizedFileURL {
            return try Self.validate(destination)
        }
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent("import-\(UUID().uuidString).mlpackage", isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: source, to: staging)
        let artifact = try Self.validate(staging)
        try Task.checkCancellation()
        if manager.fileExists(atPath: destination.path) {
            // Atomically swap directory packages; staging then contains the old model.
            let result = staging.withUnsafeFileSystemRepresentation { stagedPath in
                destination.withUnsafeFileSystemRepresentation { destinationPath in
                    renameatx_np(AT_FDCWD, stagedPath, AT_FDCWD, destinationPath, UInt32(RENAME_SWAP))
                }
            }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
        return MeetingNemotronModelArtifact(
            packageURL: destination,
            totalByteCount: artifact.totalByteCount,
            fileCount: artifact.fileCount,
            manifestSHA256: artifact.manifestSHA256,
            entryMetadataSHA256: artifact.entryMetadataSHA256
        )
    }
}
