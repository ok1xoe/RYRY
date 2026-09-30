import Foundation
import Testing
@testable import MacroEngine

@Test func clusterMacroExpandsVariablesAndFrequency() {
    var c = ctx(); c.rigKHz = 14083.25
    #expect(MacroEngine.expandCluster("dx %k %c RTTY", context: c) == ["dx 14083.2 DL1ABC RTTY"])
    #expect(MacroEngine.expandCluster("ann/full %m QRV %t", context: c) == ["ann/full OK1XOE QRV 1413"])
    c.rigKHz = nil
    #expect(MacroEngine.expandCluster("dx %k %c", context: c) == ["dx  DL1ABC"])     // an unknown frequency = nothing
}

@Test func clusterMacroMultipleLinesBecomeMultipleCommands() {
    #expect(MacroEngine.expandCluster("sh/wwv\r\n\r\n  sh/sun  \nsh/dx 5\r", context: ctx()) == ["sh/wwv", "sh/sun", "sh/dx 5"])
    #expect(MacroEngine.expandCluster("", context: ctx()).isEmpty)
    #expect(MacroEngine.expandCluster("\r\n  \r\n", context: ctx()).isEmpty)
}

@Test func clusterMacroIgnoresControlCharactersOfTransmitMacros() {
    #expect(MacroEngine.expandCluster("sh/dx 30\\", context: ctx()) == ["sh/dx 30"])
    #expect(MacroEngine.expandCluster("#sh/dx 30#", context: ctx()) == ["sh/dx 30"])
    #expect(MacroEngine.expandCluster("\\sh/dx 30\r\n#", context: ctx()) == ["sh/dx 30"])
    // CW ID, LTRS/FIGS and logging never reach the cluster
    #expect(MacroEngine.expandCluster("sh/dx%{DE %m}%L%F%l 30", context: ctx()) == ["sh/dx 30"])
}

@Test func clusterMacroStripsControlCharsAndLimitsLength() {
    #expect(MacroEngine.expandCluster("sh/dx\u{1B}\u{7}\t 30", context: ctx()) == ["sh/dx 30"])
    let long = String(repeating: "a", count: 400)
    #expect(MacroEngine.expandCluster(long, context: ctx())[0].count == MacroEngine.maxClusterLine)
}

@Test func transmitMacroFrequencyVariableIsEmptyWithoutRigContext() {
    #expect(text(MacroEngine.expand("F=%k.", context: ctx())) == "F=.")
}
