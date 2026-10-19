# Unverified API and tooling assumptions

No Swift compiler, Xcode or XcodeGen is available in the authoring environment. Every item below could only be checked statically and must be confirmed on the Mac or in CI.

- `project.yml`: XcodeGen is expected to exclude the `Info.plist` referenced by `INFOPLIST_FILE` from the target's resources automatically. To verify: after `xcodegen generate`, check that `SleepTracker/Info.plist` does not appear under "Copy Bundle Resources". If it does, add `excludes: ["Info.plist"]` to the `SleepTracker` source entry.
- `SleepTracker/Shared/SettingsStore.swift:17`: `_settings = Published(initialValue: SettingsStore.load(from: userDefaults))` assigns the `@Published` backing storage directly in `init`, so the `didSet { save() }` observer on `settings` does not fire while loading. To verify on the Mac: it compiles without "self used before all stored properties are initialized" or an observer-on-wrapped-property diagnostic, and `testSettingsStorePersists` passes.
- `SleepTracker/Shared/SoundEventType.swift:25-28`: SF Symbols names `zzz`, `bubble.left.fill`, `wind`, `ear.fill` must exist on iOS 17 in the installed SF Symbols set. To verify: render `Image(systemName:)` for each case in a preview and check that none shows a blank image.
- `SleepTracker/Shared/Formatters.swift:42,52,60-78`: the exact output of `DateFormatter` with `de_DE` and `EE, d. MMM yyyy` (abbreviation with or without trailing dot, e.g. "Mo., 3. Feb. 2025", "Juni" vs "Jun.") depends on the CLDR version of the iOS runtime. To verify: log `Formatters.nightDate(Date())` for several months on the simulator and device; also confirm `Formatters.csvTimestamp(Date(timeIntervalSince1970: 0))` gives `1970-01-01T00:00:00Z`.

