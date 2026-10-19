/// Hand-drawn 20×16 frames of the menu bar crab, one string per pixel row.
///
/// Legend: `.` transparent · `O` body · `E` eye · `L` laptop lid · `l` lid logo ·
/// `K` keyboard · `S` keystroke spark · `Y` alert · `G` check mark · `Z` snore.
/// Colors live in the app target; this file is pure data so tests can validate it.
public enum MascotSprites {
    public static let width = 20
    public static let height = 16
    public static let paletteCharacters: Set<Character> = [".", "O", "E", "L", "l", "K", "S", "Y", "G", "Z"]

    public static func frames(for mood: MascotMood) -> [PixelSprite] {
        switch mood {
        case .sleeping: [sleeping]
        case .ready: [ready]
        case .working: [workingLeftHand, workingRightHand]
        case .waiting: [waitingStill, waitingWave]
        }
    }

    // MARK: Shared rows

    private static let blank = "...................."
    private static let body = "....OOOOOOOOOOOO...."
    private static let eyes = "....OOEEOOOOEEOO...."
    private static let arms = "..OOOOOOOOOOOOOOOO.."
    private static let legs = "....O.O......O.O...."
    private static let lid = "....OLLLLLLLLLLO...."
    private static let keyboard = "..KKKKKKKKKKKKKKKK.."

    private static let lowerBody = [arms, arms, body, body, legs, legs, blank]

    // MARK: Frames

    /// The crab alone, cropped to its body: the app icon, so banners and Finder show who it is.
    public static let appIcon = PixelSprite(rows: [body, body, eyes, body] + lowerBody.dropLast())

    /// Eyes shut, snoring: no sessions open.
    static let sleeping = PixelSprite(rows: [
        "...............ZZZZ.",
        ".................Z..",
        "................Z...",
        "...............ZZZZ.",
        blank,
        body, body, body,
        eyes,
    ] + lowerBody)

    /// Happy `^ ^` eyes with a check mark: everything finished.
    static let ready = PixelSprite(rows: [
        blank,
        "...................G",
        "..............G...G.",
        "...............G.G..",
        "................G...",
        body, body,
        "....OOOEOOOOEOOO....",
        "....OOEOEOOEOEOO....",
    ] + lowerBody)

    /// Looking up at a blinking `!`: a session needs the user.
    static let waitingStill = PixelSprite(rows: [
        ".................YY.",
        ".................YY.",
        ".................YY.",
        blank,
        ".................YY.",
        body,
        "....OOOEEOOOOEEO....",
        "....OOOEEOOOOEEO....",
        body,
    ] + lowerBody)

    /// Same pose, right claw raised to wave.
    static let waitingWave = PixelSprite(rows: [
        ".................YY.",
        ".................YY.",
        ".................YY.",
        blank,
        ".................YY.",
        body,
        "....OOOEEOOOOEEO....",
        "....OOOEEOOOOEEOOO..",
        "....OOOOOOOOOOOOOO..",
        "..OOOOOOOOOOOOOO....",
        "..OOOOOOOOOOOOOO....",
        body, body, legs, legs, blank,
    ])

    /// Typing behind a laptop, left claw up.
    static let workingLeftHand = PixelSprite(rows: [
        blank,
        "..................S.",
        ".................S..",
        blank, blank,
        body, body, body,
        eyes,
        lid, lid,
        "..OOOLLLLllLLLLO....",
        lid,
        "....OLLLLLLLLLLOOO..",
        keyboard,
        blank,
    ])

    /// Typing behind a laptop, right claw up.
    static let workingRightHand = PixelSprite(rows: [
        blank,
        "................S...",
        blank,
        "..................S.",
        blank,
        body, body, body,
        eyes,
        lid, lid,
        "....OLLLLllLLLLOOO..",
        lid,
        "..OOOLLLLLLLLLLO....",
        keyboard,
        blank,
    ])
}

/// sRGB colors for sprite characters, shared by the app's NSImage renderer and the widget.
public enum MascotPalette {
    public struct RGB: Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    public static let colors: [Character: RGB] = [
        "O": RGB(red: 0.85, green: 0.47, blue: 0.34),  // Claude-ish terracotta
        "E": RGB(red: 0.12, green: 0.07, blue: 0.05),
        "L": RGB(red: 0.75, green: 0.77, blue: 0.80),
        "l": RGB(red: 0.55, green: 0.58, blue: 0.62),
        "K": RGB(red: 0.45, green: 0.48, blue: 0.52),
        "S": RGB(red: 0.42, green: 0.77, blue: 1.00),
        "Y": RGB(red: 1.00, green: 0.78, blue: 0.20),
        "G": RGB(red: 0.20, green: 0.78, blue: 0.35),
        "Z": RGB(red: 0.62, green: 0.65, blue: 0.70),
    ]
}
