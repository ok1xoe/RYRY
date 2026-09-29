// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Engine
import Foundation
import ModemKit
import QSOLog

extension JSONRPCServer {
    private func str(_ p: [String: Any], _ k: String) throws -> String {
        guard let v = p[k] as? String else { throw RPCError.params("chybí '\(k)' (string)") }; return v
    }
    private func num(_ p: [String: Any], _ k: String) throws -> Double {
        guard let v = p[k] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() else { throw RPCError.params("chybí '\(k)' (number)") }
        return v.doubleValue
    }
    private func int(_ p: [String: Any], _ k: String) throws -> Int {
        guard let i = Int(exactly: try num(p, k).rounded(.towardZero)) else { throw RPCError.params("'\(k)' mimo rozsah") }
        return i
    }

    private func txCall(_ f: () async throws -> Void) async throws {
        do { try await f() } catch { throw RPCError(code: -32001, message: "TX odmítnuto: \(error)") }
    }

    func dispatch(_ m: String, _ p: [String: Any], _ s: ClientSession) async throws -> Any {
        let engine = app.engine
        switch m {
        // engine
        case "engine.status":
            return ["state": (await engine.state).rawValue, "tuning": await engine.isTuning,
                    "txPending": await engine.txPending, "mode": (await engine.currentMode()).id,
                    "rig": Self.rigJSON(await engine.rigStatus)] as [String: Any]
        case "engine.tx": try await txCall { try await app.tx() }; s.startedTx = true; return true
        case "engine.tune": try await txCall { try await app.tune() }; s.startedTx = true; return true
        case "engine.rx": await app.rx(); return true
        case "engine.rxNow": await app.rxNow(); return true
        // tx
        case "tx.send": await app.send(text: try str(p, "text")); return true
        case "tx.sendRaw":
            guard let codes = p["codes"] as? [NSNumber] else { throw RPCError.params("chybí 'codes' (array)") }
            await engine.sendRaw(codes.map { UInt8(truncatingIfNeeded: $0.intValue) }); return true
        case "tx.clear": await app.clearTx(); return true
        case "tx.pending": return await engine.txPending
        // modem
        case "modem.list":
            let modes = await engine.modes().map { ["id": $0.id, "name": $0.displayName, "adif": $0.adifMode] }
            return [["id": "rtty", "modes": modes, "current": (await engine.currentMode()).id] as [String: Any]]
        case "modem.select":
            do { try await engine.selectMode(try str(p, "mode")) } catch let e as RPCError { throw e } catch { throw RPCError.params("\(error)") }
            return true
        case "modem.getParams": return (await app.modemParams()).mapValues(Self.toJSON)
        case "modem.setParams":
            guard let ps = p["params"] as? [String: Any] else { throw RPCError.params("chybí 'params' (object)") }
            for (k, v) in ps.sorted(by: { $0.key < $1.key }) {
                guard let pv = Self.fromJSON(v) else { throw RPCError.params("\(k): neplatný typ") }
                do { try await app.setModemParam(k, pv) } catch { throw RPCError(code: -32602, message: "\(k): \(error)") }
            }
            return (await app.modemParams()).mapValues(Self.toJSON)
        case "modem.describeParams": return await engine.parameterDescriptors().map(Self.descriptorJSON)
        // profily
        case "profile.list":
            return await app.profileList().enumerated().map { i, pr in ["slot": i, "name": pr?.name ?? NSNull()] as [String: Any] }
        case "profile.load":
            do { try await app.loadProfile(try int(p, "slot")) } catch let e as RPCError { throw e } catch { throw RPCError.params("\(error)") }
            return true
        case "profile.save":
            do { try await app.saveProfile(try int(p, "slot"), name: try str(p, "name")) } catch let e as RPCError { throw e } catch { throw RPCError.params("\(error)") }
            return true
        case "profile.delete":
            do { try await app.deleteProfile(try int(p, "slot")) } catch let e as RPCError { throw e } catch { throw RPCError.params("\(error)") }
            return true
        // rig
        case "rig.status": return Self.rigJSON(await engine.rigStatus)
        case "rig.getFreq": return (await engine.rigStatus?.frequency) as Any? ?? NSNull()
        case "rig.setFreq":
            let hz = try num(p, "hz")
            guard hz.isFinite, hz > 0 else { throw RPCError.params("hz > 0") }
            do { try await app.setFrequency(hz) } catch { throw RPCError(code: -32002, message: "rig: \(error)") }
            return true
        case "rig.setMode":
            do { try await app.setRigMode(try str(p, "mode")) } catch let e as RPCError { throw e } catch { throw RPCError(code: -32002, message: "rig: \(error)") }
            return true
        // makra
        case "macro.list":
            return await app.settings.macros.enumerated().map { ["index": $0, "name": $1.name, "text": $1.text] as [String: Any] }
        case "macro.run":
            let i = try int(p, "index")
            do { try await app.runMacro(index: i) } catch AppError.badMacro(let n) { throw RPCError.params("makro \(n) neexistuje") }
            catch { throw RPCError(code: -32001, message: "TX odmítnuto: \(error)") }
            s.startedTx = true
            return true
        case "macro.stop": await app.stopMacroRepeat(); return true
        // QSO okno
        case "qso.getCurrent": return Self.encodable(await app.qso)
        case "qso.setField":
            do { try await app.setQSOField(try str(p, "name"), try str(p, "value")) } catch let e as RPCError { throw e } catch { throw RPCError.params("\(error)") }
            return Self.encodable(await app.qso)
        case "qso.clear": await app.clearQSO(); return true
        case "qso.log":
            do { return Self.recordJSON(try await app.logQSO()) } catch { throw RPCError(code: -32003, message: "\(error)") }
        // log
        case "log.query":
            guard let log = app.log else { throw RPCError(code: -32003, message: "log není k dispozici") }
            let from = (p["from"] as? String).flatMap(Self.iso.date(from:))
            let to = (p["to"] as? String).flatMap(Self.iso.date(from:))
            let recs = await log.query(call: p["call"] as? String, from: from, to: to, limit: (p["limit"] as? NSNumber)?.intValue)
            return recs.map(Self.recordJSON)
        case "log.update":
            var obj: Any? = p["record"]
            if obj == nil, let idS = p["id"] as? String, let fields = p["fields"] as? [String: Any] {
                // {id, fields}: sloučit se stávajícím záznamem
                guard let log = app.log, let id = UUID(uuidString: idS),
                      let cur = await log.records.first(where: { $0.id == id }),
                      var base = Self.recordJSON(cur) as? [String: Any] else { throw RPCError(code: -32003, message: "záznam nenalezen") }
                for (k, v) in fields { base[k] = v }
                base.removeValue(forKey: "band")
                obj = base
            }
            guard let obj, let d = try? JSONSerialization.data(withJSONObject: obj) else { throw RPCError.params("chybí 'record' nebo {id, fields}") }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            guard let r = try? dec.decode(QSORecord.self, from: d) else { throw RPCError.params("neplatný záznam") }
            do { try await app.updateQSO(r) } catch { throw RPCError(code: -32003, message: "\(error)") }
            return true
        case "log.delete":
            guard let id = UUID(uuidString: try str(p, "id")) else { throw RPCError.params("neplatné id") }
            do { try await app.deleteQSO(id) } catch { throw RPCError(code: -32003, message: "\(error)") }
            return true
        // spektrum
        case "spectrum.get":
            guard let f = await engine.spectrum() else { return NSNull() }
            return Self.spectrumJSON(f, bins: (p["bins"] as? NSNumber)?.intValue)
        case "spectrum.stream":
            let fps = min(20, max(1, (p["fps"] as? NSNumber)?.doubleValue ?? 10))
            let bins = (p["bins"] as? NSNumber)?.intValue
            s.subscribe(["spectrum"])
            s.spectrumTask?.cancel()
            s.spectrumTask = Task { [weak s] in
                while !Task.isCancelled, let s, !s.isClosed {
                    if let f = await engine.spectrum() { s.notify("spectrum", Self.spectrumJSON(f, bins: bins)) }
                    try? await Task.sleep(for: .milliseconds(Int(1000 / fps)))
                }
            }
            return true
        case "spectrum.stopStream": s.spectrumTask?.cancel(); s.unsubscribe(["spectrum"]); return true
        // události
        case "events.subscribe":
            guard let ev = p["events"] as? [String] else { throw RPCError.params("chybí 'events' (array)") }
            s.subscribe(ev); return true
        case "events.unsubscribe":
            guard let ev = p["events"] as? [String] else { throw RPCError.params("chybí 'events' (array)") }
            s.unsubscribe(ev); return true
        default:
            throw RPCError(code: -32601, message: "method not found: \(m)")
        }
    }

    static func spectrumJSON(_ f: SpectrumFrame, bins: Int?) -> [String: Any] {
        var mags = f.magnitudes, binHz = f.binHz
        if let bins, bins > 0, bins < mags.count {
            let step = Double(mags.count) / Double(bins)
            mags = (0..<bins).map { i in
                let lo = Int(Double(i) * step), hi = max(lo + 1, Int(Double(i + 1) * step))
                return mags[lo..<min(hi, mags.count)].max() ?? 0
            }
            binHz *= step
        }
        return ["binHz": binHz, "magnitudes": mags]
    }
}
