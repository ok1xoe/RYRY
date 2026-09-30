// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import DXCC

/// Zeměpisné výpočty pro směr antény a vzdálenost k protistanici (čistá logika bez UI).
public enum Geo {
    /// Zeměpisná poloha ve stupních: šířka + na sever, délka + na východ.
    public struct Coordinate: Sendable, Equatable {
        public var lat: Double, lon: Double
        public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    }

    /// Odkud poloha pochází: z lokátoru (střed čtverce), nebo jen podle země DXCC (přibližně).
    public enum Source: Sendable, Equatable { case locator, country }

    public struct Position: Sendable, Equatable {
        public var coordinate: Coordinate
        public var source: Source
        public init(coordinate: Coordinate, source: Source) { self.coordinate = coordinate; self.source = source }
    }

    /// Směr a vzdálenost krátkou i dlouhou cestou (long path = opačný směr, zbytek obvodu Země).
    public struct Beam: Sendable, Equatable {
        public var shortAzimuth: Double
        public var shortKm: Double
        public var longAzimuth: Double
        public var longKm: Double
        public var ownSource: Source
        public var remoteSource: Source
    }

    /// Střední poloměr Země (km) pro velkokružnicovou vzdálenost.
    public static let earthRadiusKm = 6371.0
    /// Obvod Země (km) pro dlouhou cestu.
    public static let circumferenceKm = 40075.0

    // MARK: Maidenhead

    /// Střed čtverce Maidenhead lokátoru o 4, 6 nebo 8 znacích (`JO70`, `JO70fc`, `JO70FC55`); neplatný → nil.
    public static func maidenhead(_ locator: String) -> Coordinate? {
        let s = Array(locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().unicodeScalars)
        guard [4, 6, 8].contains(s.count) else { return nil }
        func letter(_ u: Unicode.Scalar, upTo last: UInt32) -> Double? {
            guard u.value >= 65, u.value <= last else { return nil }
            return Double(u.value - 65)
        }
        func digit(_ u: Unicode.Scalar) -> Double? {
            guard u.value >= 48, u.value <= 57 else { return nil }
            return Double(u.value - 48)
        }
        guard let fl = letter(s[0], upTo: 82), let fa = letter(s[1], upTo: 82),     // A–R
              let dl = digit(s[2]), let da = digit(s[3]) else { return nil }
        var lon = -180 + fl * 20 + dl * 2, lat = -90 + fa * 10 + da
        var w = 2.0, h = 1.0                                                          // rozměr aktuálního čtverce
        if s.count >= 6 {
            guard let sl = letter(s[4], upTo: 88), let sa = letter(s[5], upTo: 88) else { return nil }   // A–X
            lon += sl * (5.0 / 60); lat += sa * (2.5 / 60)
            w = 5.0 / 60; h = 2.5 / 60
        }
        if s.count == 8 {
            guard let el = digit(s[6]), let ea = digit(s[7]) else { return nil }
            lon += el * (w / 10); lat += ea * (h / 10)
            w /= 10; h /= 10
        }
        return Coordinate(lat: lat + h / 2, lon: lon + w / 2)
    }

    // MARK: Vzdálenost a azimut

    /// Velkokružnicová vzdálenost (haversine) v km, krátká cesta.
    public static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180
        let dp = p2 - p1, dl = (b.lon - a.lon) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Počáteční azimut z `a` do `b` ve stupních 0..<360 (0 = sever); pro totožné body 0.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let p1 = a.lat * .pi / 180, p2 = b.lat * .pi / 180, dl = (b.lon - a.lon) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        if abs(x) < 1e-12 && abs(y) < 1e-12 { return 0 }
        return normalize(atan2(y, x) * 180 / .pi)
    }

    static func normalize(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d >= 360 ? 0 : d
    }

    public static func beam(from a: Coordinate, to b: Coordinate, ownSource: Source = .locator,
                            remoteSource: Source = .locator) -> Beam {
        let d = distanceKm(a, b), az = bearing(from: a, to: b)
        return Beam(shortAzimuth: az, shortKm: d, longAzimuth: normalize(az + 180), longKm: circumferenceKm - d,
                    ownSource: ownSource, remoteSource: remoteSource)
    }

    public static func beam(own: Position, remote: Position) -> Beam {
        beam(from: own.coordinate, to: remote.coordinate, ownSource: own.source, remoteSource: remote.source)
    }

    // MARK: Výběr zdroje polohy

    /// Poloha stanice: platný lokátor má přednost, jinak střed země DXCC (souřadnice z cty.dat, východ kladně).
    public static func position(locator: String, country: CountryInfo?) -> Position? {
        if let c = maidenhead(locator) { return Position(coordinate: c, source: .locator) }
        guard let country else { return nil }
        return Position(coordinate: Coordinate(lat: country.latitude, lon: country.longitude), source: .country)
    }

    /// Vzdálenost v km s mezerou po tisících (`1 234`), zaokrouhleno na celé km.
    public static func formatKm(_ km: Double) -> String {
        let n = Int(km.rounded())
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}

/// Zadání frekvence v kHz z textu (horní lišta).
public enum FrequencyInput {
    public static let rangeKHz = 100.0...500_000.0

    /// „14080“, „14080,5“, „14080.5 kHz“, „14.08 MHz“ → kHz; mimo rozsah 100 kHz – 500 MHz nebo nesmysl → nil.
    public static func parseKHz(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var mult = 1.0
        if t.hasSuffix("mhz") { t.removeLast(3); mult = 1000 }
        else if t.hasSuffix("khz") { t.removeLast(3) }
        t = t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              t.filter({ $0 == "." }).count <= 1, let v = Double(t) else { return nil }
        let k = v * mult
        return rangeKHz.contains(k) ? k : nil
    }
}
