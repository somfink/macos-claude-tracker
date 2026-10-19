import Foundation
import Testing
@testable import TrackerCore

private func usage(
    input: Int = 0, output: Int = 0, write5m: Int = 0, write1h: Int = 0, read: Int = 0,
    legacyWrite: Int? = nil, speed: String? = nil
) -> TokenUsage {
    TokenUsage(
        inputTokens: input,
        outputTokens: output,
        cacheCreationInputTokens: legacyWrite ?? (write5m + write1h),
        cacheReadInputTokens: read,
        cacheCreation: legacyWrite == nil ? .init(ephemeral5m: write5m, ephemeral1h: write1h) : nil,
        speed: speed
    )
}

private let million = 1_000_000

@Suite("API-equivalent pricing")
struct PricingTests {
    @Test func opus55AllTokenKinds() throws {
        let tokens = usage(input: million, output: million, write5m: million, write1h: million, read: million)

        let cost = try #require(Pricing.cost(of: tokens, model: "claude-opus-5-5"))

        // 4 input + 20 output + 5 (5m write) + 8 (1h write) + 0.20 read
        #expect(abs(cost - 37.20) < 0.0001)
    }

    @Test func fable51DiscountedCacheReads() throws {
        let cost = try #require(Pricing.cost(of: usage(read: million), model: "claude-fable-5-1"))

        #expect(abs(cost - 0.25) < 0.0001)
    }

    @Test func fable5UsesStandardCacheReads() throws {
        let cost = try #require(Pricing.cost(of: usage(read: million), model: "claude-fable-5"))

        #expect(abs(cost - 1.0) < 0.0001)
    }

    @Test func longestPrefixWins() throws {
        let opus5 = try #require(Pricing.cost(of: usage(input: million), model: "claude-opus-5"))
        let opus55 = try #require(Pricing.cost(of: usage(input: million), model: "claude-opus-5-5"))
        let opus48 = try #require(Pricing.cost(of: usage(input: million), model: "claude-opus-4-8"))
        let opus41 = try #require(Pricing.cost(of: usage(input: million), model: "claude-opus-4-1-20250805"))

        #expect(opus5 == 5)
        #expect(opus55 == 4)
        #expect(opus48 == 5)
        #expect(opus41 == 15)
    }

    @Test func modelSuffixesAreIgnored() throws {
        #expect(try #require(Pricing.cost(of: usage(output: million), model: "claude-sonnet-5-5[1m]")) == 10)
        #expect(try #require(Pricing.cost(of: usage(output: million), model: "claude-haiku-4-5-20251001")) == 5)
    }

    @Test func legacyCacheWriteCountsAsFiveMinute() throws {
        let cost = try #require(Pricing.cost(of: usage(legacyWrite: million), model: "claude-sonnet-4-6"))

        #expect(abs(cost - 3.75) < 0.0001)
    }

    @Test func fastModeDoublesPrice() throws {
        let cost = try #require(Pricing.cost(of: usage(input: million, output: million, speed: "fast"), model: "claude-opus-5-5"))

        #expect(abs(cost - 48) < 0.0001)
    }

    @Test func haiku55LongPromptTier() throws {
        let short = try #require(Pricing.cost(of: usage(input: 50_000, output: million), model: "claude-haiku-5-5"))
        let long = try #require(Pricing.cost(of: usage(input: 150_000, output: million), model: "claude-haiku-5-5"))

        #expect(abs(short - (0.05 * 0.10 + 0.50)) < 0.0001)
        #expect(abs(long - (0.15 * 0.50 + 2.50)) < 0.0001)
    }

    @Test(arguments: ["<synthetic>", "gpt-5", "claude-unknown-9"])
    func unknownModelsAreUnpriced(model: String) {
        #expect(Pricing.cost(of: usage(input: million), model: model) == nil)
    }
}

@Suite("Usage line parsing")
struct UsageParserTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func line(id: String, model: String = "claude-opus-5-5", ts: String = "2026-10-18T09:00:00.000Z",
                      output: Int = 1_000_000, sidechain: Bool = false) -> String {
        """
        {"type":"assistant","isSidechain":\(sidechain),"timestamp":"\(ts)","message":{"id":"\(id)","model":"\(model)",\
        "usage":{"input_tokens":0,"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,\
        "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"speed":"standard"}}}
        """
    }

    @Test func parsesAssistantUsage() throws {
        let data = Data((line(id: "m1") + "\n").utf8)

        let records = UsageParser.records(in: data, calendar: calendar)

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.messageId == "m1")
        #expect(record.day == "2026-10-18")
        #expect(abs(record.cost - 20) < 0.0001)
        #expect(record.model == "claude-opus-5-5")
    }

    @Test func dayUsesLocalTimeZone() throws {
        // 23:30 UTC on Oct 31 is already Nov 1 in Warsaw (UTC+1 after DST ends).
        let data = Data(line(id: "m1", ts: "2026-10-31T23:30:00.000Z").utf8)

        #expect(UsageParser.records(in: data, calendar: calendar).first?.day == "2026-11-01")
    }

    @Test func skipsNonAssistantAndSyntheticLines() {
        let lines = [
            #"{"type":"user","message":{"content":"hi"}}"#,
            line(id: "m2", model: "<synthetic>"),
            "garbage",
        ]

        #expect(UsageParser.records(in: Data(lines.joined(separator: "\n").utf8), calendar: calendar).isEmpty)
    }

    @Test func includesSubagentUsage() {
        // Sidechain turns are billed like any other request.
        #expect(UsageParser.records(in: Data(line(id: "m3", sidechain: true).utf8), calendar: calendar).count == 1)
    }
}
