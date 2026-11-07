import AppKit

#if DEBUG
if CommandLine.arguments.contains("--probe-updater") { exit(runUpdaterProbe()) }
if CommandLine.arguments.contains("--self-test") { exit(runAppSelfTests()) }
if CommandLine.arguments.contains("--probe") {
    exit(runHardwareProbe(roundTrip: CommandLine.arguments.contains("--round-trip")))
}
#endif

let app = NSApplication.shared
let delegate = EdgeSwipeApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
