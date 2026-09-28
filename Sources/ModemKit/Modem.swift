/// Obecné rozhraní modemu (RTTY teď, později PSK z MMVARI, SSTV z MMSSTV).
///
/// Vlákna: všechny metody volá jeden sériový kontext (Engine). `events` je AsyncStream
/// s jediným odběratelem (Engine), který události dále rozesílá.
public protocol Modem: AnyObject {
    static var id: String { get }
    /// Módy, které modem umí.
    var modes: [ModeDescriptor] { get }
    var currentMode: ModeDescriptor { get }
    /// Pracovní vzorkovací frekvence modemu (AudioIO převádí ze/do frekvence zařízení).
    var sampleRate: Double { get }
    var capabilities: ModemCapabilities { get }
    /// Popis všech parametrů (pro GUI a API).
    var parameters: [ParameterDescriptor] { get }
    /// Proud událostí (přijatý text, úroveň signálu, doladění…).
    var events: AsyncStream<ModemEvent> { get }

    func select(mode: ModeDescriptor) throws
    func set(parameter id: String, value: ParameterValue) throws
    func get(parameter id: String) -> ParameterValue?

    /// Zpracuje blok přijatých vzorků (±1.0) na `sampleRate`.
    func processRx(_ samples: UnsafeBufferPointer<Float>)
    /// Zahájí vysílání; `tune` = jen nosná.
    func beginTx(tune: Bool)
    /// Přidá text do vysílací fronty.
    func queueTx(text: String)
    /// Vygeneruje vysílané vzorky; `.finished`, když vysílání skončilo (zbytek bufferu je ticho).
    func generateTx(into buffer: UnsafeMutableBufferPointer<Float>) -> TxStatus
    /// Dovysílá rozpracovaný znak, zbytek fronty zahodí; pak `generateTx` vrátí `.finished`.
    func stopTx()
    /// Okamžitě ukončí vysílání.
    func abortTx()
    /// Počet znaků/kódů čekajících na odvysílání (fronta modemu + jádro).
    var txPending: Int { get }
    /// Poslední spektrum pro vodopád a AFC.
    func spectrum() -> SpectrumFrame?
    /// Kódy, které modulátor začal vysílat (pro FSK klíčovač); modemy bez FSK vrací [].
    func takeFskCodes() -> [UInt8]
    /// Ukončí proud `events` (po doručení čekajících událostí). Modem pak už nic nehlásí.
    func finishEvents()
}

public extension Modem {
    func takeFskCodes() -> [UInt8] { [] }
}
