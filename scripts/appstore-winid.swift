// Vypíše ID okna aplikace podle části názvu (pro screencapture -l). Použití: swift appstore-winid.swift <proces> <název>
import CoreGraphics
import Foundation
let owner = CommandLine.arguments[1], title = CommandLine.arguments[2]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == owner && (w[kCGWindowLayer as String] as? Int) == 0 {
    if ((w[kCGWindowName as String] as? String) ?? "").contains(title) { print(w[kCGWindowNumber as String]!); exit(0) }
}
exit(1)
