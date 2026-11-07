#if DEBUG
import AppKit
import Sparkle

private final class UpdaterProbeDelegate: NSObject, SPUUpdaterDelegate {
    var loaded = false
    var failure: Error?
    var versions: [String] = []

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        versions = appcast.items.map(\.versionString)
        loaded = true
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if !loaded { failure = error }
    }
}

func runUpdaterProbe() -> Int32 {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let delegate = UpdaterProbeDelegate()
    let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
    do { try controller.updater.start() }
    catch { print("Updater configuration failed: \(error)"); return 1 }
    controller.updater.checkForUpdateInformation()
    let deadline = Date(timeIntervalSinceNow: 25)
    while !delegate.loaded, delegate.failure == nil, Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    if let error = delegate.failure { print("Signed update feed failed: \(error)"); return 1 }
    guard delegate.loaded, !delegate.versions.isEmpty else {
        print("Updater did not load a signed release before the timeout")
        return 1
    }
    print("PASS Sparkle loaded the public signed feed; versions: \(delegate.versions)")
    return 0
}
#endif
