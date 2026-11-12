import Foundation
import ModuleKit

/// `context.updates` (Story 6.5): `[updates] prices` and `check_interval` read from the resolved config at each
/// read (live reload, AD-8), and the price table's location from the bundle's updater keys.
public struct CoreUpdatesService: UpdatesService {
    let shared: ConfigSharedState?
    public let priceTable: PriceTableLocation?

    init(shared: ConfigSharedState?, priceTable: PriceTableLocation?) {
        self.shared = shared
        self.priceTable = priceTable
    }

    public var pricesEnabled: Bool {
        shared?.value(at: UpdateSettings.pricesPath)?.typed(as: Bool.self) ?? true
    }

    public var checkInterval: Duration {
        let interval =
            shared?.value(at: UpdateSettings.checkIntervalPath)?.typed(as: Duration.self)
            ?? UpdateSettings.defaults.checkInterval
        return max(interval, UpdateSettings.minimumInterval)
    }
}

extension UpdaterConfiguration {
    /// The signed price table's location (Story 6.5): `prices.json` and `prices.json.sig` next to the appcast
    /// (`SUFeedURL` is `https://github.com/<release repo>/releases/latest/download/appcast.xml`), verified with
    /// `SUPublicEDKey`. nil whenever the updater itself is unconfigured (``check(infoDictionary:)``: empty key, or
    /// the `OWNER/…` placeholder release repository): no request is ever made then.
    public static func priceTableLocation(infoDictionary: [String: Any]) -> PriceTableLocation? {
        guard check(infoDictionary: infoDictionary) == nil,
            let feed = (infoDictionary["SUFeedURL"] as? String).flatMap(URL.init(string:)),
            let key = (infoDictionary["SUPublicEDKey"] as? String)
                .flatMap({ Data(base64Encoded: $0.trimmingCharacters(in: .whitespaces)) })
        else { return nil }
        let folder = feed.deletingLastPathComponent()
        return PriceTableLocation(
            tableURL: folder.appendingPathComponent(priceTableName),
            signatureURL: folder.appendingPathComponent(priceTableName + ".sig"), publicKey: key)
    }

    /// The published file name (`Scripts/release/prices.sh`).
    public static let priceTableName = "prices.json"
}
