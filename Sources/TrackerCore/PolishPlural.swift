/// Polish count agreement: 1 → singular, 2–4 (not 12–14) → "few", everything else → "many".
public enum PolishPlural {
    public static func sessions(_ count: Int) -> String {
        "\(count) " + form(count, one: "sesja", few: "sesje", many: "sesji")
    }

    /// Feminine adjective agreeing with "sesja": `3 aktywne`, `5 aktywnych`.
    public static func active(_ count: Int) -> String {
        "\(count) " + form(count, one: "aktywna", few: "aktywne", many: "aktywnych")
    }

    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        let lastDigit = count % 10
        let lastTwo = count % 100
        if count == 1 { return one }
        if (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) { return few }
        return many
    }
}
