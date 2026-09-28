import Foundation
import Testing
@testable import XMLRPC

let allTypes: [XMLRPCValue] = [
    .int(-42), .bool(true), .bool(false), .string("A & B <C> \"q\""), .double(14070000.5),
    .base64(Data([0, 1, 2, 255])), .array([.int(1), .string("x")]),
    .dict(["freq": .double(7040000), "mode": .string("USB")]), .nil_,
]

@Test func callRoundTrip() throws {
    let data = XMLRPCCodec.encodeCall(method: "main.set_frequency", params: allTypes)
    let (m, p) = try XMLRPCCodec.decodeCall(data)
    #expect(m == "main.set_frequency")
    #expect(p == allTypes)
}

@Test func responseRoundTrip() throws {
    for v in allTypes {
        #expect(try XMLRPCCodec.decodeResponse(XMLRPCCodec.encodeResponse(v)) == v)
    }
}

@Test func untypedValueIsString() throws {
    let xml = "<?xml version=\"1.0\"?><methodResponse><params><param><value>14070000</value></param></params></methodResponse>"
    #expect(try XMLRPCCodec.decodeResponse(Data(xml.utf8)) == .string("14070000"))
}

@Test func i4AndWhitespace() throws {
    let xml = """
    <?xml version="1.0"?>
    <methodResponse>
      <params>
        <param>
          <value><i4> 7 </i4></value>
        </param>
      </params>
    </methodResponse>
    """
    #expect(try XMLRPCCodec.decodeResponse(Data(xml.utf8)) == .int(7))
}

@Test func faultIsThrown() throws {
    let data = XMLRPCCodec.encodeFault(XMLRPCFault(code: 4, message: "Too many parameters"))
    #expect(throws: XMLRPCFault(code: 4, message: "Too many parameters")) {
        try XMLRPCCodec.decodeResponse(data)
    }
}

@Test func malformedIsRejected() {
    #expect(throws: XMLRPCCodecError.self) { try XMLRPCCodec.decodeResponse(Data("<methodResponse><params>".utf8)) }
    #expect(throws: XMLRPCCodecError.self) { try XMLRPCCodec.decodeCall(Data("garbage".utf8)) }
    #expect(throws: XMLRPCCodecError.self) {
        try XMLRPCCodec.decodeResponse(Data("<methodResponse><params><param><value><int>abc</int></value></param></params></methodResponse>".utf8))
    }
}

@Test func callWithoutParams() throws {
    let xml = "<?xml version=\"1.0\"?><methodCall><methodName>fldigi.name</methodName></methodCall>"
    let (m, p) = try XMLRPCCodec.decodeCall(Data(xml.utf8))
    #expect(m == "fldigi.name" && p.isEmpty)
}
