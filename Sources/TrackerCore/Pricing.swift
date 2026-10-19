import Foundation

/// Token counts of one API response, as Claude Code stores them in `message.usage`.
public struct TokenUsage: Codable, Equatable, Sendable {
    public struct CacheCreation: Codable, Equatable, Sendable {
        public let ephemeral5m: Int?
        public let ephemeral1h: Int?

        public init(ephemeral5m: Int?, ephemeral1h: Int?) {
            self.ephemeral5m = ephemeral5m
            self.ephemeral1h = ephemeral1h
        }

        enum CodingKeys: String, CodingKey {
            case ephemeral5m = "ephemeral_5m_input_tokens"
            case ephemeral1h = "ephemeral_1h_input_tokens"
        }
    }

    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?
    public let cacheCreation: CacheCreation?
    /// `fast` when the request ran in fast mode (premium pricing).
    public let speed: String?

    public init(
        inputTokens: Int?, outputTokens: Int?, cacheCreationInputTokens: Int?,
        cacheReadInputTokens: Int?, cacheCreation: CacheCreation?, speed: String?
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreation = cacheCreation
        self.speed = speed
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreation = "cache_creation"
        case speed
    }

    /// 1-hour writes when broken down; anything else written counts as 5-minute.
    var cacheWrite1h: Int { cacheCreation?.ephemeral1h ?? 0 }
    var cacheWrite5m: Int { max((cacheCreationInputTokens ?? 0) - cacheWrite1h, 0) }
    var promptTokens: Int { (inputTokens ?? 0) + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0) }
}

/// USD per million tokens.
public struct ModelPrice: Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let cacheWrite5m: Double
    public let cacheWrite1h: Double
    public let cacheRead: Double

    /// Standard cache economics: writes 1.25× (5 min) / 2× (1 h), reads 0.1× of input.
    static func standard(input: Double, output: Double, cacheRead: Double? = nil) -> ModelPrice {
        ModelPrice(
            input: input, output: output,
            cacheWrite5m: input * 1.25, cacheWrite1h: input * 2,
            cacheRead: cacheRead ?? input * 0.1
        )
    }

    func scaled(by factor: Double) -> ModelPrice {
        ModelPrice(
            input: input * factor, output: output * factor,
            cacheWrite5m: cacheWrite5m * factor, cacheWrite1h: cacheWrite1h * factor,
            cacheRead: cacheRead * factor
        )
    }
}

/// What a Claude Code request would cost at Anthropic first-party API list prices.
/// Source: claude-api skill model table (cached 2026-10-06). An estimate: long-context
/// premiums of older models and batch/priority discounts are not modeled.
public enum Pricing {
    private static let perMillion = 1_000_000.0
    private static let fastModeMultiplier = 2.0
    /// Claude Haiku 5.5 bills prompts above this size at the higher tier.
    private static let haiku55TierThreshold = 100_000

    private static let haiku55 = ModelPrice.standard(input: 0.10, output: 0.50)
    private static let haiku55Long = ModelPrice.standard(input: 0.50, output: 2.50)

    /// Model id prefix → price. Matched longest prefix first, so `claude-opus-5-5`
    /// wins over `claude-opus-5` and date or `[1m]` suffixes are ignored.
    private static let table: [(prefix: String, price: ModelPrice)] = [
        ("claude-fable-5-1", .standard(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", .standard(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", .standard(input: 10, output: 50)),
        ("claude-mythos-5", .standard(input: 10, output: 50)),
        ("claude-opus-5-5", .standard(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", .standard(input: 5, output: 25)),
        ("claude-opus-4-8", .standard(input: 5, output: 25)),
        ("claude-opus-4-7", .standard(input: 5, output: 25)),
        ("claude-opus-4-6", .standard(input: 5, output: 25)),
        ("claude-opus-4-5", .standard(input: 5, output: 25)),
        ("claude-opus-4", .standard(input: 15, output: 75)),
        ("claude-sonnet-5-5", .standard(input: 2, output: 10)),
        ("claude-sonnet-5", .standard(input: 2, output: 10)),
        ("claude-sonnet-4", .standard(input: 3, output: 15)),
        ("claude-haiku-4-5", .standard(input: 1, output: 5)),
    ].sorted { $0.prefix.count > $1.prefix.count }

    public static func price(for model: String, promptTokens: Int) -> ModelPrice? {
        if model.hasPrefix("claude-haiku-5-5") {
            return promptTokens > haiku55TierThreshold ? haiku55Long : haiku55
        }
        return table.first { model.hasPrefix($0.prefix) }?.price
    }

    /// nil for models without a known price (`<synthetic>`, other vendors, future ids).
    public static func cost(of usage: TokenUsage, model: String) -> Double? {
        guard let base = price(for: model, promptTokens: usage.promptTokens) else { return nil }
        let price = usage.speed == "fast" ? base.scaled(by: fastModeMultiplier) : base
        let dollars = Double(usage.inputTokens ?? 0) * price.input
            + Double(usage.outputTokens ?? 0) * price.output
            + Double(usage.cacheWrite5m) * price.cacheWrite5m
            + Double(usage.cacheWrite1h) * price.cacheWrite1h
            + Double(usage.cacheReadInputTokens ?? 0) * price.cacheRead
        return dollars / perMillion
    }
}
