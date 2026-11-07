#if DEBUG
import AppKit
import Foundation
import GestureCore

func runAppSelfTests() -> Int32 {
    let suite = "io.github.winnercup1602.edgeswipe.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var failures: Int32 = 0
    func check(_ name: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL") \(name)")
        if !condition { failures += 1 }
    }
    defaults.set(true, forKey: "edgesSwapped")
    defaults.set(true, forKey: "paused")
    let preferences = Preferences(defaults: defaults, hasKeyboardBacklight: true)
    check("legacy side and pause settings migrate", preferences.settings.swapped && preferences.paused && preferences.settings.freezeCursor)
    preferences.settings.precise = true
    preferences.settings.freezeCursor = false
    preferences.settings.bottomQuarterOnly = true
    preferences.settings.threeFingerClick = true
    preferences.settings.width = .wide
    preferences.settings.haptics = .off
    preferences.settings.holdKey = .control
    preferences.settings.holdMode = .toggle
    preferences.settings.top = .scrubVideo
    preferences.settings.bottom = .media
    preferences.settings.corners[.bottomRight] = .screenshot
    preferences.excludedApps = ["org.example.Excluded"]
    preferences.save()
    defaults.synchronize()
    let restored = Preferences(defaults: UserDefaults(suiteName: suite)!, hasKeyboardBacklight: true)
    let s = restored.settings
    check("gesture and excluded-app settings persist", s.swapped && s.precise && !s.freezeCursor
        && s.bottomQuarterOnly && s.threeFingerClick && s.width == .wide && s.haptics == .off
        && s.holdKey == .control && s.holdMode == .toggle && s.top == .scrubVideo && s.bottom == .media
        && s.corners[.bottomRight] == .screenshot && restored.paused && restored.excludedApps == ["org.example.Excluded"])
    restored.reset()
    let reset = Preferences(defaults: defaults, hasKeyboardBacklight: true)
    check("reset clears custom gestures and exclusions", !reset.settings.swapped && !reset.settings.precise
        && reset.settings.freezeCursor && !reset.settings.threeFingerClick && reset.settings.width == .standard
        && reset.settings.haptics == .medium && reset.settings.holdKey == .none && reset.settings.top == .switchApps
        && reset.settings.bottom == .keyboardBrightness && reset.settings.corners.values.allSatisfy { $0 == .off }
        && !reset.paused && reset.excludedApps.isEmpty)
    defaults.removePersistentDomain(forName: suite)
    let unlit = Preferences(defaults: defaults, hasKeyboardBacklight: false)
    check("non-backlit keyboards default to media", unlit.settings.bottom == .media)
    defaults.set("unknown-value", forKey: "edgeWidth")
    defaults.set("unknown-value", forKey: "topAction")
    let invalid = Preferences(defaults: defaults, hasKeyboardBacklight: false)
    check("invalid stored enum values recover to defaults", invalid.settings.width == .standard && invalid.settings.top == .switchApps)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let menuPreferences = Preferences(defaults: defaults, hasKeyboardBacklight: true)
    menuPreferences.reset()
    let builder = MenuController(preferences: menuPreferences, keyboardAvailable: true)
    builder.onSettings = { menuPreferences.settings = $0; menuPreferences.save() }
    let context = MenuContext(status: "test", currentApp: nil, permissionGranted: false,
                              inputMonitoringNeeded: false, statusLines: ["test"])
    func find(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let sub = item.submenu, let match = find(title, in: sub) { return match }
        }
        return nil
    }
    func choose(_ title: String, in menu: NSMenu) -> Bool {
        guard let item = find(title, in: menu), let action = item.action else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }
    var menu = builder.build(context)
    let selectedPrecision = choose("정밀 조절 (¼ 단계)", in: menu)
    let selectedHaptics = choose("강하게", in: menu)
    let selectedKey = choose("⌥ Option", in: menu)
    let selectedTop = choose("동영상 탐색", in: menu)
    check("menu actions update independent settings", selectedPrecision && selectedHaptics && selectedKey && selectedTop
        && menuPreferences.settings.precise && menuPreferences.settings.haptics == .strong
        && menuPreferences.settings.holdKey == .option && menuPreferences.settings.top == .scrubVideo
        && menuPreferences.settings.bottom == .keyboardBrightness)
    menu = builder.build(context)
    check("menu checkmarks reflect saved settings", find("정밀 조절 (¼ 단계)", in: menu)?.state == .on
        && find("강하게", in: menu)?.state == .on && find("⌥ Option", in: menu)?.state == .on)
    let cornerMenu = menu.item(withTitle: "모서리 더블 탭")?.submenu?.item(withTitle: "오른쪽 아래")?.submenu
    let selectedCorner = cornerMenu.map { choose("스크린샷 도구 막대", in: $0) } ?? false
    check("corner menu changes only the selected corner", selectedCorner && menuPreferences.settings.corners[.bottomRight] == .screenshot
        && menuPreferences.settings.corners[.topLeft] == .off)
    return failures == 0 ? 0 : 1
}
#endif
