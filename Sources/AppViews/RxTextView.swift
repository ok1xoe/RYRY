// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Settings
import SwiftUI

/// Okno přijatého textu: NSTextView s inkrementálním přidáváním, echo jinou barvou, klik na slovo → QSO pole.
struct RxTextView: NSViewRepresentable {
    @Bindable var model: AppModel

    final class ClickTextView: NSTextView {
        var onWord: ((String) -> Void)?
        /// Slovo se vloží jen po jednoduchém kliknutí bez tažení (výběr textu pole nepřepisuje).
        override func mouseDown(with event: NSEvent) {
            let down = event.locationInWindow
            super.mouseDown(with: event)             // sleduje tažení až do uvolnění tlačítka
            guard event.clickCount == 1, selectedRange().length == 0 else { return }
            let up = window?.mouseLocationOutsideOfEventStream ?? down
            guard hypot(up.x - down.x, up.y - down.y) < 4 else { return }
            let p = convert(down, from: nil)
            let i = characterIndexForInsertion(at: p)
            guard i < (textStorage?.length ?? 0) else { return }
            let r = selectionRange(forProposedRange: NSRange(location: i, length: 0), granularity: .selectByWord)
            if let s = textStorage?.string, let rr = Range(r, in: s) {
                let w = String(s[rr]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !w.isEmpty { onWord?(w) }
            }
        }
    }

    final class Coordinator {
        var appended = 0
        var trimmed = 0
        var style: Style?
        var highlightVersion = -1
    }

    /// Značka v textu vysílání (echo) – zvýraznění ji přeskakuje.
    static let echoKey = NSAttributedString.Key("cz.ok1xoe.mmtty4mac.echo")
    /// Kolik posledních znaků se přestyluje při změně stavu (zalogování, změna pásma).
    static let restyleTail = 5000

    /// Vzhled okna příjmu (písmo, barvy) – změna vede k přestylování celého obsahu.
    struct Style: Equatable {
        var size: Double, font: String, text: String?, echo: String?, background: String?, highlight: Bool
        init(_ d: DisplaySettings) {
            size = d.fontSize; font = d.rxFont; text = d.rxTextColor; echo = d.rxEchoColor; background = d.rxBackground
            highlight = d.highlightCalls
        }
        /// Atributy zvýrazněné značky: vlastní červeně tučně, duplicita šedě přeškrtnutě, v logu modře, nová tučně.
        func decorate(_ a: inout [NSAttributedString.Key: Any], _ s: CallStyle, bold: NSFont) {
            switch s {
            case .own: a[.foregroundColor] = NSColor.systemRed; a[.font] = bold
            case .dupe: a[.foregroundColor] = NSColor.systemGray; a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case .worked: a[.foregroundColor] = NSColor.systemBlue
            case .new: a[.font] = bold
            }
        }
        var nsFont: NSFont {
            if !font.isEmpty, let f = NSFont(name: font, size: size) { return f }
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        func attrs(echo isEcho: Bool) -> [NSAttributedString.Key: Any] {
            let c = isEcho ? (Color(hex: echo).map(NSColor.init) ?? .systemRed) : (Color(hex: text).map(NSColor.init) ?? .textColor)
            var a: [NSAttributedString.Key: Any] = [.font: nsFont, .foregroundColor: c]
            if isEcho { a[RxTextView.echoKey] = true }
            return a
        }
        var backgroundColor: NSColor { Color(hex: background).map(NSColor.init) ?? .textBackgroundColor }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ClickTextView.scrollableTextView()
        let tv = ClickTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = Style(model.settings.display).nsFont
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.onWord = { [model] w in Task { @MainActor in await model.insertWord(w) } }
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        return scroll
    }

    /// Obarví značky ve slovech od pozice `from` (mimo echo). Ostatní slova dostanou základní styl,
    /// takže se dřívější zvýraznění při změně stavu správně vrátí.
    func applyHighlight(_ storage: NSTextStorage, from: Int, style: Style) {
        let ns = storage.mutableString
        guard from < ns.length else { return }
        let bold = NSFontManager.shared.convert(style.nsFont, toHaveTrait: .boldFontMask)
        for r in CallHighlight.wordRanges(in: ns, range: NSRange(location: from, length: ns.length - from)) {
            if storage.attribute(Self.echoKey, at: r.location, effectiveRange: nil) != nil { continue }
            var a = style.attrs(echo: false)
            if let cs = model.callStyle(for: ns.substring(with: r)) { style.decorate(&a, cs, bold: bold) }
            storage.setAttributes(a, range: r)
        }
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, let storage = tv.textStorage else { return }
        let c = context.coordinator
        let atBottom = scroll.contentView.bounds.maxY >= (tv.frame.height - 30)
        let newChars = model.rxAppendedTotal - c.appended
        let cut = model.rxTrimmedTotal - c.trimmed
        let style = Style(model.settings.display)
        if style != c.style { tv.backgroundColor = style.backgroundColor; tv.insertionPointColor = style.attrs(echo: false)[.foregroundColor] as? NSColor ?? .textColor }
        let hv = model.highlightVersion
        var restyleFrom: Int?
        storage.beginEditing()
        if newChars >= model.rxCharCount || newChars < 0 || cut < 0 || style != c.style {
            c.style = style
            // velká změna (start, clear) → celé znovu
            let s = NSMutableAttributedString()
            for r in model.rxRuns { s.append(NSAttributedString(string: r.text, attributes: style.attrs(echo: r.echo))) }
            storage.setAttributedString(s)
            restyleFrom = max(0, storage.length - Self.restyleTail)
        } else {
            if cut > 0 {       // ořez zepředu (limit 200 000 znaků)
                let n = (storage.string.utf16.count > 0) ? NSRange(storage.string.startIndex..<storage.string.index(storage.string.startIndex, offsetBy: min(cut, storage.string.count)), in: storage.string) : NSRange(location: 0, length: 0)
                storage.deleteCharacters(in: n)
            }
            let oldLength = storage.length
            for r in model.rxTail(newChars) {
                storage.append(NSAttributedString(string: r.text, attributes: style.attrs(echo: r.echo)))
            }
            // navazuje-li přidaný text na neúplné slovo, přestylovat i to (slovo rozdělené mezi dvě přidání)
            if newChars > 0 { restyleFrom = CallHighlight.restyleStart(in: storage.mutableString, appendedAt: oldLength) }
            if hv != c.highlightVersion {         // změna stavu (log, pásmo) → přestylovat konec textu
                restyleFrom = min(restyleFrom ?? Int.max, max(0, storage.length - Self.restyleTail))
            }
        }
        if style.highlight, let from = restyleFrom { applyHighlight(storage, from: from, style: style) }
        storage.endEditing()
        c.highlightVersion = hv
        c.appended = model.rxAppendedTotal
        c.trimmed = model.rxTrimmedTotal
        if atBottom { tv.scrollToEndOfDocument(nil) }
    }
}
