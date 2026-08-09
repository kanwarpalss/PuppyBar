import AppKit
import PuppyBarCore

// `PuppyBar --dump` prints exactly what the menu would show, then exits.
// Useful for checking things without hunting for the paw in the menu bar,
// and it renders from the same MenuText source as the real menu. (ARCH-04)
if CommandLine.arguments.contains("--dump") {
    Diagnostics.dumpAndExit()
}

// `PuppyBar --paw <path.png>` writes the paw icon out so it can be eyeballed.
if let index = CommandLine.arguments.firstIndex(of: "--paw"),
   index + 1 < CommandLine.arguments.count {
    let size = (index + 2 < CommandLine.arguments.count)
        ? (Double(CommandLine.arguments[index + 2]).map { CGFloat($0) } ?? 256)
        : 256
    Diagnostics.writePaw(to: CommandLine.arguments[index + 1], size: size)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, no app menu. (Also set via LSUIElement in Info.plist.)
app.setActivationPolicy(.accessory)
app.run()
