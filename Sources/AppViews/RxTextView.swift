// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import SwiftUI

/// Okno přijatého textu: NSTextView s inkrementálním přidáváním, echo jinou barvou, klik na slovo → QSO pole.
struct RxTextView: NSViewRepresentable {
    @Bindable var model: AppModel

    final class ClickTextView: NSTextView {
        var onWord: ((String) -> Void)?
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            let i = characterIndexForInsertion(at: p)
            if i < (textStorage?.length ?? 0) {
                let r = selectionRange(forProposedRange: NSRange(location: i, length: 0), granularity: .selectByWord)
                if let s = textStorage?.string, let rr = Range(r, in: s) {
                    let w = String(s[rr]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !w.isEmpty { onWord?(w) }
                }
            }
            super.mouseDown(with: event)
        }
    }

    final class Coordinator {
        var firstRunId: Int?
        var runCount = 0
        var lastRunLength = 0
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
        let runs = model.rxRuns
        let c = context.coordinator
        let atBottom = scroll.contentView.bounds.maxY >= (tv.frame.height - 30)
        let needsRebuild = runs.first?.id != c.firstRunId || runs.count < c.runCount
        if needsRebuild {
            let s = NSMutableAttributedString()
            for r in runs { s.append(NSAttributedString(string: r.text, attributes: Self.attrs(echo: r.echo))) }
            storage.setAttributedString(s)
        } else if !runs.isEmpty {
            // doplnit konec poslední známé položky a nové položky
            let lastKnown = c.runCount - 1
            if lastKnown >= 0, lastKnown < runs.count {
                let t = runs[lastKnown].text
                if t.count > c.lastRunLength {
                    let add = String(t.suffix(t.count - c.lastRunLength))
                    storage.append(NSAttributedString(string: add, attributes: Self.attrs(echo: runs[lastKnown].echo)))
                }
            }
            for r in runs.dropFirst(max(0, c.runCount)) {
                storage.append(NSAttributedString(string: r.text, attributes: Self.attrs(echo: r.echo)))
            }
        }
        c.firstRunId = runs.first?.id
        c.runCount = runs.count
        c.lastRunLength = runs.last?.text.count ?? 0
        if atBottom || needsRebuild { tv.scrollToEndOfDocument(nil) }
    }
}
