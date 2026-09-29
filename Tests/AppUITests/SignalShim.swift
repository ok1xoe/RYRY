import RTTYSignalKit
enum RTTYSignalGeneratorShim { static func signal() -> [Float] { RTTYSignalGenerator().generate(text: "RYRYRYRY", leadIn: 0.5) } }
