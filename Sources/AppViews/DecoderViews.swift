// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppKit
import AppUI
import Engine
import Localization
import Settings
import SwiftUI

// MARK: Second decoder

/// The second decoder's panel below the receive window (smaller font, clicking a word → QSO as in the main receive window).
struct SecondDecoderPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(L("2. dekodér")).uiFont(.caption, weight: .bold)
                Picker(L("Demodulátor"), selection: demodBinding) {
                    Text(L("auto (%@)", model.secondDemodEffective.uppercased())).tag(String?.none)
                    ForEach(AuxDecoderConfig.demodTypes, id: \.self) { Text($0.uppercased()).tag(String?.some($0)) }
                }
                .labelsHidden().fixedSize()
                .hint(L("Demodulátor druhého dekodéru (auto = jiný než hlavní)"))
                Spacer()
                Button { model.clearRx2() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).hint(L("Vymazat text druhého dekodéru"))
                Button { Task { await model.setSecondDecoder(false) } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).hint(L("Vypnout druhý dekodér"))
            }
            .uiControlSize(-1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.bar)
            AuxTextView(model: model)
        }
    }

    var demodBinding: Binding<String?> {
        Binding(get: { model.settings.decoders.secondDemod },
                set: { v in Task { await model.updateDecoders { $0.secondDemod = v } } })
    }
}

/// The second decoder's text: an NSTextView with incremental appending and clickable words (like RxTextView).
struct AuxTextView: NSViewRepresentable {
    @Bindable var model: AppModel

    final class Coordinator { var appended = 0, trimmed = 0; var style: RxTextView.Style? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func style() -> RxTextView.Style {
        var s = RxTextView.Style(model.settings.display)
        s.size = max(8, s.size - 2)                   // smaller font than the main receive window
        return s
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = RxTextView.ClickTextView.scrollableTextView()
        let tv = RxTextView.ClickTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.textContainerInset = NSSize(width: 6, height: 3)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.onWord = { [model] w in Task { @MainActor in await model.insertWord(w) } }
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, let storage = tv.textStorage else { return }
        let c = context.coordinator
        let atBottom = scroll.contentView.bounds.maxY >= (tv.frame.height - 20)
        let st = style()
        let added = model.rx2AppendedTotal - c.appended
        let cut = model.rx2TrimmedTotal - c.trimmed
        storage.beginEditing()
        if st != c.style || added < 0 || cut < 0 || cut > 0 || added > model.rx2Text.count {
            c.style = st
            tv.backgroundColor = st.backgroundColor
            storage.setAttributedString(NSAttributedString(string: model.rx2Text, attributes: st.attrs(echo: false)))
        } else if added > 0 {
            storage.append(NSAttributedString(string: String(model.rx2Text.suffix(added)), attributes: st.attrs(echo: false)))
        }
        storage.endEditing()
        c.appended = model.rx2AppendedTotal
        c.trimmed = model.rx2TrimmedTotal
        if atBottom { tv.scrollToEndOfDocument(nil) }
    }
}

// MARK: Channels

/// The "Channels" window: independent decoders on the signals found in the waterfall.
public struct ChannelsWindow: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle(L("Vícekanálové dekódování"), isOn: Binding(get: { model.settings.decoders.channelsEnabled },
                                                                   set: { v in Task { await model.setChannelDecoding(v) } }))
                Stepper(L("Max. kanálů: %ld", model.settings.decoders.maxChannels),
                        value: Binding(get: { model.settings.decoders.maxChannels },
                                       set: { v in Task { await model.updateDecoders { $0.maxChannels = v } } }),
                        in: DecoderSettings.channelRange)
                .fixedSize()
                Toggle(L("Značky ve vodopádu"), isOn: Binding(get: { model.settings.decoders.showChannelMarks },
                                                             set: { v in Task { await model.updateDecoders { $0.showChannelMarks = v } } }))
                Spacer()
            }
            .uiControlSize(-1)
            .padding(8)
            Divider()
            if !model.settings.decoders.channelsEnabled {
                ContentUnavailableView(L("Vícekanálové dekódování je vypnuté"), systemImage: "square.stack.3d.down.right",
                                       description: Text(L("Zapněte ho přepínačem nahoře – dekodéry se samy naladí na RTTY signály ve vodopádu.")))
            } else if model.decoderChannels.isEmpty {
                ContentUnavailableView(L("Žádný signál"), systemImage: "waveform.slash",
                                       description: Text(L("Hledají se dvojice tónů vzdálené o shift nad šumem.")))
            } else {
                List(Array(model.decoderChannels.enumerated()), id: \.element.id) { i, ch in
                    ChannelRow(model: model, index: i + 1, channel: ch)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .top)
    }
}

