import AgentKit
import Foundation

/// Price per million tokens for one model, in its provider section's currency.
public struct ModelPrice: Hashable, Sendable, Codable {
    public let input: Double
    public let output: Double
    /// Cache writes (5-minute TTL rate; Claude Code logs do not split write TTLs).
    public let cacheWrite: Double
    public let cacheRead: Double
    /// Optional higher rates above a prompt size (long-context tiers). Kept in the table, not applied yet: usage is
    /// summed per 15-minute slot, so a single request's prompt size is unknown.
    public let tiers: [PriceTier]?

    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double, tiers: [PriceTier]? = nil) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.tiers = tiers
    }

    enum CodingKeys: String, CodingKey {
        case input, output, tiers
        case cacheWrite = "cache_write"
        case cacheRead = "cache_read"
    }
}

/// The rates that apply once a request's prompt exceeds `aboveTokens`; a missing rate keeps the base one.
public struct PriceTier: Hashable, Sendable, Codable {
    public let aboveTokens: Int
    public let input: Double?
    public let output: Double?
    public let cacheWrite: Double?
    public let cacheRead: Double?

    public init(aboveTokens: Int, input: Double?, output: Double?, cacheWrite: Double? = nil, cacheRead: Double? = nil)
    {
        self.aboveTokens = aboveTokens
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    enum CodingKeys: String, CodingKey {
        case input, output
        case aboveTokens = "above_tokens"
        case cacheWrite = "cache_write"
        case cacheRead = "cache_read"
    }
}

/// The per-provider price table `prices.json` (Story 6.5, schema 2; supersedes A56): one `providers` section per
/// adapter id (AD-23), each with its currency, unit, `updated` date and models. The bundled copy ships with the
/// app; a newer signed copy may be fetched (``PriceTableUpdater``).
public struct PriceTable: Hashable, Sendable, Codable {
    /// The schema this build reads.
    public static let currentSchema = 2

    public let schema: Int
    /// Monotonic: a fetched table is used only when its version is above the bundled and stored ones.
    public let version: Int
    public let note: String?
    public let providers: [String: Provider]

    public struct Provider: Hashable, Sendable, Codable {
        public let currency: String
        public let unit: String
        /// `YYYY-MM-DD`: when the prices were last checked.
        public let updated: String
        public let note: String?
        public let models: [String: ModelPrice]

        public init(
            currency: String = "USD", unit: String = "per_million_tokens", updated: String, note: String? = nil,
            models: [String: ModelPrice]
        ) {
            self.currency = currency
            self.unit = unit
            self.updated = updated
            self.note = note
            self.models = models
        }
    }

    public init(
        schema: Int = PriceTable.currentSchema, version: Int, note: String? = nil, providers: [String: Provider]
    ) {
        self.schema = schema
        self.version = version
        self.note = note
        self.providers = providers
    }

    public enum DecodeError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    /// Decodes a table of the schema this build reads.
    public static func decode(_ data: Data) throws -> PriceTable {
        let table = try JSONDecoder().decode(PriceTable.self, from: data)
        guard table.schema == currentSchema else { throw DecodeError.unsupportedSchema(table.schema) }
        return table
    }

    /// The table bundled with this build.
    public static func bundled() throws -> PriceTable {
        guard let url = Bundle.module.url(forResource: "prices", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    /// This table with every provider section it lacks taken from `fallback` (a stored table without a section
    /// for a provider falls back to the bundled one).
    public func merged(fallback: PriceTable) -> PriceTable {
        PriceTable(
            schema: schema, version: version, note: note,
            providers: providers.merging(fallback.providers) { mine, _ in mine })
    }

    /// The newest `updated` date of the sections in the table (the footer's `PRICES <date>`).
    public var updated: String? { providers.values.map(\.updated).max() }
}

/// Which table the estimates use (the Usage footer's `BUNDLED` / `UPDATED`).
public enum PriceTableSource: Hashable, Sendable {
    case bundled
    case updated
}

/// Estimated cost from a ``PriceTable``. An adapter's models are looked up in the section its
/// `priceProviderID` names (the adapter id by default). A model id matches a table id exactly, or by the longest
/// table id followed by `-` (date-suffixed ids such as `claude-haiku-4-5-20251001`). Unknown models have no
/// price: their cost is nil, never an invented number.
public struct CostEstimator: Sendable {
    public let table: PriceTable
    public let source: PriceTableSource
    /// Adapter id → price table section (``AgentAdapter/priceProviderID``); absent ids use their own id.
    public let sections: [AgentID: String]

    public init(table: PriceTable, source: PriceTableSource = .bundled, sections: [AgentID: String] = [:]) {
        self.table = table
        self.source = source
        self.sections = sections
    }

    /// The section of each adapter.
    public static func sections(for adapters: [any AgentAdapter]) -> [AgentID: String] {
        Dictionary(adapters.map { ($0.id, $0.priceProviderID) }, uniquingKeysWith: { first, _ in first })
    }

    /// The bundled table, sections from `adapters`.
    public static func bundled(adapters: [any AgentAdapter] = []) throws -> CostEstimator {
        CostEstimator(table: try PriceTable.bundled(), source: .bundled, sections: sections(for: adapters))
    }

    public var version: Int { table.version }

    /// The models of the section `provider`'s adapter maps to.
    public func prices(for provider: AgentID) -> [String: ModelPrice] {
        table.providers[sections[provider] ?? provider.rawValue]?.models ?? [:]
    }

    public func price(for model: String, provider: AgentID) -> ModelPrice? {
        let prices = prices(for: provider)
        if let exact = prices[model] { return exact }
        return prices.keys
            .filter { model.hasPrefix($0 + "-") }
            .max { $0.count < $1.count }
            .flatMap { prices[$0] }
    }

    /// Cost of `tokens` of `model` used through `provider`, or nil when the model has no price.
    public func cost(of tokens: TokenCounts, model: String, provider: AgentID) -> Double? {
        guard let price = price(for: model, provider: provider) else { return nil }
        let micro =
            Double(tokens.input) * price.input + Double(tokens.output) * price.output
            + Double(tokens.cacheCreation) * price.cacheWrite + Double(tokens.cacheRead) * price.cacheRead
        return micro / 1_000_000
    }
}
