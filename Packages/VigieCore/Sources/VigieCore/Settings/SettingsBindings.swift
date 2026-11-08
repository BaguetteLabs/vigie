import Foundation
import ModuleKit
import SwiftUI
import VigieUI

extension ConfigResolvedValue {
    /// The generated controls' view of this value.
    var controlValue: SettingControlValue {
        switch self {
        case .bool(let value): .bool(value)
        case .int(let value): .int(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .duration(let value): .duration(value)
        case .strings(let value): .strings(value)
        case .none: .none
        }
    }

    init(_ control: SettingControlValue) {
        switch control {
        case .bool(let value): self = .bool(value)
        case .int(let value): self = .int(value)
        case .double(let value): self = .double(value)
        case .string(let value): self = .string(value)
        case .duration(let value): self = .duration(value)
        case .strings(let value): self = .strings(value)
        case .none: self = .none
        }
    }
}

/// A refused Settings write, with catalog text per `ConfigError` case (never the English `reason`).
public struct SettingWriteError: LocalizedError, Equatable {
    public let underlying: ConfigError

    public init(_ underlying: ConfigError) {
        self.underlying = underlying
    }

    public var errorDescription: String? {
        switch underlying {
        case .unknownSetting: SettingsText.string("settings.error.unknownSetting")
        case .invalidValue: SettingsText.string("settings.error.invalidValue")
        case .unsupportedLocation: SettingsText.string("settings.error.unsupportedLocation")
        case .fileUnavailable(let file, _): SettingsText.format("settings.error.fileUnavailable", file)
        case .fileHasErrors(let file): SettingsText.format("settings.error.fileHasErrors", file)
        case .verificationFailed: SettingsText.string("settings.error.verificationFailed")
        case .writeFailed(let file, _): SettingsText.format("settings.error.writeFailed", file)
        case .secretKey: SettingsText.string("settings.error.secretKey")
        }
    }
}

/// A refused secret read or write, with catalog text (never the value, never the English status).
public struct SecretWriteError: LocalizedError, Equatable {
    public let underlying: SecretStoreError

    public init(_ underlying: SecretStoreError) {
        self.underlying = underlying
    }

    public var errorDescription: String? {
        switch underlying {
        case .unavailable: SettingsText.string("settings.error.secretsUnavailable")
        case .notFound, .failed, .consentRequired: SettingsText.string("settings.error.secretFailed")
        }
    }
}

extension ConfigStore {
    /// A binding for the generated controls: reads the resolved value (observing `revision`, so outside edits
    /// refresh the window), writes through `set`, and `set(nil)` resets the key (`remove`).
    func settingBinding(for path: ConfigKeyPath) -> SettingBinding {
        SettingBinding(
            get: { [weak self] in self?.resolvedValue(path)?.controlValue },
            set: { [weak self] value in
                guard let self else { return }
                do throws(ConfigError) {
                    if let value {
                        try await self.set(path, to: ConfigResolvedValue(value))
                    } else {
                        try await self.remove(path)
                    }
                } catch {
                    throw SettingWriteError(error)
                }
            })
    }
}

/// Generated-control services backed by VigieCore: `ConfigDuration` parsing and the KeyboardShortcuts recorder.
@MainActor
enum CoreSettingServices {
    static func make() -> SettingControlServices {
        SettingControlServices(
            parseDuration: { ConfigDuration.parse($0) },
            formatDuration: { ConfigDuration.format($0) },
            hotkeyRecorder: { binding, state in AnyView(HotkeyRecorderField(binding: binding, state: state)) })
    }
}