struct ChannelRow: View {
    @Bindable var model: AppModel
    let index: Int
    let channel: DecoderChannel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(index)").uiFont(.caption, weight: .bold).foregroundStyle(.green).frame(width: 14)
            Text(String(format: "%.0f Hz", channel.mark)).uiFont(.body, digits: true).frame(width: 70, alignment: .trailing)
            Text(Self.clickable(channel.text))
                .uiFont(.body, design: .monospaced)
                .lineLimit(2).truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tint(.primary)
                .environment(\.openURL, OpenURLAction { url in
                    if let w = Self.word(from: url) { Task { await model.insertWord(w) } }
                    return .handled
                })
                .hint(L("Klik na slovo = vložit do QSO"))
            Button(L("Naladit")) { Task { await model.tuneChannel(channel.id) } }
                .uiControlSize(-1)
                .hint(L("Přeladit hlavní dekodér na tento signál"))
        }
        .contentShape(Rectangle())
    }

    static let scheme = "ryry-word"

    /// Text in which every word is a link (click → the word is put into the QSO panel).
    static func clickable(_ text: String) -> AttributedString {
        var out = AttributedString()
        let flat = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            var a = AttributedString(word)
            var comps = URLComponents(); comps.scheme = scheme; comps.host = "w"; comps.queryItems = [URLQueryItem(name: "t", value: word)]
            a.link = comps.url
            out += a; word = ""
        }
        for ch in flat {
            if ch == " " { flush(); out += AttributedString(" ") } else { word.append(ch) }
        }
        flush()
        return out
    }

    static func word(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "t" }?.value
    }
}

/// Channel markers in the waterfall: short green ticks at mark and space plus the channel number.
@MainActor func drawChannelMarks(_ ctx: GraphicsContext, _ size: CGSize, _ model: AppModel) {
    let d = model.settings.decoders
    guard d.channelsEnabled, d.showChannelMarks, !model.decoderChannels.isEmpty else { return }
    let span = model.waterfallToHz - model.waterfallFromHz
    guard span > 0 else { return }
    let shift = model.space - model.mark
    func x(_ hz: Double) -> CGFloat { CGFloat((hz - model.waterfallFromHz) / span) * size.width }
    for (i, ch) in model.decoderChannels.enumerated() {
        let xm = x(ch.mark), xs = x(ch.mark + shift)
        var p = Path()
        p.move(to: CGPoint(x: xm, y: size.height)); p.addLine(to: CGPoint(x: xm, y: size.height - 10))
        p.move(to: CGPoint(x: xs, y: size.height)); p.addLine(to: CGPoint(x: xs, y: size.height - 10))
        ctx.stroke(p, with: .color(.green.opacity(0.9)), lineWidth: 1.5)
        ctx.draw(Text(verbatim: "\(i + 1)").font(.caption2.bold()).foregroundStyle(.green),
                 at: CGPoint(x: (xm + xs) / 2, y: size.height - 16))
    }
}

// MARK: Settings

struct DecodersTab: View {
    @Binding var s: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(L("Zapnout druhý dekodér"), isOn: $s.decoders.secondEnabled)
                Picker(L("Demodulátor"), selection: $s.decoders.secondDemod) {
                    Text(L("automaticky jiný než hlavní")).tag(String?.none)
                    ForEach(AuxDecoderConfig.demodTypes, id: \.self) { Text($0.uppercased()).tag(String?.some($0)) }
                }
            } header: { Text(L("Druhý dekodér")) } footer: {
                Text(L("Druhý dekodér přijímá na stejném naladění jako hlavní, ale jiným demodulátorem (bez vlastního AFC). Jen příjem."))
            }
            Section {
                Toggle(L("Zapnout vícekanálové dekódování"), isOn: $s.decoders.channelsEnabled)
                NumberRow(title: L("Max. počet kanálů"), value: $s.decoders.maxChannels, range: DecoderSettings.channelRange)
                LabeledContent(L("Kanál zaniká po")) {
                    HStack(spacing: 4) {
                        TextField("", value: $s.decoders.channelTimeoutS, format: .number.precision(.fractionLength(0)))
                            .multilineTextAlignment(.trailing).frame(width: 70)
                        Text("s").foregroundStyle(.secondary)
                        Stepper("", value: $s.decoders.channelTimeoutS, in: DecoderSettings.timeoutRange, step: 5).labelsHidden()
                    }
                }
                Toggle(L("Značky kanálů ve vodopádu"), isOn: $s.decoders.showChannelMarks)
            } header: { Text(L("Vícekanálové dekódování")) } footer: {
                Text(L("Každý kanál je samostatný dekodér (s AFC) na RTTY signálu nalezeném ve spektru. Seznam v okně Kanály."))
            }
        }
        .formStyle(.grouped)
    }
}
