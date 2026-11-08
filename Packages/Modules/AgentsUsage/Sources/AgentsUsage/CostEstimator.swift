import Foundation

/// USD per million tokens for one model (A56).
public struct ModelPrice: Hashable, Sendable, Codable {
    public let input: Double
    public let output: Double
    /// Cache writes (5-minute TTL rate; Claude Code logs do not split write TTLs).
    public let cacheWrite: Double
    public let cacheRead: Double

    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    enum CodingKeys: String, CodingKey {
        case input, output
        case cacheWrite = "cache_write"
        case cacheRead = "cache_read"
    }
}

/// Estimated cost from the bundled per-model price table `prices.json` (A56): versioned with the app, never
/// fetched. A model id matches a table id exactly, or by the longest table id followed by `-` (date-suffixed
/// ids such as `claude-haiku-4-5-20251001`). Unknown models have no price: their cost is nil.
public struct CostEstimator: Sendable {
    public let version: Int
    public let prices: [String: ModelPrice]

    public init(version: Int = 0, prices: [String: ModelPrice]) {
        self.version = version
        self.prices = prices
    }

    /// The table bundled with this build.
    public static func bundled() throws -> CostEstimator {
        guard let url = Bundle.module.url(forResource: "prices", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let table = try JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
        return CostEstimator(version: table.version, prices: table.models)
    }

    public func price(for model: String) -> ModelPrice? {
        if let exact = prices[model] { return exact }
        return prices.keys
            .filter { model.hasPrefix($0 + "-") }
            .max { $0.count < $1.count }
            .flatMap { prices[$0] }
    }

    /// USD for `tokens` of `model`, or nil when the model has no price.
    public func cost(of tokens: TokenCounts, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        let micro =
            Double(tokens.input) * price.input + Double(tokens.output) * price.output
            + Double(tokens.cacheCreation) * price.cacheWrite + Double(tokens.cacheRead) * price.cacheRead
        return micro / 1_000_000
    }

    struct Table: Decodable {
        let version: Int
        let models: [String: ModelPrice]
    }
}
