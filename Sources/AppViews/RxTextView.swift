// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
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
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ClickTextView.scrollableTextView()
        let tv = ClickTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.onWord = { [model] w in Task { @MainActor in await model.insertWord(w) } }
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        return scroll
    }

    static func attrs(echo: Bool) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
         .foregroundColor: echo ? NSColor.systemRed : NSColor.textColor]
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, let storage = tv.textStorage else { return }
        let c = context.coordinator
        let atBottom = scroll.contentView.bounds.maxY >= (tv.frame.height - 30)
        let newChars = model.rxAppendedTotal - c.appended
        let cut = model.rxTrimmedTotal - c.trimmed
        storage.beginEditing()
        if newChars >= model.rxCharCount || newChars < 0 || cut < 0 {
            // velká změna (start, clear) → celé znovu
            let s = NSMutableAttributedString()
            for r in model.rxRuns { s.append(NSAttributedString(string: r.text, attributes: Self.attrs(echo: r.echo))) }
            storage.setAttributedString(s)
        } else {
            if cut > 0 {       // ořez zepředu (limit 200 000 znaků)
                let n = (storage.string.utf16.count > 0) ? NSRange(storage.string.startIndex..<storage.string.index(storage.string.startIndex, offsetBy: min(cut, storage.string.count)), in: storage.string) : NSRange(location: 0, length: 0)
                storage.deleteCharacters(in: n)
            }
            for r in model.rxTail(newChars) {
                storage.append(NSAttributedString(string: r.text, attributes: Self.attrs(echo: r.echo)))
            }
        }
        storage.endEditing()
        c.appended = model.rxAppendedTotal
        c.trimmed = model.rxTrimmedTotal
        if atBottom { tv.scrollToEndOfDocument(nil) }
    }
}
