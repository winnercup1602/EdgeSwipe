import AppKit

#if DEBUG
if CommandLine.arguments.contains("--probe") {
    exit(runHardwareProbe(roundTrip: CommandLine.arguments.contains("--round-trip")))
}
#endif

let app = NSApplication.shared
let delegate = EdgeSwipeApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
