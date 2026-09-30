/// Generic modem interface (RTTY now, later PSK from MMVARI, SSTV from MMSSTV).
///
/// Threading: all methods are called from one serial context (Engine). `events` is an AsyncStream
/// with a single subscriber (Engine), which forwards the events onward.
public protocol Modem: AnyObject {
    static var id: String { get }
    /// The modes the modem supports.
    var modes: [ModeDescriptor] { get }
    var currentMode: ModeDescriptor { get }
    /// The modem's working sample rate (AudioIO converts from/to the device rate).
    var sampleRate: Double { get }
    var capabilities: ModemCapabilities { get }
    /// A description of all parameters (for the GUI and the API).
    var parameters: [ParameterDescriptor] { get }
    /// The stream of events (received text, signal level, tuning…).
    var events: AsyncStream<ModemEvent> { get }

    func select(mode: ModeDescriptor) throws
    func set(parameter id: String, value: ParameterValue) throws
    func get(parameter id: String) -> ParameterValue?

    /// Processes a block of received samples (±1.0) at `sampleRate`.
    func processRx(_ samples: UnsafeBufferPointer<Float>)
    /// Starts transmitting; `tune` = carrier only.
    func beginTx(tune: Bool)
    /// Appends text to the transmit queue.
    func queueTx(text: String)
    /// Appends raw modem codes (RTTY: Baudot in MMTTY order and control 0xFC–0xFF) – in the same order as the text.
    func queueTxRaw(_ codes: [UInt8])
    /// Generates the transmit samples; `.finished` once the transmission ended (the rest of the buffer is silence).
    func generateTx(into buffer: UnsafeMutableBufferPointer<Float>) -> TxStatus
    /// Finishes the character in progress and discards the rest of the queue; then `generateTx` returns `.finished`.
    func stopTx()
    /// Ends the transmission immediately.
    func abortTx()
    /// The amount of data waiting to be transmitted (RTTY: text bytes in the modem queue + Baudot codes in the core).
    /// The units are not uniform – only a comparison with zero is reliable (everything transmitted).
    var txPending: Int { get }
    /// The latest spectrum for the waterfall and AFC.
    func spectrum() -> SpectrumFrame?
    /// The codes the modulator has started transmitting (for the FSK keyer); modems without FSK return [].
    func takeFskCodes() -> [UInt8]
    /// Finishes the `events` stream (after pending events are delivered). The modem then reports nothing more.
    func finishEvents()
    /// XY scope: enable collection and read batches of points (modems without XY return nil).
    func setXYScope(_ on: Bool)
    func xyScope() -> [XYPoint]?
    /// Demodulator scope (tuning): enable collection and read completed batches (all sources).
    func setDemodScope(_ on: Bool)
    func demodScope() -> DemodScope?
    /// Notch at a frequency (right button in the spectrum, as in MMTTY); modems without a notch do nothing.
    func notchClick(hz: Double)
}

public extension Modem {
    func takeFskCodes() -> [UInt8] { [] }
    func queueTxRaw(_ codes: [UInt8]) {}
    func setXYScope(_ on: Bool) {}
    func xyScope() -> [XYPoint]? { nil }
    func notchClick(hz: Double) {}
    func setDemodScope(_ on: Bool) {}
    func demodScope() -> DemodScope? { nil }
}
