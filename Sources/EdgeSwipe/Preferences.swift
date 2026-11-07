import Foundation
import GestureCore

final class Preferences {
    private let defaults: UserDefaults
    private let hasKeyboardBacklight: Bool
    var settings: GestureSettings
    var excludedApps: Set<String>
    var paused: Bool

    init(defaults: UserDefaults = .standard, hasKeyboardBacklight: Bool) {
        self.defaults = defaults
        self.hasKeyboardBacklight = hasKeyboardBacklight
        var settings = GestureSettings()
        settings.swapped = defaults.bool(forKey: "edgesSwapped")
        settings.precise = defaults.bool(forKey: "precise")
        settings.freezeCursor = defaults.object(forKey: "freezeCursor") == nil || defaults.bool(forKey: "freezeCursor")
        settings.bottomQuarterOnly = defaults.bool(forKey: "bottomQuarterOnly")
        settings.threeFingerClick = defaults.bool(forKey: "threeFingerClick")
        settings.width = EdgeWidth(rawValue: defaults.string(forKey: "edgeWidth") ?? "") ?? .standard
        settings.haptics = HapticStrength(rawValue: defaults.string(forKey: "hapticStrength") ?? "") ?? .medium
        settings.holdKey = HoldKey(rawValue: defaults.string(forKey: "holdKey") ?? "") ?? .none
        settings.holdMode = HoldMode(rawValue: defaults.string(forKey: "holdMode") ?? "") ?? .held
        settings.top = GestureAction(rawValue: defaults.string(forKey: "topAction") ?? "") ?? .switchApps
        settings.bottom = GestureAction(rawValue: defaults.string(forKey: "bottomAction") ?? "")
            ?? (hasKeyboardBacklight ? .keyboardBrightness : .media)
        for corner in Corner.allCases {
            settings.corners[corner] = CornerAction(rawValue: defaults.string(forKey: "corner." + corner.rawValue) ?? "") ?? .off
        }
        self.settings = settings
        excludedApps = Set(defaults.stringArray(forKey: "excludedApps") ?? [])
        paused = defaults.bool(forKey: "paused")
    }

    func save() {
        defaults.set(settings.swapped, forKey: "edgesSwapped")
        defaults.set(settings.precise, forKey: "precise")
        defaults.set(settings.freezeCursor, forKey: "freezeCursor")
        defaults.set(settings.bottomQuarterOnly, forKey: "bottomQuarterOnly")
        defaults.set(settings.threeFingerClick, forKey: "threeFingerClick")
        defaults.set(settings.width.rawValue, forKey: "edgeWidth")
        defaults.set(settings.haptics.rawValue, forKey: "hapticStrength")
        defaults.set(settings.holdKey.rawValue, forKey: "holdKey")
        defaults.set(settings.holdMode.rawValue, forKey: "holdMode")
        defaults.set(settings.top.rawValue, forKey: "topAction")
        defaults.set(settings.bottom.rawValue, forKey: "bottomAction")
        for corner in Corner.allCases { defaults.set((settings.corners[corner] ?? .off).rawValue, forKey: "corner." + corner.rawValue) }
        defaults.set(excludedApps.sorted(), forKey: "excludedApps")
        defaults.set(paused, forKey: "paused")
    }

    func reset() {
        settings = GestureSettings()
        if !hasKeyboardBacklight { settings.bottom = .media }
        excludedApps = []
        paused = false
        save()
    }
}
