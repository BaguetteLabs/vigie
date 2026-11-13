import Darwin
import Foundation

/// A completed write: the bytes now on disk and their parsed document.
struct ConfigWriteResult: Sendable {
    let data: Data
    let document: ConfigDocument
    /// False when the patched text equalled the file (nothing was written).
    let wrote: Bool
}

/// Performs ConfigStore's writes off the main actor, one at a time (AD-8, Conventions: File writes).
///
/// Every write resolves symlinks, re-reads the file, patches the fresh text with `TOMLPatcher`, re-parses
/// the result with swift-toml and checks that it decodes to the original document with exactly the intended
/// change, then replaces the file atomically (temp file in the same folder + `rename`, original POSIX mode
/// kept). Any failure leaves the file untouched.
actor ConfigWriter {
    /// Sets (`value` non-nil) or removes `path` in the file at `url`.
    /// - Parameter hook: tests only; rewrites the patched text before verification.
    func write(
        _ path: ConfigKeyPath,
        value: TOMLScalar?,
        to url: URL,
        hook: (@Sendable (String) -> String)? = nil
    ) throws(ConfigError) -> ConfigWriteResult {
        let key = path.description
        let name = url.lastPathComponent
        let target = url.resolvingSymlinksInPath()

        let original: Data
        var exists = true
        switch CoordinatedFileReader.readNow(target, status: SystemUbiquitousItemStatus()) {
        case .data(let data): original = data
        case .missing:
            original = Data()
            exists = false
        case .pending: throw .fileUnavailable(file: name, reason: "not downloaded from iCloud yet")
        case .failed(let reason): throw .fileUnavailable(file: name, reason: reason)
        }
        guard let text = String(validating: original, as: UTF8.self) else {
            throw .fileUnavailable(file: name, reason: "not valid UTF-8")
        }
        let before: ConfigDocument
        do {
            before = try ConfigDocument.parse(Self.droppingBOM(text))
        } catch {
            throw .fileHasErrors(file: name)
        }

        var patched: String
        do {
            if let value {
                patched = try TOMLPatcher.set(text, path: path, value: value)
            } else {
                patched = try TOMLPatcher.remove(text, path: path)
            }
        } catch .unsupportedLocation {
            throw .unsupportedLocation(key: key)
        } catch {
            throw .verificationFailed(key: key)
        }
        if let hook { patched = hook(patched) }

        let expected = before.replacing(path, with: value?.configValue)
        guard let after = try? ConfigDocument.parse(Self.droppingBOM(patched)), after == expected else {
            throw .verificationFailed(key: key)
        }
        let data = Data(patched.utf8)
        if exists, data == original {
            return ConfigWriteResult(data: data, document: after, wrote: false)
        }
        try Self.atomicWrite(data, to: target, name: name)
        return ConfigWriteResult(data: data, document: after, wrote: true)
    }

    static func droppingBOM(_ text: String) -> String {
        text.unicodeScalars.first == "\u{FEFF}" ? String(text.unicodeScalars.dropFirst()) : text
    }

    /// Writes a temp file next to `target`, gives it `target`'s permissions and renames it over `target`,
    /// under a coordinated write (AD-12).
    static func atomicWrite(_ data: Data, to target: URL, name: String) throws(ConfigError) {
        let folder = target.deletingLastPathComponent()
        var failure: String?
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .writeFailed(file: name, reason: error.localizedDescription)
        }
        var info = stat()
        let mode: mode_t? = stat(target.path, &info) == 0 ? info.st_mode & 0o7777 : nil

        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) {
            writeURL in
            let temp = writeURL.deletingLastPathComponent()
                .appendingPathComponent(".\(writeURL.lastPathComponent).\(UUID().uuidString).tmp")
            do {
                try data.write(to: temp)
            } catch {
                failure = error.localizedDescription
                return
            }
            if let mode, chmod(temp.path, mode) != 0 {
                failure = String(cString: strerror(errno))
                unlink(temp.path)
                return
            }
            if rename(temp.path, writeURL.path) != 0 {
                failure = String(cString: strerror(errno))
                unlink(temp.path)
            }
        }
        if let coordinationError { throw .writeFailed(file: name, reason: coordinationError.localizedDescription) }
        if let failure { throw .writeFailed(file: name, reason: failure) }
    }
}

extension ConfigDocument {
    /// The document with `path` set to `value` (creating missing tables), or removed when `value` is nil.
    func replacing(_ path: ConfigKeyPath, with value: ConfigValue?) -> ConfigDocument {
        func apply(_ table: [String: ConfigValue], _ segments: ArraySlice<String>) -> [String: ConfigValue] {
            guard let key = segments.first else { return table }
            var table = table
            if segments.count == 1 {
                table[key] = value
                return table
            }
            switch table[key] {
            case .table(let child):
                table[key] = .table(apply(child, segments.dropFirst()))
            case nil where value != nil:
                table[key] = .table(apply([:], segments.dropFirst()))
            default:
                break
            }
            return table
        }
        return ConfigDocument(root: apply(root, path.segments[...]))
    }
}
