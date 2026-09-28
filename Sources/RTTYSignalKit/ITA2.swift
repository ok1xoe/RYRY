/// Nezávislá ITA2 / US-TTY tabulka pro testy (NEsdílí kód s MMTTY CRTTY).
public enum ITA2 {
    public static let ltrs: UInt8 = 0x1F
    public static let figs: UInt8 = 0x1B

    static let letters: [Character: UInt8] = [
        "E": 0x01, "\n": 0x02, "A": 0x03, " ": 0x04, "S": 0x05, "I": 0x06, "U": 0x07,
        "\r": 0x08, "D": 0x09, "R": 0x0A, "J": 0x0B, "N": 0x0C, "F": 0x0D, "C": 0x0E,
        "K": 0x0F, "T": 0x10, "Z": 0x11, "L": 0x12, "W": 0x13, "H": 0x14, "Y": 0x15,
        "P": 0x16, "Q": 0x17, "O": 0x18, "B": 0x19, "G": 0x1A, "M": 0x1C, "X": 0x1D,
        "V": 0x1E,
    ]
    /// Jen znaky společné pro US-TTY i ITA2 (bez $ ! " # & ; ' BELL).
    static let figures: [Character: UInt8] = [
        "3": 0x01, "-": 0x03, "8": 0x06, "7": 0x07, "4": 0x0A, ",": 0x0C, ":": 0x0E,
        "(": 0x0F, "5": 0x10, ")": 0x12, "2": 0x13, "6": 0x15, "0": 0x16, "1": 0x17,
        "9": 0x18, "?": 0x19, ".": 0x1C, "/": 0x1D,
    ]

    /// Text → 5bitové kódy. Začíná LTRS, FIGS/LTRS vkládá podle potřeby.
    /// Mezera, CR a LF jsou v obou registrech (bez přepnutí). Neznámé znaky vynechá.
    public static func encode(_ text: String) -> [UInt8] {
        var out: [UInt8] = [ltrs]
        var inFigs = false
        // Po znacích Unicode (CR LF je v Swiftu jeden Character, proto přes unicodeScalars).
        for scalar in text.uppercased().unicodeScalars {
            let ch = Character(scalar)
            if ch == " " || ch == "\r" || ch == "\n" {
                out.append(letters[ch]!)
            } else if let c = letters[ch] {
                if inFigs { out.append(ltrs); inFigs = false }
                out.append(c)
            } else if let c = figures[ch] {
                if !inFigs { out.append(figs); inFigs = true }
                out.append(c)
            }
        }
        return out
    }
}
