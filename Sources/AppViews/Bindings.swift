// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import ModemKit
import SwiftUI

@MainActor
extension AppModel {
    func boolBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { if case .bool(let b)? = self.param(id) { return b }; return false },
                set: { v in Task { await self.setParam(id, .bool(v)) } })
    }
    func choiceBinding(_ id: String) -> Binding<String> {
        Binding(get: { if case .string(let s)? = self.param(id) { return s }; return "" },
                set: { v in Task { await self.setParam(id, .string(v)) } })
    }
    func doubleBinding(_ id: String) -> Binding<Double> {
        Binding(get: { if case .double(let d)? = self.param(id) { return d }; return 0 },
                set: { v in Task { await self.setParam(id, .double(v)) } })
    }
    func qsoBinding(_ name: String) -> Binding<String> {
        Binding(get: { self.qso.value(name) ?? "" },
                set: { v in Task { await self.setQSOField(name, v) } })
    }
}
