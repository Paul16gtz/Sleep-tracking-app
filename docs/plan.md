# Schlafprotokoll: Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine lokale iPhone-App (SwiftUI, iOS 17), die nachts Schnarchen, Sprechen und Unruhe erkennt, Clips speichert und die Nächte auswertet.

**Architecture:** Hardware-Zugriffe (Mikrofon, SoundAnalysis, CoreMotion, Dateisystem) liegen hinter Protokollen. Die gesamte Entscheidungslogik (Ringpuffer, Pegel, Ereigniserkennung, Clip-Auswahl, Epochen, Kalibrierung, Statistik, CSV) sind reine Value-Types mit XCTest. `AudioPipeline` verbindet Quelle, Klassifikator und Logik auf einer Serial Queue; `SleepSessionController` (MainActor) orchestriert eine Nacht und persistiert über SwiftData.

**Tech Stack:** Swift 5 Language Mode, SwiftUI, SwiftData, Swift Charts, AVFoundation, SoundAnalysis, CoreMotion, XCTest, XcodeGen.

**Spec:** `docs/spec.md` (Teil A Vorgabe, Teil B Entscheidungen). Jeder Task setzt die Spec voraus.

## Arbeitsbedingungen (gelten für jeden Task)

- **Kein Compiler verfügbar.** Es gibt in dieser Umgebung weder `swift` noch `xcodebuild`. Jeder "Run"-Schritt der TDD-Schleife wird durch einen **statischen Check** ersetzt: Test und Implementierung noch einmal lesen und für jedes benutzte Symbol prüfen, dass es mit exakt dieser Signatur in diesem Plan oder im Code definiert ist (Typen, Optionals, Labels, `mutating`, `throws`, Imports). Der echte Lauf passiert später auf dem Mac und in CI.
- **Reihenfolge trotzdem TDD:** Test zuerst schreiben und committen können, dann Implementierung. Testdatei und Implementierung im selben Commit ist in Ordnung.
- **Unsicherheiten protokollieren:** Jede API-Stelle, bei der die Signatur nicht sicher ist, kommt mit Datei und Zeile als Stichpunkt nach `docs/unverified.md` (anlegen, falls nicht vorhanden). Task 17 und Task 25 übernehmen diese Liste in die README.
- **Konventionen:** Code, Bezeichner, Kommentare Englisch. UI-Strings Deutsch, direkt im Code (keine Localizable-Dateien). Keine `TODO`/`FIXME`, keine Platzhalter. Keine Force-Unwraps außer bei `floatChannelData` nach Format-Prüfung. Jede Datei beginnt mit `import Foundation`; weitere Imports nur wo nötig. Reine Logik liegt in `struct`s ohne Framework-Imports außer Foundation. Klassen mit UI-State sind `@MainActor final class ... : ObservableObject`.
- **Commits:** Nach jedem Task ein Commit mit aussagekräftiger Message. Kein Modellname in Commit-Messages oder Code.

## Global Constraints

- Deployment Target iOS 17.0, nur iPhone (`TARGETED_DEVICE_FAMILY = 1`), nur Hochformat.
- Nur Apple-Frameworks: AVFoundation, SoundAnalysis, CoreMotion, SwiftData, Charts, SwiftUI, UIKit (nur wo nötig). Keine Third-Party-Dependencies.
- `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`.
- Bundle Identifier `com.paul.sleeptracker`, `DEVELOPMENT_TEAM` leer, Display-Name "Schlafprotokoll".
- Info.plist: `NSMicrophoneUsageDescription`, `NSMotionUsageDescription` (deutsch), `UIBackgroundModes = [audio]`.
- Dateischutz `FileProtectionType.completeUntilFirstUserAuthentication` für Clip-Ordner, Clips, Store-Ordner und Store-Datei.
- Standardwerte: Einschlafverzögerung 900 s, Schwelle 0,6 je Kategorie, N = 2 Fenster, Ende-Lücke 4 s, Merge-Abstand 10 s, Pre-/Post-Roll 5 s, Clip max. 60 s, Sprech-Clips max. 50/Nacht, Schnarch-Clips 1 je 600 s und max. 20/Nacht, Epoche 30 s, Kalibrierung 300 s, Unruhe-Faktor 3,0, Ringpuffer 10 s, Live-Pegel max. 5 Updates/s (Intervall 0,2 s), Speichern spätestens alle 120 s.
- Klassifikator: `SNClassifySoundRequest(classifierIdentifier: .version1)`, Fenster 1,5 s, Überlappung 0,5. Labels nur aus `knownClassifications`.
- Alle SwiftData-Zugriffe auf dem Main Actor. Audio-Analyse auf einer dedizierten Serial Queue.
- Niemals die ganze Nacht im RAM halten: Ringpuffer fest 10 s, Clips streamen direkt in die Datei.

## Review Focus

Fünf Eingaben, die die Spec nicht nennt, die aber im Betrieb auftreten. Jede Zeile hat ihren Test im zuständigen Task.

1. **Nicht-endliche Samples (NaN/Inf) im Audiopuffer** dürfen die Epochenmittelwerte nicht vergiften: `LevelMeter.rmsDecibels` behandelt sie als Stille (Task 4).
2. **Zeit springt rückwärts** nach dem Neustart eines Audio-Segments (Wanduhr vs. Frame-Zähler): `LevelEpochAggregator` darf keine negativen oder doppelten Epochen liefern; der Wert landet in der aktuellen Epoche (Task 4). Der `EventDetector` darf nicht abstürzen (Task 6).
3. **Session mit Dauer 0 oder ohne Epochen**: `NightStatistics` liefert 0 statt NaN für Prozentwerte (Task 13).
4. **Clip-Datei kann nicht geöffnet werden** (Speicher voll): Die Pipeline läuft ohne Clip weiter, meldet den Fehler einmal und finalisiert das Ereignis mit `clipPath == nil` (Task 12).
5. **Einstellungen aus einer älteren Version** ohne neue Schlüssel: `AppSettings` dekodiert mit Standardwerten für fehlende Felder statt alles zu verwerfen (Task 2). Löschen einer Session, deren Clip-Ordner fehlt, ist kein Fehler (Task 9).

## Dateistruktur

```
project.yml
.gitignore
.github/workflows/build.yml                    (Task 24)
README.md
docs/spec.md, docs/plan.md, docs/unverified.md
SleepTracker/
  Info.plist
  App/SleepTrackerApp.swift                     @main, Fehleranzeige bei Startproblemen
  App/AppDependencies.swift                     baut Container, Stores, Controller
  App/RootTabView.swift                         TabView
  Shared/SoundEventType.swift                   enum + deutsche Namen + SF Symbols
  Shared/AppSettings.swift                      Codable-Einstellungen mit Defaults
  Shared/SettingsStore.swift                    UserDefaults-Persistenz, ObservableObject
  Shared/Formatters.swift                       Dauer, Datum, Prozent, dB (de_DE)
  Shared/Theme.swift                            Farben
  Audio/AudioSource.swift                       Protokoll AudioSource + Delegate
  Audio/MonoDownmix.swift                       AVAudioPCMBuffer -> Mono Float32 / [Float]
  Audio/AudioSessionManager.swift               AVAudioSession-Konfiguration
  Audio/MicrophoneAudioSource.swift             AVAudioEngine-Tap, Interruptions, Restart
  Audio/FileAudioSource.swift                   (Task 23) liest AVAudioFile blockweise
  Audio/RingBuffer.swift                        reine Logik
  Audio/LevelMeter.swift                        RMS dBFS + LevelThrottle
  Audio/LevelEpochAggregator.swift              30-s-Epochen avg/peak
  Audio/ClipWriting.swift                       Protokoll ClipWriting
  Audio/ClipWriter.swift                        AVAudioFile AAC .m4a
  Audio/ClipRecorder.swift                      reine Logik: Pre-Roll, Live, Post-Roll, Max
  Analysis/LabelMapping.swift                   Label -> SoundEventType (zentral)
  Analysis/ClassificationWindow.swift           Fensterergebnis
  Analysis/SoundClassifying.swift               Protokoll + Factory-Typ
  Analysis/SoundClassifierService.swift         SNAudioStreamAnalyzer-Wrapper
  Analysis/EventDetector.swift                  reine Logik
  Analysis/ClipPolicy.swift                     reine Logik
  Motion/MotionEpochAggregator.swift            (Task 18)
  Motion/MotionBaselineCalibrator.swift         (Task 18)
  Motion/MotionAnalyzer.swift                   (Task 18)
  Motion/MotionSource.swift                     (Task 19) Protokoll + CoreMotion-Implementierung
  Session/AudioPipeline.swift                   verbindet Quelle, Klassifikator, Logik
  Session/InterruptionGap.swift                 Codable
  Session/EpochMerger.swift                     (Task 19) Pegel + Bewegung je Epoche
  Session/NightStatistics.swift                 reine Logik
  Session/SleepSessionController.swift          MainActor-Orchestrierung
  Persistence/FileStore.swift                   Verzeichnisse, Schutzattribut, Clip-Pfade
  Persistence/Models.swift                      SleepSession, SoundEvent, EpochSample
  Persistence/SessionRepository.swift           CRUD, Stale-Markierung, Löschen inkl. Clips
  Persistence/CSVExporter.swift                 (Task 21)
  Features/Tonight/TonightView.swift            Start-Ansicht
  Features/Tonight/StartHintsSheet.swift        Hinweise vor dem Start
  Features/Tonight/NightScreenView.swift        Live-Bildschirm
  Features/Nights/NightsListView.swift          Liste
  Features/Nights/NightRowView.swift            Zeile
  Features/NightDetail/NightDetailView.swift    Zusammenfassung + Ereignisse (+ Chart, Export in Phase 2)
  Features/NightDetail/EventRowView.swift       Ereignis mit Play/Pause
  Features/NightDetail/NightTimelineChart.swift (Task 20)
  Features/NightDetail/ClipPlayer.swift         AVAudioPlayer-Wrapper
  Features/Settings/SettingsView.swift          (Task 22)
  Features/Debug/DebugView.swift                (Task 23)
  Features/Debug/TestModeView.swift             (Task 23)
SleepTrackerTests/
  SmokeTests.swift, AppSettingsTests.swift, FormattersTests.swift, RingBufferTests.swift,
  LevelMeterTests.swift, LevelEpochAggregatorTests.swift, LabelMappingTests.swift,
  EventDetectorTests.swift, ClipPolicyTests.swift, ClipRecorderTests.swift,
  FileStoreTests.swift, SessionRepositoryTests.swift, AudioPipelineTests.swift,
  NightStatisticsTests.swift, MotionTests.swift, EpochMergerTests.swift, CSVExporterTests.swift
  Fakes/FakeAudioSource.swift, Fakes/FakeSoundClassifier.swift, Fakes/FakeClipWriter.swift
```

---

# Phase 1 (MVP)

### Task 1: Projektgerüst (XcodeGen, Info.plist, App-Einstieg, Test-Target)

**Files:**
- Create: `project.yml`, `.gitignore`, `SleepTracker/Info.plist`, `SleepTracker/App/SleepTrackerApp.swift`, `SleepTracker/App/RootTabView.swift`, `SleepTrackerTests/SmokeTests.swift`, `docs/unverified.md`

**Interfaces:**
- Produces: Target `SleepTracker` (application), Target `SleepTrackerTests` (bundle.unit-test, `@testable import SleepTracker`), Scheme `SleepTracker` mit Test-Action.

- [ ] **Step 1: `project.yml` schreiben**

```yaml
name: SleepTracker
options:
  bundleIdPrefix: com.paul
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
targets:
  SleepTracker:
    type: application
    platform: iOS
    sources:
      - path: SleepTracker
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.paul.sleeptracker
        INFOPLIST_FILE: SleepTracker/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        TARGETED_DEVICE_FAMILY: "1"
        ENABLE_PREVIEWS: YES
  SleepTrackerTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: SleepTrackerTests
    dependencies:
      - target: SleepTracker
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.paul.sleeptracker.tests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  SleepTracker:
    build:
      targets:
        SleepTracker: all
        SleepTrackerTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - SleepTrackerTests
```

- [ ] **Step 2: `.gitignore`**: `*.xcodeproj/`, `xcuserdata/`, `DerivedData/`, `.DS_Store`, `*.xcworkspace/` (außer Package-Workspaces gibt es keine), `build/`.

- [ ] **Step 3: `SleepTracker/Info.plist`** (XML-Plist) mit genau diesen Keys:
  `CFBundleDevelopmentRegion` = `de`, `CFBundleDisplayName` = `Schlafprotokoll`, `CFBundleExecutable` = `$(EXECUTABLE_NAME)`, `CFBundleIdentifier` = `$(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleInfoDictionaryVersion` = `6.0`, `CFBundleName` = `$(PRODUCT_NAME)`, `CFBundlePackageType` = `APPL`, `CFBundleShortVersionString` = `1.0`, `CFBundleVersion` = `1`, `LSRequiresIPhoneOS` = true, `UILaunchScreen` = leeres Dict, `UISupportedInterfaceOrientations` = `[UIInterfaceOrientationPortrait]`, `UIUserInterfaceStyle` = `Dark`, `UIBackgroundModes` = `[audio]`, `NSMicrophoneUsageDescription` = `Das Mikrofon wird nachts genutzt, um Schnarchen und Sprechen im Schlaf zu erkennen. Alle Daten bleiben auf deinem iPhone.`, `NSMotionUsageDescription` = `Der Bewegungssensor erkennt über die Matratze, wie unruhig du schläfst. Alle Daten bleiben auf deinem iPhone.`

- [ ] **Step 4: `SleepTrackerApp.swift`**: `@main struct SleepTrackerApp: App` mit `WindowGroup { RootTabView() }`. In diesem Task noch ohne Dependencies (Task 14 ersetzt den Body).

- [ ] **Step 5: `RootTabView.swift`**: `struct RootTabView: View` mit `TabView` und zwei Platzhalter-Tabs `Text("Heute Nacht")` (Label "Heute Nacht", `systemImage: "moon.zzz.fill"`) und `Text("Nächte")` (Label "Nächte", `systemImage: "list.bullet"`). Task 15/16 ersetzen die Inhalte.

- [ ] **Step 6: `SmokeTests.swift`**: `final class SmokeTests: XCTestCase { func testTargetLinks() { XCTAssertTrue(true) } }` mit `@testable import SleepTracker`.

- [ ] **Step 7: `docs/unverified.md`** anlegen mit Überschrift und erstem Eintrag: XcodeGen schließt `Info.plist` unter `INFOPLIST_FILE` automatisch aus den Resources aus (zu prüfen: taucht die Datei in "Copy Bundle Resources" auf, `excludes: ["Info.plist"]` ergänzen).

- [ ] **Step 8: Statischer Check**: Jeder Pfad in `project.yml` existiert. `Info.plist` ist valides XML (mit `python3 -c "import plistlib,sys; plistlib.load(open('SleepTracker/Info.plist','rb'))"` prüfen) und `python3 -c "import yaml"` falls verfügbar für `project.yml`.

- [ ] **Step 9: Commit** `Add XcodeGen project skeleton, Info.plist and app entry`

---

### Task 2: Shared-Typen: SoundEventType, AppSettings, SettingsStore, Formatters, Theme

**Files:**
- Create: `SleepTracker/Shared/SoundEventType.swift`, `SleepTracker/Shared/AppSettings.swift`, `SleepTracker/Shared/SettingsStore.swift`, `SleepTracker/Shared/Formatters.swift`, `SleepTracker/Shared/Theme.swift`
- Test: `SleepTrackerTests/AppSettingsTests.swift`, `SleepTrackerTests/FormattersTests.swift`

**Interfaces (Produces):**

```swift
enum SoundEventType: String, Codable, CaseIterable, Identifiable {
    case snoring, speech, cough, whispering
    var id: String { rawValue }
    var germanName: String        // "Schnarchen", "Sprechen", "Husten", "Flüstern"
    var symbolName: String        // "zzz", "bubble.left.fill", "wind", "ear.fill"
}

struct AppSettings: Codable, Equatable {
    var fallAsleepDelay: TimeInterval          // 900
    var thresholds: [String: Double]           // key = SoundEventType.rawValue, default 0.6 für alle vier
    var minConsecutiveWindows: Int             // 2
    var eventEndGap: TimeInterval              // 4
    var mergeGap: TimeInterval                 // 10
    var maxEventDuration: TimeInterval         // 600
    var clipPreRoll: TimeInterval              // 5
    var clipPostRoll: TimeInterval             // 5
    var clipMaxDuration: TimeInterval          // 60
    var speechClipLimitPerNight: Int           // 50
    var snoringClipMinInterval: TimeInterval   // 600
    var snoringClipLimitPerNight: Int          // 20
    var restlessFactor: Double                 // 3.0
    var motionCalibrationDuration: TimeInterval // 300
    init()                                     // alle Defaults
    init(from decoder: Decoder) throws         // decodeIfPresent je Feld, sonst Default
    func threshold(for type: SoundEventType) -> Double          // thresholds[type.rawValue] ?? 0.6
    mutating func setThreshold(_ value: Double, for type: SoundEventType)
}

@MainActor final class SettingsStore: ObservableObject {
    static let storageKey = "appSettings"
    @Published var settings: AppSettings      // didSet -> save()
    init(userDefaults: UserDefaults = .standard)   // lädt JSON, bei Fehler AppSettings()
    func resetToDefaults()
}

enum Formatters {
    static func duration(_ seconds: TimeInterval) -> String   // "7 h 32 min", unter 1 h "32 min", negative -> "0 min"
    static func clock(_ seconds: TimeInterval) -> String      // "07:32:15"
    static func minutes(_ seconds: TimeInterval) -> String    // "12 min" (gerundet)
    static func percent(_ value: Double) -> String            // "23 %" (gerundet, value in 0...100)
    static func decibels(_ value: Double) -> String           // "-42 dB"
    static func nightDate(_ date: Date) -> String             // DateFormatter de_DE, dateFormat "EE, d. MMM yyyy"
    static func time(_ date: Date) -> String                  // "23:41"
    static func csvTimestamp(_ date: Date) -> String          // ISO8601DateFormatter, Zeitzone UTC
}

enum Theme {
    static let background: Color      // Color(red: 0.05, green: 0.06, blue: 0.09)
    static let card: Color            // Color(red: 0.11, green: 0.12, blue: 0.16)
    static let accent: Color          // Color(red: 0.55, green: 0.65, blue: 1.0)
    static let nightDim: Color        // Color.black
    static func color(for type: SoundEventType) -> Color   // snoring .orange, speech .teal, cough .red, whispering .purple
}
```

- [ ] **Step 1: Tests schreiben** (`AppSettingsTests`):
  - `testDefaultsMatchSpec`: `AppSettings()` hat fallAsleepDelay 900, threshold(for: .snoring) 0.6, minConsecutiveWindows 2, eventEndGap 4, mergeGap 10, maxEventDuration 600, clipPreRoll 5, clipPostRoll 5, clipMaxDuration 60, speechClipLimitPerNight 50, snoringClipMinInterval 600, snoringClipLimitPerNight 20, restlessFactor 3.0, motionCalibrationDuration 300.
  - `testRoundTrip`: setThreshold(0.8, for: .speech), encode mit JSONEncoder, decode → gleich.
  - `testMissingKeysUseDefaults` (Review Focus 5): `Data("{\"fallAsleepDelay\": 60}".utf8)` dekodieren → fallAsleepDelay 60, mergeGap 10, threshold(for: .cough) 0.6.
  - `testSettingsStorePersists`: `UserDefaults(suiteName: "SettingsStoreTests")!`, `removePersistentDomain`, Store A setzt `settings.mergeGap = 20`, Store B mit denselben Defaults liest 20. Test-Methode `@MainActor`.
  - `FormattersTests`: `duration(27120) == "7 h 32 min"`, `duration(1920) == "32 min"`, `duration(-5) == "0 min"`, `clock(27135) == "07:32:15"`, `percent(23.4) == "23 %"`, `minutes(725) == "12 min"`, `decibels(-42.4) == "-42 dB"`.

- [ ] **Step 2: Implementieren** gemäß Interfaces. `nightDate` nutzt `DateFormatter` mit `locale = Locale(identifier: "de_DE")`, `dateFormat = "EE, d. MMM yyyy"`. `clock` nutzt Integer-Arithmetik (keine `DateComponentsFormatter`, deren Ausgabe lokalisiert und schwer testbar ist).

- [ ] **Step 3: Statischer Check** (Codable-Init: `container.decodeIfPresent(TimeInterval.self, forKey: .fallAsleepDelay) ?? 900` je Feld; `CodingKeys` enum vollständig).

- [ ] **Step 4: Commit** `Add shared types: event type, settings, formatters, theme`

---

### Task 3: RingBuffer (TDD)

**Files:**
- Create: `SleepTracker/Audio/RingBuffer.swift`
- Test: `SleepTrackerTests/RingBufferTests.swift`

**Interfaces (Produces):**

```swift
struct RingBuffer {
    let capacity: Int
    private(set) var count: Int          // gültige Samples, <= capacity
    init(capacity: Int)                  // capacity < 1 wird als 1 behandelt
    mutating func write(_ samples: [Float])
    func latest(_ requested: Int) -> [Float]   // die jüngsten min(requested, count) Samples, älteste zuerst; requested <= 0 -> []
    mutating func clear()
}
```

- [ ] **Step 1: Tests**:
  - `testLatestReturnsFewerWhenNotFull`: capacity 10, write [1,2,3] → latest(5) == [1,2,3], count == 3.
  - `testWrapAround`: capacity 5, write [1,2,3,4,5,6,7] → latest(5) == [3,4,5,6,7], latest(2) == [6,7].
  - `testWriteLargerThanCapacityKeepsTail`: capacity 3, write 1...10 → latest(3) == [8,9,10].
  - `testMultipleSmallWritesWrap`: capacity 4, write [1,2], write [3,4], write [5] → latest(4) == [2,3,4,5].
  - `testClearResetsCount`: nach clear count == 0 und latest(3) == [].
  - `testNonPositiveRequestReturnsEmpty`: latest(0) == [], latest(-1) == [].
- [ ] **Step 2: Implementieren** mit `[Float]` Storage der Länge capacity und Schreibindex. `write` mit mehr Samples als capacity schreibt nur die letzten `capacity`.
- [ ] **Step 3: Statischer Check.**
- [ ] **Step 4: Commit** `Add RingBuffer with tests`

---

### Task 4: LevelMeter, LevelThrottle, LevelEpochAggregator (TDD)

**Files:**
- Create: `SleepTracker/Audio/LevelMeter.swift`, `SleepTracker/Audio/LevelEpochAggregator.swift`
- Test: `SleepTrackerTests/LevelMeterTests.swift`, `SleepTrackerTests/LevelEpochAggregatorTests.swift`

**Interfaces (Produces):**

```swift
enum LevelMeter {
    static let silenceFloor: Double = -120
    static func rmsDecibels(_ samples: [Float]) -> Double   // 20*log10(rms), clamp >= silenceFloor; leer -> silenceFloor; NaN/Inf-Samples zählen als 0
}

struct LevelThrottle {
    init(minInterval: TimeInterval = 0.2)
    mutating func shouldEmit(at time: TimeInterval) -> Bool   // erstes Mal true; danach true wenn time - lastEmit >= minInterval
}

struct LevelEpoch: Equatable {
    let index: Int
    let start: TimeInterval          // index * epochDuration
    let averageDecibels: Double      // arithmetisches Mittel der dB-Werte
    let peakDecibels: Double         // Maximum
}

struct LevelEpochAggregator {
    init(epochDuration: TimeInterval = 30)
    mutating func add(decibels: Double, at time: TimeInterval) -> [LevelEpoch]   // schließt die aktuelle Epoche ab, wenn time in eine spätere fällt; leere Epochen werden nicht emittiert; time vor der aktuellen Epoche -> Wert geht in die aktuelle Epoche
    mutating func finish() -> LevelEpoch?   // flusht die angefangene Epoche, danach leer
}
```

- [ ] **Step 1: Tests** (`LevelMeterTests`):
  - `testEmptyIsFloor`: `rmsDecibels([]) == -120`.
  - `testSilenceIsFloor`: 1000 Nullen → -120.
  - `testConstantHalfIsMinusSix`: 1000 × 0.5 → `-6.02 ± 0.01`.
  - `testFullScaleSineIsMinusThree`: 4800 Samples `sin(2π·i·100/4800)` → `-3.01 ± 0.05`.
  - `testNonFiniteSamplesAreTreatedAsSilence` (Review Focus 1): `[Float.nan, Float.infinity, 0, 0]` → -120; `[Float.nan, 0.5, 0.5, 0.5]` → endlicher Wert zwischen -7 und -5.
  - `testThrottle`: minInterval 0.2: shouldEmit(0) true, (0.1) false, (0.2) true, (0.35) false, (0.4) true.
  - (`LevelEpochAggregatorTests`) `testAverageAndPeakWithinEpoch`: add(-40, at: 1), (-20, 2), (-60, 3) → jeweils []; add(-50, at: 31) → `[LevelEpoch(index: 0, start: 0, averageDecibels: -40, peakDecibels: -20)]`.
  - `testSkipsEmptyEpochs`: add(-40, 1); add(-40, 95) → genau eine Epoche (index 0); finish() → Epoche index 3, start 90.
  - `testBoundaryBelongsToNextEpoch`: add(-40, 29.9), add(-30, 30) → eine Epoche index 0 avg -40; finish → index 1 avg -30.
  - `testFinishFlushesOnce`: add(-40, 1); finish() == LevelEpoch(0, 0, -40, -40); finish() == nil.
  - `testTimeGoingBackwardsStaysInCurrentEpoch` (Review Focus 2): add(-40, 50); add(-20, 45) → []; finish() → index 1 mit avg -30, peak -20.
- [ ] **Step 2: Implementieren.** Epochen-Index = `Int(floor(time / epochDuration))`, geklemmt auf `>= currentIndex`.
- [ ] **Step 3: Statischer Check.**
- [ ] **Step 4: Commit** `Add level meter, throttle and epoch aggregator with tests`

---

### Task 5: LabelMapping und ClassificationWindow (TDD)

**Files:**
- Create: `SleepTracker/Analysis/LabelMapping.swift`, `SleepTracker/Analysis/ClassificationWindow.swift`
- Test: `SleepTrackerTests/LabelMappingTests.swift`

**Interfaces (Produces):**

```swift
struct LabelMapping: Equatable {
    /// Zentrale Stelle für Label-Namen. Reihenfolge = Priorität.
    static let candidates: [SoundEventType: [String]] = [
        .snoring: ["snoring"], .speech: ["speech"], .cough: ["cough"], .whispering: ["whispering"]
    ]
    let labelToType: [String: SoundEventType]
    let availableTypes: Set<SoundEventType>
    init(knownLabels: [String])                      // nimmt nur Kandidaten, die in knownLabels vorkommen
    func type(for label: String) -> SoundEventType?
}

struct RankedLabel: Equatable {
    let label: String
    let confidence: Double
}

struct ClassificationWindow: Equatable {
    let start: TimeInterval
    let end: TimeInterval
    let confidences: [SoundEventType: Double]        // höchste Konfidenz je gemappter Kategorie
    init(start: TimeInterval, end: TimeInterval, confidences: [SoundEventType: Double])
    static func make(from ranked: [RankedLabel], mapping: LabelMapping, start: TimeInterval, end: TimeInterval) -> ClassificationWindow
}
```

- [ ] **Step 1: Tests**:
  - `testMapsOnlyKnownLabels`: known ["snoring","speech","dog"] → type(for:"snoring") == .snoring, type(for:"cough") == nil, availableTypes == [.snoring, .speech].
  - `testEmptyKnownLabelsYieldsEmptyMapping`: `LabelMapping(knownLabels: [])` → availableTypes leer, type(for:"snoring") == nil.
  - `testCandidatesCoverAllTypes`: für jeden `SoundEventType.allCases` ist `candidates[type]` nicht leer.
  - `testMakeWindowTakesMaxPerType`: ranked [("snoring",0.7),("speech",0.2),("snoring",0.1)] (bewusst doppelt) mit mapping aus ["snoring","speech"] → confidences == [.snoring: 0.7, .speech: 0.2]; unbekannte Labels ignoriert.
- [ ] **Step 2: Implementieren.**
- [ ] **Step 3: Statischer Check.**
- [ ] **Step 4: Commit** `Add label mapping and classification window with tests`

---

### Task 6: EventDetector (TDD)

**Files:**
- Create: `SleepTracker/Analysis/EventDetector.swift`
- Test: `SleepTrackerTests/EventDetectorTests.swift`

**Interfaces (Produces):**

```swift
struct DetectorConfig: Equatable {
    var thresholds: [SoundEventType: Double]
    var minConsecutiveWindows: Int
    var endGap: TimeInterval
    var mergeGap: TimeInterval
    var maxEventDuration: TimeInterval
    var countingStart: TimeInterval       // Fenster mit start < countingStart werden ignoriert
    init(thresholds: [SoundEventType: Double], minConsecutiveWindows: Int = 2, endGap: TimeInterval = 4, mergeGap: TimeInterval = 10, maxEventDuration: TimeInterval = 600, countingStart: TimeInterval = 0)
    init(settings: AppSettings, countingStart: TimeInterval)   // thresholds für alle SoundEventType.allCases
}

struct DetectedEvent: Equatable {
    let type: SoundEventType
    let start: TimeInterval
    let end: TimeInterval
    let maxConfidence: Double
    let averageConfidence: Double
}

enum DetectorOutput: Equatable {
    case eventStarted(type: SoundEventType, start: TimeInterval, detectedAt: TimeInterval)
    case eventResumed(type: SoundEventType)
    case eventEnded(type: SoundEventType, end: TimeInterval)
    case eventFinalized(DetectedEvent)
}

struct EventDetector {
    init(config: DetectorConfig)
    mutating func process(_ window: ClassificationWindow) -> [DetectorOutput]   // Typen in SoundEventType.allCases-Reihenfolge
    mutating func finish(at time: TimeInterval) -> [DetectorOutput]
}
```

Regeln (Zustandsautomat je Typ: `idle`, `candidate(hits, firstStart, confidences)`, `active(start, lastHitEnd, confidences)`, `pending(event, resumeHits, resumeConfidences)`):
- Treffer: `confidences[type] ?? 0 >= threshold`. Fenster mit `start < countingStart` ist für alle Typen ein Nicht-Treffer und wird komplett ignoriert (auch keine Zeitfortschritte für pending).
- `idle` + Treffer → `candidate` (hits 1). `candidate` + Treffer → hits+1; erreicht `minConsecutiveWindows` → `active(start: firstStart, lastHitEnd: window.end)`, Ausgabe `eventStarted(start: firstStart, detectedAt: window.end)`. `candidate` + Nicht-Treffer → `idle`.
- `active` + Treffer → lastHitEnd = window.end, Konfidenz sammeln. Wenn `window.end - start >= maxEventDuration` → `eventEnded(end: window.end)`, `eventFinalized`, dann sofort neues `active(start: window.end, lastHitEnd: window.end)` mit leerer Konfidenzliste plus der aktuellen Konfidenz und Ausgabe `eventStarted(start: window.end, detectedAt: window.end)`.
- `active` + Nicht-Treffer: wenn `window.end >= lastHitEnd + endGap` → `eventEnded(end: lastHitEnd)`, Zustand `pending`. Sonst nichts.
- `pending`: zuerst prüfen `window.start >= event.end + mergeGap` → `eventFinalized`, Zustand `idle`, dann das Fenster normal als `idle` verarbeiten. Sonst Treffer → resumeHits+1; erreicht `minConsecutiveWindows` → zurück zu `active` mit ursprünglichem Start, Konfidenzen vereinigt, Ausgabe `eventResumed`. Nicht-Treffer → resumeHits = 0 (bleibt pending).
- Konfidenz-Statistik: nur Treffer-Fenster des Ereignisses (inkl. fortgesetzter Teile), max und arithmetisches Mittel.
- `finish(at:)`: `active` → `eventEnded(end: lastHitEnd)` + `eventFinalized`; `pending` → `eventFinalized`; `candidate`/`idle` → nichts. Reihenfolge nach Typ.

- [ ] **Step 1: Tests** (Helper `w(_ start: Double, _ conf: Double, _ type: SoundEventType = .snoring) -> ClassificationWindow` mit end = start + 1.5; Standard-Config thresholds 0.6 für alle, N 2, endGap 4, mergeGap 10, maxDuration 600):
  - `testSingleOutlierDoesNotStartEvent`: w(0, 0.9), w(0.75, 0.1), w(1.5, 0.1) → alle Ausgaben leer.
  - `testTwoConsecutiveHitsStartEvent`: w(0, 0.9) → []; w(0.75, 0.8) → `[.eventStarted(type: .snoring, start: 0, detectedAt: 2.25)]`.
  - `testThresholdIsInclusive`: w(0, 0.6), w(0.75, 0.6) → eventStarted; mit 0.59 nicht.
  - `testEventEndsAfterEndGap`: Treffer 0, 0.75; Nicht-Treffer bei 1.5, 2.25, 3.0, 3.75, 4.5 → jeweils []; Nicht-Treffer bei 5.25 (end 6.75 ≥ 2.25 + 4) → `[.eventEnded(type: .snoring, end: 2.25)]`.
  - `testShortGapKeepsEventActive`: Treffer 0 (0.9), 0.75 (0.8); Nicht-Treffer 1.5, 2.25; Treffer 3.0 (0.7) → []; finish(at: 10) → `[.eventEnded(type: .snoring, end: 4.5), .eventFinalized(DetectedEvent(type: .snoring, start: 0, end: 4.5, maxConfidence: 0.9, averageConfidence: 0.8))]` (avg mit `accuracy: 1e-9` vergleichen, dazu Ausgabe destrukturieren).
  - `testEventFinalizedAfterMergeGap`: nach eventEnded (end 2.25) Nicht-Treffer bei 12.0 → []; bei 12.75 (start ≥ 12.25) → `[.eventFinalized(...)]`.
  - `testEventsWithinMergeGapAreMerged`: A wie oben bis eventEnded; Treffer 8.25 (0.7) → []; Treffer 9.0 (0.7) → `[.eventResumed(type: .snoring)]`; finish(at: 30) → eventEnded(end: 10.5), eventFinalized(start 0, end 10.5, max 0.9, avg (0.9+0.8+0.7+0.7)/4).
  - `testEventsBeyondMergeGapStaySeparate`: A bis eventEnded (end 2.25); Treffer 13.5 → `[.eventFinalized(A)]`; Treffer 14.25 → `[.eventStarted(type: .snoring, start: 13.5, detectedAt: 15.75)]`.
  - `testResumeRequiresMinConsecutiveWindows`: pending; Treffer 8.25; Nicht-Treffer 9.0; Nicht-Treffer bis 12.75 → genau ein eventFinalized mit end 2.25, kein eventResumed.
  - `testMaxDurationSplitsEvent`: maxDuration 3.0: Treffer 0, 0.75 → started; Treffer 1.5 (end 3.0) → `[.eventEnded(type: .snoring, end: 3.0), .eventFinalized(DetectedEvent(start: 0, end: 3.0, ...)), .eventStarted(type: .snoring, start: 3.0, detectedAt: 3.0)]`; Treffer 2.25 → []; finish(at: 10) → eventEnded(end: 3.75), eventFinalized(start 3.0, end 3.75).
  - `testFinishFinalizesActiveEvent`: Treffer 0, 0.75; finish(at: 5) → `[.eventEnded(end: 2.25), .eventFinalized(start 0, end 2.25, max 0.9, avg 0.85)]`.
  - `testFinishFinalizesPendingEvent`, `testFinishDropsCandidate` (ein Treffer, finish → []).
  - `testWindowsBeforeCountingStartAreIgnored`: countingStart 10: Treffer 0, 0.75, 1.5 → leer; Treffer 10.0, 10.75 → eventStarted(start: 10.0, detectedAt: 12.25).
  - `testTypesAreIndependentAndOrdered`: Fenster mit confidences [.speech: 0.9, .snoring: 0.9] zweimal → zweite Ausgabe == `[.eventStarted(type: .snoring, ...), .eventStarted(type: .speech, ...)]`.
  - `testMissingThresholdNeverHits`: config thresholds nur [.snoring: 0.6]; Fenster [.speech: 0.99] zweimal → leer.
  - `testWindowOutOfOrderDoesNotCrash` (Review Focus 2): Treffer 0, 0.75, dann w(0.5, 0.9), w(0.2, 0.9) → keine Exception, Ausgaben leer (Fenster ohne Zeitfortschritt bleiben Treffer im aktiven Ereignis).
- [ ] **Step 2: Implementieren** (private enum `TypeState` mit assoziierten Werten; `process` iteriert `SoundEventType.allCases` und sammelt Ausgaben).
- [ ] **Step 3: Statischer Check** (Equatable auf Enum mit assoziierten Werten wird synthetisiert; `DetectedEvent` Equatable; Double-Vergleiche in Tests mit `XCTAssertEqual(_:_:accuracy:)` wo nötig).
- [ ] **Step 4: Commit** `Add EventDetector state machine with tests`

---

### Task 7: ClipPolicy (TDD)

**Files:**
- Create: `SleepTracker/Analysis/ClipPolicy.swift`
- Test: `SleepTrackerTests/ClipPolicyTests.swift`

**Interfaces (Produces):**

```swift
struct ClipPolicy {
    struct Config: Equatable {
        var perEventLimit: Int            // für speech, cough, whispering (je Typ eigener Zähler)
        var snoringLimit: Int
        var snoringMinInterval: TimeInterval
        init(perEventLimit: Int, snoringLimit: Int, snoringMinInterval: TimeInterval)
        init(settings: AppSettings)       // speechClipLimitPerNight, snoringClipLimitPerNight, snoringClipMinInterval
    }
    init(config: Config)
    mutating func shouldRecordClip(for type: SoundEventType, at time: TimeInterval) -> Bool   // bei true wird gezählt und lastSnoringClipTime gesetzt
    func clipCount(for type: SoundEventType) -> Int
}
```

- [ ] **Step 1: Tests**:
  - `testSpeechAllowedUpToLimit`: perEventLimit 2 → true, true, false; clipCount(for: .speech) == 2.
  - `testCoughAndWhisperingUsePerEventRuleWithOwnCounters`: limit 1 → cough true, whispering true, cough false.
  - `testSnoringRespectsMinInterval`: interval 600, limit 20: at 0 true; at 300 false; at 599 false; at 600 true; at 1200 true.
  - `testSnoringRespectsLimit`: limit 2, interval 0 → true, true, false.
  - `testDeniedSnoringDoesNotResetInterval`: at 0 true, at 300 false, at 600 true (lastClipTime bleibt 0 bis 600).
- [ ] **Step 2: Implementieren.**
- [ ] **Step 3: Statischer Check.**
- [ ] **Step 4: Commit** `Add ClipPolicy with tests`

---

### Task 8: ClipRecorder (TDD)

**Files:**
- Create: `SleepTracker/Audio/ClipRecorder.swift`
- Test: `SleepTrackerTests/ClipRecorderTests.swift`

**Interfaces (Produces):**

```swift
enum ClipRecorderAction: Equatable {
    case open(type: SoundEventType, clipStart: TimeInterval)   // clipStart = max(0, eventStart - preRoll)
    case write([Float])
    case close
}

struct ClipRecorder {
    init(preRoll: TimeInterval, postRoll: TimeInterval, maxDuration: TimeInterval, sampleRate: Double)
    var isActive: Bool { get }
    func preRollSampleCount(eventStart: TimeInterval, now: TimeInterval) -> Int   // Int((preRoll + max(0, now - eventStart)) * sampleRate)
    mutating func begin(type: SoundEventType, eventStart: TimeInterval, preRollSamples: [Float]) -> [ClipRecorderAction]   // ignoriert, wenn aktiv (-> [])
    mutating func append(_ samples: [Float]) -> [ClipRecorderAction]   // [] wenn inaktiv; schneidet bei maxDuration ab und schließt
    mutating func eventEnded() -> [ClipRecorderAction]                 // startet Post-Roll-Zähler (postRoll * sampleRate Samples), gibt []
    mutating func eventResumed()                                       // bricht Post-Roll ab
    mutating func finish() -> [ClipRecorderAction]                     // [.close] wenn aktiv, sonst []
}
```

- [ ] **Step 1: Tests** (preRoll 5, postRoll 5, max 60, sampleRate 10; `z(n)` = `[Float](repeating: 0, count: n)`):
  - `testPreRollSampleCount`: eventStart 10, now 12 → 70; now 9 → 50.
  - `testBeginEmitsOpenAndPreRoll`: begin(.speech, eventStart: 10, preRollSamples: z(70)) → `[.open(type: .speech, clipStart: 5), .write(z(70))]`, isActive true. eventStart 2 → clipStart 0.
  - `testBeginWhileActiveIsIgnored`: zweites begin → [].
  - `testAppendWhileActiveWrites`: append(z(20)) → `[.write(z(20))]`; inaktiv → [].
  - `testPostRollClosesAfterPostRollSamples`: nach begin(70) eventEnded() → []; append(z(30)) → [.write(z(30))]; append(z(30)) → `[.write(z(20)), .close]`; isActive false; append(z(5)) → [].
  - `testMaxDurationTruncates`: begin mit z(70); append(z(600)) → `[.write(z(530)), .close]`.
  - `testEventResumedCancelsPostRoll`: eventEnded(); append(z(30)); eventResumed(); append(z(100)) → `[.write(z(100))]`, isActive true.
  - `testFinishClosesActiveClip`: finish() → [.close], danach finish() → [].
  - `testPreRollLargerThanMaxIsTruncated`: begin mit z(700) → `[.open(...), .write(z(600)), .close]`.
- [ ] **Step 2: Implementieren** (Zähler `writtenSamples`, `maxSamples`, `postRollRemaining: Int?`).
- [ ] **Step 3: Statischer Check.**
- [ ] **Step 4: Commit** `Add ClipRecorder with tests`

---

### Task 9: Persistenz: InterruptionGap, FileStore, SwiftData-Modelle, SessionRepository

**Files:**
- Create: `SleepTracker/Session/InterruptionGap.swift`, `SleepTracker/Persistence/FileStore.swift`, `SleepTracker/Persistence/Models.swift`, `SleepTracker/Persistence/SessionRepository.swift`
- Test: `SleepTrackerTests/FileStoreTests.swift`, `SleepTrackerTests/SessionRepositoryTests.swift`

**Interfaces (Produces):**

```swift
struct InterruptionGap: Codable, Equatable {
    var start: TimeInterval        // Sekunden seit Session-Start
    var end: TimeInterval?         // nil = bis Session-Ende
    var reason: String             // AudioInterruptionReason.rawValue (Task 10)
}

final class FileStore {
    let baseDirectory: URL                                  // .../Application Support/SleepTracker
    var clipsDirectory: URL { baseDirectory/Clips }
    var storeDirectory: URL { baseDirectory/Store }
    var storeURL: URL { storeDirectory/SleepTracker.store }
    static let protectionType: FileProtectionType = .completeUntilFirstUserAuthentication
    init(baseDirectory: URL)
    static func makeDefault() throws -> FileStore           // FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) + "SleepTracker"
    func prepareDirectories() throws                        // legt base, Clips, Store an und ruft applyProtection auf jedes Verzeichnis
    func applyProtection(to url: URL) throws                // FileManager.default.setAttributes([.protectionKey: FileStore.protectionType], ofItemAtPath:)
    func clipDirectory(for sessionID: UUID) throws -> URL   // legt an + Schutz
    func makeClipRelativePath(sessionID: UUID, clipStart: Date, type: SoundEventType) -> String   // "Clips/<uuidString>/<yyyyMMdd-HHmmss>-<type.rawValue>.m4a", Zeit in UTC
    func clipURL(relativePath: String) -> URL               // baseDirectory.appendingPathComponent(relativePath)
    func deleteClips(for sessionID: UUID) throws            // fehlender Ordner ist kein Fehler
    func deleteClip(relativePath: String) throws            // fehlende Datei ist kein Fehler
    func deleteAllClips() throws                            // löscht Clips-Ordner und legt ihn neu an
    func clipsTotalSize() -> Int64                          // Summe .fileSize aller Dateien unter Clips
}

enum SessionStatus: String, Codable { case running, ended, endedUnexpectedly
    var germanName: String   // "Läuft", "Beendet", "Unerwartet beendet"
}

@Model final class SleepSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var statusRaw: String
    var isTest: Bool
    var settingsSnapshotData: Data
    var interruptionGapsData: Data
    @Relationship(deleteRule: .cascade, inverse: \SoundEvent.session) var events: [SoundEvent] = []
    @Relationship(deleteRule: .cascade, inverse: \EpochSample.session) var epochs: [EpochSample] = []
    init(id: UUID = UUID(), startDate: Date, settings: AppSettings, isTest: Bool = false)
    var status: SessionStatus { get set }            // über statusRaw, unbekannt -> .endedUnexpectedly
    var settingsSnapshot: AppSettings { get }        // JSONDecoder, Fehler -> AppSettings()
    var interruptionGaps: [InterruptionGap] { get set }
    var duration: TimeInterval { (endDate ?? Date()).timeIntervalSince(startDate) }
}

@Model final class SoundEvent {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var startDate: Date
    var endDate: Date
    var maxConfidence: Double
    var averageConfidence: Double
    var clipRelativePath: String?
    var session: SleepSession?
    init(id: UUID = UUID(), type: SoundEventType, startDate: Date, endDate: Date, maxConfidence: Double, averageConfidence: Double, clipRelativePath: String?)
    var type: SoundEventType { get }                 // unbekannt -> .speech
    var duration: TimeInterval
}

@Model final class EpochSample {
    var timestamp: Date
    var motionIntensity: Double
    var isRestless: Bool
    var averageDecibels: Double
    var peakDecibels: Double
    var session: SleepSession?
    init(timestamp: Date, motionIntensity: Double, isRestless: Bool, averageDecibels: Double, peakDecibels: Double)
}

@MainActor final class SessionRepository {
    static let schema = Schema([SleepSession.self, SoundEvent.self, EpochSample.self])
    init(context: ModelContext, fileStore: FileStore)
    func createSession(startDate: Date, settings: AppSettings, isTest: Bool) throws -> SleepSession    // insert + save
    func addEvent(to session: SleepSession, type: SoundEventType, startDate: Date, endDate: Date, maxConfidence: Double, averageConfidence: Double, clipRelativePath: String?) throws -> SoundEvent
    func addEpoch(to session: SleepSession, timestamp: Date, averageDecibels: Double, peakDecibels: Double, motionIntensity: Double, isRestless: Bool) throws -> EpochSample
    func updateGaps(_ gaps: [InterruptionGap], for session: SleepSession) throws
    func finishSession(_ session: SleepSession, endDate: Date, status: SessionStatus, gaps: [InterruptionGap]) throws
    func markStaleRunningSessions() throws -> Int   // running -> endedUnexpectedly; endDate = max(letzte Epoche, letztes Ereignis-Ende) sonst startDate
    func fetchSessions() throws -> [SleepSession]   // FetchDescriptor sortiert startDate absteigend
    func deleteSession(_ session: SleepSession) throws   // fileStore.deleteClips(for:) dann context.delete + save
    func deleteEvent(_ event: SoundEvent) throws         // Clip-Datei löschen, dann Objekt
    func deleteAllData() throws                          // alle Sessions löschen + deleteAllClips
    func save() throws
}
```

- [ ] **Step 1: Tests** (`FileStoreTests`, temp base `FileManager.default.temporaryDirectory/UUID`):
  - `testClipRelativePathFormat`: sessionID `UUID(uuidString: "11111111-2222-3333-4444-555555555555")!`, clipStart = `Date(timeIntervalSince1970: 1_760_917_267)` (= 2025-10-19 23:41:07 UTC) → `"Clips/11111111-2222-3333-4444-555555555555/20251019-234107-speech.m4a"`.
  - `testClipURLAppendsRelativePath`: `clipURL(relativePath: "Clips/a/b.m4a").path` endet mit `/Clips/a/b.m4a`.
  - `testPrepareCreatesDirectories`: nach prepareDirectories existieren Clips und Store.
  - `testDeleteClipsForSessionRemovesDirectoryAndToleratesMissing` (Review Focus 5): Ordner anlegen mit Datei, löschen → weg; zweites Löschen wirft nicht.
  - `testClipsTotalSizeSumsFiles`: zwei Dateien mit 10 und 20 Bytes → 30.
  - (`SessionRepositoryTests`, alle `@MainActor`, Container `ModelContainer(for: SessionRepository.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])`, `container.mainContext`):
  - `testCreateAndFetchNewestFirst`: zwei Sessions mit Start t und t+3600 → fetch[0].startDate == t+3600.
  - `testMarkStaleRunningSessions`: Session running mit Epoche bei t+60 und Ereignis t+10...t+20 → Rückgabe 1, status == .endedUnexpectedly, endDate == t+60. Eine zweite Session mit status ended bleibt unverändert.
  - `testMarkStaleWithoutDataUsesStartDate`.
  - `testFinishSessionStoresGaps`: gaps [InterruptionGap(start: 10, end: 25, reason: "systemInterruption")] → session.interruptionGaps == gaps, status ended, endDate gesetzt.
  - `testDeleteSessionRemovesEventsAndClipFolder`: FileStore mit temp base, clipDirectory(for:) + Dummy-Datei, Session mit einem Ereignis → deleteSession → fetchSessions leer, Ordner weg.
  - `testDeleteEventRemovesClipFile`.
  - `testSettingsSnapshotRoundTrip`: settings.mergeGap = 42 → session.settingsSnapshot.mergeGap == 42.
- [ ] **Step 2: Implementieren.** `markStaleRunningSessions` holt alle Sessions (FetchDescriptor mit `#Predicate { $0.statusRaw == "running" }`; falls das Predicate mit String-Literal Probleme machen könnte, stattdessen alle fetchen und filtern, in `docs/unverified.md` notieren).
- [ ] **Step 3: Statischer Check**: In `@Model` keine `let`-Properties; Initializer setzen alle gespeicherten Properties; `inverse:` nur auf der Session-Seite; `import SwiftData` in Models und Repository.
- [ ] **Step 4: Commit** `Add persistence: file store, SwiftData models, repository with tests`

---

### Task 10: Audio-Hardware-Schicht: AudioSource, MonoDownmix, AudioSessionManager, MicrophoneAudioSource, ClipWriting/ClipWriter

**Files:**
- Create: `SleepTracker/Audio/AudioSource.swift`, `SleepTracker/Audio/MonoDownmix.swift`, `SleepTracker/Audio/AudioSessionManager.swift`, `SleepTracker/Audio/MicrophoneAudioSource.swift`, `SleepTracker/Audio/ClipWriting.swift`, `SleepTracker/Audio/ClipWriter.swift`
- Test: `SleepTrackerTests/Fakes/FakeAudioSource.swift`, `SleepTrackerTests/Fakes/FakeClipWriter.swift` (nur Fakes, keine Hardware-Tests)

**Interfaces (Produces):**

```swift
enum AudioInterruptionReason: String, Codable {
    case systemInterruption, routeChange, mediaServicesReset, engineConfigurationChange, engineFailure
    var germanName: String
}

protocol AudioSourceDelegate: AnyObject {
    /// Neues Stream-Segment (Start oder Neustart). Wird vor dem ersten Puffer des Segments aufgerufen. Läuft auf callbackQueue.
    func audioSource(_ source: AudioSource, didBeginSegmentWith format: AVAudioFormat)
    /// Mono-Float32-Puffer. framePosition zählt Frames seit Segmentbeginn. Läuft auf callbackQueue.
    func audioSource(_ source: AudioSource, didProduce buffer: AVAudioPCMBuffer, framePosition: AVAudioFramePosition)
    func audioSource(_ source: AudioSource, didInterruptWith reason: AudioInterruptionReason)
    func audioSource(_ source: AudioSource, didFailWith error: Error)
    /// Quelle hat selbst geendet (Datei zu Ende). Nicht nach stop().
    func audioSourceDidFinish(_ source: AudioSource)
}

protocol AudioSource: AnyObject {
    var delegate: AudioSourceDelegate? { get set }
    var callbackQueue: DispatchQueue { get }
    func start() throws
    func stop()
}

enum MonoDownmix {
    /// Mittelt alle Kanäle in einen neuen Mono-Float32-Puffer (Format monoFormat). nil, wenn buffer kein Float32 ist.
    static func makeMonoBuffer(from buffer: AVAudioPCMBuffer, monoFormat: AVAudioFormat) -> AVAudioPCMBuffer?
    /// Kanal 0 als Array.
    static func samples(of buffer: AVAudioPCMBuffer) -> [Float]
    /// Neuer Puffer aus Samples.
    static func makeBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer?
}

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    func configureForRecording() throws   // setCategory(.record, mode: .measurement, options: []); setActive(true)
    func configureForPlayback() throws    // setCategory(.playback, mode: .default, options: []); setActive(true)
    func deactivate()                     // setActive(false, options: .notifyOthersOnDeactivation); Fehler ignorieren
}

final class MicrophoneAudioSource: AudioSource {
    init(callbackQueue: DispatchQueue, sessionManager: AudioSessionManager = .shared, tapBufferSize: AVAudioFrameCount = 4096)
    // start(): Session konfigurieren, Notifications registrieren, beginSegment()
    // beginSegment(): engine neu erzeugen, inputFormat = engine.inputNode.outputFormat(forBus: 0); wenn sampleRate == 0 oder channelCount == 0 -> throw MicrophoneError.noInputFormat; monoFormat; Tap mit format: inputFormat; engine.prepare(); engine.start(); framePosition = 0; delegate.didBeginSegmentWith(monoFormat)
    // Tap-Block: MonoDownmix.makeMonoBuffer -> callbackQueue.async { delegate.didProduce(buffer, framePosition) ; framePosition += frameLength }
    // Notifications (Main Thread): AVAudioSession.interruptionNotification (.began -> didInterruptWith(.systemInterruption); .ended mit .shouldResume -> restart), AVAudioSession.routeChangeNotification (reason .oldDeviceUnavailable oder .newDeviceAvailable -> restart mit .routeChange), AVAudioSession.mediaServicesWereResetNotification (restart mit .mediaServicesReset), Notification.Name.AVAudioEngineConfigurationChange (restart mit .engineConfigurationChange)
    // restart(reason:): didInterruptWith(reason) falls noch nicht gemeldet; engine stoppen; sessionManager.configureForRecording(); beginSegment(); bei Fehler erneut nach 1, 2, 5, 10, 30 s (DispatchQueue.main.asyncAfter); nach dem 5. Fehlversuch didFailWith
    // stop(): Notifications entfernen, Tap entfernen, engine.stop(), sessionManager.deactivate()
}

enum MicrophoneError: LocalizedError { case noInputFormat, restartFailed(Error)
    var errorDescription: String?   // deutsch: "Kein Mikrofon-Eingang verfügbar.", "Aufnahme konnte nach einer Unterbrechung nicht fortgesetzt werden."
}

protocol ClipWriting: AnyObject {
    /// Wird von der Pipeline bei jedem Segmentbeginn aufgerufen, bevor ein Clip geöffnet wird.
    func prepare(sampleRate: Double)
    /// Öffnet eine neue Clip-Datei. Rückgabe: relativer Pfad. Wirft, wenn prepare noch nicht aufgerufen wurde (ClipWriterError.notPrepared).
    func open(type: SoundEventType, clipStart: Date) throws -> String
    func write(_ samples: [Float]) throws
    func close()
}

enum ClipWriterError: LocalizedError { case notPrepared, bufferAllocationFailed
    var errorDescription: String?   // deutsch
}

final class ClipWriter: ClipWriting {
    init(fileStore: FileStore, sessionID: UUID, bitRate: Int = 48_000)
    // prepare: sampleRate merken, monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate:, channels: 1, interleaved: false)
    // open: fileStore.clipDirectory(for:), relativePath = fileStore.makeClipRelativePath(...), AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: bitRate], commonFormat: .pcmFormatFloat32, interleaved: false); fileStore.applyProtection(to: url)
    // write: Puffer via MonoDownmix.makeBuffer(samples:, format: monoFormat), file.write(from:); ohne offene Datei ist write ein No-op
    // close: file = nil (AVAudioFile schließt beim Deinit)
}
```

Fakes:
```swift
final class FakeAudioSource: AudioSource {
    weak var delegate: AudioSourceDelegate?
    let callbackQueue: DispatchQueue          // im Test: DispatchQueue(label: "test.audio")
    var startCount = 0, stopCount = 0
    func start() throws { startCount += 1 }
    func stop() { stopCount += 1 }
    // Test-Helfer, rufen den Delegate synchron auf (callbackQueue.sync):
    func emitSegment(format: AVAudioFormat)
    func emitBuffer(samples: [Float], format: AVAudioFormat, framePosition: AVAudioFramePosition)
    func emitInterruption(_ reason: AudioInterruptionReason)
    func emitFinish()
}
final class FakeClipWriter: ClipWriting {
    var preparedSampleRate: Double?
    var openedTypes: [SoundEventType] = []
    var writtenSampleCount = 0
    var closeCount = 0
    var shouldFailOnOpen = false            // wirft FakeError.openFailed
    var nextRelativePath = "Clips/test/clip.m4a"
}
```

- [ ] **Step 1: Fakes schreiben** (sie definieren den Vertrag, bevor die echte Implementierung entsteht).
- [ ] **Step 2: Protokolle und MonoDownmix implementieren.** `makeMonoBuffer`: `buffer.format.commonFormat == .pcmFormatFloat32` prüfen, `floatChannelData` lesen, über Kanäle mitteln, `frameLength` setzen.
- [ ] **Step 3: AudioSessionManager, MicrophoneAudioSource, ClipWriter implementieren.** Tap-Puffer sofort downmixen (Kopie) und erst dann auf die Queue geben. Alle `NotificationCenter`-Observer mit `[weak self]`.
- [ ] **Step 4: Statischer Check**, Einträge in `docs/unverified.md`: `installTap(onBus:bufferSize:format:block:)` mit Input-Format; Tap-Block-Signatur `(AVAudioPCMBuffer, AVAudioTime) -> Void`; `AVAudioSession.InterruptionType`/`InterruptionOptions.shouldResume` aus `userInfo[AVAudioSessionInterruptionTypeKey]`/`AVAudioSessionInterruptionOptionKey`; `AVAudioSession.RouteChangeReason` aus `AVAudioSessionRouteChangeReasonKey`; `AVAudioFile(forWriting:settings:commonFormat:interleaved:)` mit AAC-Settings; Schließen über Deinit.
- [ ] **Step 5: Commit** `Add audio capture layer: source protocol, downmix, session manager, microphone source, clip writer`

---

### Task 11: SoundClassifying und SoundClassifierService

**Files:**
- Create: `SleepTracker/Analysis/SoundClassifying.swift`, `SleepTracker/Analysis/SoundClassifierService.swift`
- Test: `SleepTrackerTests/Fakes/FakeSoundClassifier.swift`

**Interfaces (Produces):**

```swift
protocol SoundClassifierDelegate: AnyObject {
    func classifier(_ classifier: SoundClassifying, didProduce window: ClassificationWindow, topLabels: [RankedLabel])
    func classifier(_ classifier: SoundClassifying, didFailWith error: Error)
}

protocol SoundClassifying: AnyObject {
    var delegate: SoundClassifierDelegate? { get set }
    func analyze(_ buffer: AVAudioPCMBuffer, atFramePosition position: AVAudioFramePosition)
    func completeAnalysis()
}

/// (Audio-Format, timeOffset in Sekunden seit Session-Start für Frame 0) -> Klassifikator
typealias SoundClassifierFactory = (AVAudioFormat, TimeInterval) throws -> SoundClassifying

final class SoundClassifierService: NSObject, SoundClassifying, SNResultsObserving {
    static let windowDuration: TimeInterval = 1.5
    static let overlapFactor: Double = 0.5
    weak var delegate: SoundClassifierDelegate?
    init(format: AVAudioFormat, mapping: LabelMapping, timeOffset: TimeInterval) throws
    // init: request = try SNClassifySoundRequest(classifierIdentifier: .version1); request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000); request.overlapFactor = 0.5; analyzer = SNAudioStreamAnalyzer(format: format); try analyzer.add(request, withObserver: self)
    // analyze: analyzer.analyze(buffer, atAudioFramePosition: position)
    // completeAnalysis: analyzer.completeAnalysis()
    // request(_:didProduce:): result as? SNClassificationResult; start = timeOffset + result.timeRange.start.seconds; end = start + result.timeRange.duration.seconds; ranked = result.classifications.map { RankedLabel(label: $0.identifier, confidence: $0.confidence) }; window = ClassificationWindow.make(from: ranked, mapping:, start:, end:); delegate?.classifier(self, didProduce: window, topLabels: Array(ranked.prefix(5)))
    // request(_:didFailWithError:): delegate?.classifier(self, didFailWith:)
    // requestDidComplete(_:): nichts
    static func knownLabels() throws -> [String]   // try SNClassifySoundRequest(classifierIdentifier: .version1).knownClassifications
    static func makeFactory(mapping: LabelMapping) -> SoundClassifierFactory
}

final class FakeSoundClassifier: SoundClassifying {
    weak var delegate: SoundClassifierDelegate?
    var analyzedFrameCount: Int = 0
    var completeCount = 0
    let timeOffset: TimeInterval
    func emit(window: ClassificationWindow, topLabels: [RankedLabel] = [])   // ruft delegate synchron
}
```

- [ ] **Step 1: Fake schreiben.**
- [ ] **Step 2: Service implementieren.** `windowDuration`-Setzen in `do/catch`-freiem Code, aber mit Kommentar; falls `windowDurationConstraint` ein `.enumeratedDurations` liefert, das nächstliegende nehmen (in `unverified.md`: Property-Namen `windowDuration`, `overlapFactor`, `windowDurationConstraint`, `knownClassifications`; Ergebnisthread von `SNAudioStreamAnalyzer`).
- [ ] **Step 3: Statischer Check** (`import SoundAnalysis`, `import AVFoundation`; `SNResultsObserving` ist ein `@objc`-Protokoll, Klasse erbt von `NSObject`).
- [ ] **Step 4: Commit** `Add SoundAnalysis classifier service and test fake`

---

### Task 12: AudioPipeline (verbindet alles; mit Fakes getestet)

**Files:**
- Create: `SleepTracker/Session/AudioPipeline.swift`
- Test: `SleepTrackerTests/AudioPipelineTests.swift`

**Interfaces:**
- Consumes: Task 3–11.
- Produces:

```swift
protocol AudioPipelineDelegate: AnyObject {    // alle Aufrufe auf pipeline.queue
    func pipeline(_ pipeline: AudioPipeline, didUpdateLevel decibels: Double)
    func pipeline(_ pipeline: AudioPipeline, didCompleteLevelEpoch epoch: LevelEpoch)
    func pipeline(_ pipeline: AudioPipeline, didStartEvent type: SoundEventType, at start: TimeInterval)
    func pipeline(_ pipeline: AudioPipeline, didFinalizeEvent event: DetectedEvent, clipRelativePath: String?)
    func pipeline(_ pipeline: AudioPipeline, didProduceTopLabels labels: [RankedLabel], at time: TimeInterval)
    func pipeline(_ pipeline: AudioPipeline, didRecordGap gap: InterruptionGap)
    func pipeline(_ pipeline: AudioPipeline, didReportError message: String)
    func pipelineDidFinish(_ pipeline: AudioPipeline)
}

final class AudioPipeline: AudioSourceDelegate, SoundClassifierDelegate {
    struct Config {
        var settings: AppSettings
        var countingStart: TimeInterval        // Einschlafverzögerung in Sekunden (0 im Testmodus)
        var ringBufferDuration: TimeInterval   // 10
        var levelUpdateInterval: TimeInterval  // 0.2
        var epochDuration: TimeInterval        // 30
        var sessionStart: Date                 // für Clip-Dateinamen: clipStart (relativ) -> Date
    }
    let queue: DispatchQueue                   // == source.callbackQueue
    weak var delegate: AudioPipelineDelegate?
    private(set) var gaps: [InterruptionGap]
    init(source: AudioSource, config: Config, mapping: LabelMapping, clipWriter: ClipWriting, classifierFactory: @escaping SoundClassifierFactory, clock: @escaping () -> TimeInterval)
    func start() throws        // source.delegate = self; source.start()
    func stop()                // source.stop(); auf queue synchron: finishSegment() (detector.finish, recorder.finish, epochs.finish), offene Gap schließen mit clock()
}
```

Verhalten:
- `didBeginSegmentWith(format)`: `segmentBase = clock()`; `sampleRate = format.sampleRate`; `clipWriter.prepare(sampleRate:)`; Klassifikator per Factory `(format, segmentBase)` erzeugen, `delegate = self`; `ringBuffer = RingBuffer(capacity: Int(ringBufferDuration * sampleRate))`; `recorder` nur beim ersten Segment erzeugen (Clip kann über Segmentgrenze weiterlaufen); offene Gap schließen (`end = segmentBase`) und `didRecordGap` melden. Detector und Epochen-Aggregator werden **einmal** beim ersten Segment erzeugt (Zeiten sind sessionrelativ).
- `didProduce(buffer, framePosition)`: `samples = MonoDownmix.samples(of:)`; `bufferEnd = segmentBase + Double(framePosition + Int64(buffer.frameLength)) / sampleRate`; `db = LevelMeter.rmsDecibels(samples)`; Throttle → `didUpdateLevel`; `epochs.add(db, at: bufferEnd)` → je Epoche `didCompleteLevelEpoch`; `ringBuffer.write(samples)`; `recorder.append(samples)` → Aktionen ausführen; `classifier.analyze(buffer, atFramePosition: framePosition)`.
- `classifier(didProduce window, topLabels)`: `didProduceTopLabels(labels, at: window.end)`; `detector.process(window)` → Ausgaben:
  - `.eventStarted(type, start, detectedAt)`: `didStartEvent`; wenn `!recorder.isActive && policy.shouldRecordClip(for: type, at: detectedAt)`: `preRoll = ringBuffer.latest(recorder.preRollSampleCount(eventStart: start, now: detectedAt))`, Aktionen von `recorder.begin(...)` ausführen; `clipPathByType[type] = Pfad aus open` (bei `open`-Fehler: `didReportError` einmal pro Session, Recorder per `finish()` zurücksetzen, Clip-Pfad nil).
  - `.eventResumed(type)`: `recorder.eventResumed()` nur wenn `activeClipType == type`.
  - `.eventEnded(type, _)`: `recorder.eventEnded()` nur wenn `activeClipType == type`; Aktionen ausführen.
  - `.eventFinalized(event)`: `didFinalizeEvent(event, clipRelativePath: clipPathByType[event.type])`; `clipPathByType[event.type] = nil`.
- Aktionen ausführen: `.open(type, clipStart)` → `clipWriter.open(type:, clipStart: config.sessionStart.addingTimeInterval(clipStart))`. `.write(samples)` → `clipWriter.write`; `.close` → `clipWriter.close()`, `activeClipType = nil`. Fehler bei write/close → `didReportError` (einmalig) und Recorder beenden.
- `didInterruptWith(reason)`: `gaps.append(InterruptionGap(start: lastBufferEnd, end: nil, reason: reason.rawValue))`; `classifier?.completeAnalysis()`; `classifier = nil`.
- `didFailWith(error)`: `didReportError(error.localizedDescription)`.
- `audioSourceDidFinish`: `finishSegment()` und `pipelineDidFinish`.
- `classifier(didFailWith:)`: `didReportError`.

- [ ] **Step 1: Tests** (Format `AVAudioFormat(standardFormatWithSampleRate: 100, channels: 1)!`; `FakeAudioSource` mit Queue; Pipeline-Delegate-Spy `PipelineSpy` sammelt alle Aufrufe; Config: settings default, countingStart 0, ringBuffer 10, levelUpdate 0.2, epoch 30, sessionStart = `Date(timeIntervalSince1970: 0)`; Klassifikator-Factory liefert den gemeinsamen `FakeSoundClassifier`; `clock` ist eine veränderbare Variable im Test):
  - `testLevelEpochAfterThirtySeconds`: 31 Puffer à 100 Samples (Wert 0.5), framePosition 0, 100, 200, … → Spy hat genau eine Epoche index 0 mit averageDecibels -6.02 ± 0.05, peak gleich; `didUpdateLevel` mindestens 1 und höchstens 31 Mal; `fakeClipWriter.preparedSampleRate == 100`.
  - `testEventWithClipFlow`: Segment beginnen; 1 Puffer; Fake-Klassifikator emittiert `w(0, [.speech: 0.9])`, `w(0.75, [.speech: 0.9])` → Spy `didStartEvent(.speech, at: 0)`, FakeClipWriter.openedTypes == [.speech], writtenSampleCount == 100 (Ringpuffer hatte nur 100 Samples); dann 3 Puffer à 100 → writtenSampleCount == 400; Fenster ohne Treffer bis 5.25 → eventEnded intern → danach 10 Puffer → Post-Roll 500 Samples geschrieben, closeCount == 1, writtenSampleCount == 900; Fenster bei 12.75 → Spy `didFinalizeEvent` mit `clipRelativePath == "Clips/test/clip.m4a"`, event.start 0, event.end 2.25.
  - `testSnoringClipPolicyApplied`: Zwei getrennte Schnarch-Ereignisse im Abstand < 600 s → openedTypes == [.snoring] (nur eins), beide finalisiert.
  - `testClipOpenFailureKeepsPipelineRunning` (Review Focus 4): FakeClipWriter.shouldFailOnOpen = true → Ereignis wird finalisiert mit clipRelativePath nil, Spy `didReportError` genau einmal, weitere Puffer liefern weiterhin Pegel.
  - `testInterruptionRecordsGap`: Puffer bis bufferEnd 10 (10 Puffer); `emitInterruption(.systemInterruption)`; clock = 25; `emitSegment` → Spy `didRecordGap == InterruptionGap(start: 10, end: 25, reason: "systemInterruption")`; nächster Puffer framePosition 0 hat bufferEnd 26 (prüfbar über Epochenindex nach weiteren Puffern oder über `pipeline.gaps`).
  - `testFallAsleepDelaySuppressesEvents`: countingStart 100; Fenster 0 und 0.75 mit 0.9 → kein didStartEvent; Fenster 100, 100.75 → didStartEvent.
  - `testStopFlushesPartialEpochAndActiveEvent`: 5 Puffer, zwei Treffer-Fenster; `stop()` → Spy hat eine Epoche (finish) und ein finalisiertes Ereignis; FakeClipWriter.closeCount == 1; FakeAudioSource.stopCount == 1.
  - `testFinishFromSourceReportsPipelineDidFinish`: `emitFinish()` → Spy `didFinish == true`, Epoche geflusht.
- [ ] **Step 2: Implementieren.** Alles mutable State nur auf `queue`. `stop()` nutzt `queue.sync` (Aufrufer ist Main Actor; Deadlock-frei, weil Delegate-Aufrufe aus der Queue nie synchron auf Main warten).
- [ ] **Step 3: Statischer Check** (Delegate-Methodennamen exakt wie Protokoll; `AVAudioFramePosition` ist `Int64`; `buffer.frameLength` ist `AVAudioFrameCount` = `UInt32`).
- [ ] **Step 4: Commit** `Add AudioPipeline wiring source, classifier, detector, clips and levels with tests`

---

### Task 13: NightStatistics (TDD)

**Files:**
- Create: `SleepTracker/Session/NightStatistics.swift`
- Test: `SleepTrackerTests/NightStatisticsTests.swift`

**Interfaces (Produces):**

```swift
struct EventSummary: Equatable { let type: SoundEventType; let start: Date; let end: Date }
struct EpochSummary: Equatable { let timestamp: Date; let isRestless: Bool }

struct NightStatistics: Equatable {
    let duration: TimeInterval
    let snoringDuration: TimeInterval
    let snoringPercentage: Double        // 0...100, 0 wenn duration <= 0
    let snoringCount: Int
    let speechCount: Int
    let coughCount: Int
    let whisperingCount: Int
    let totalEpochCount: Int
    let restlessEpochCount: Int
    let restlessPercentage: Double       // 0 wenn keine Epochen
    let restlessPhaseCount: Int          // zusammenhängende Läufe unruhiger Epochen (nach timestamp sortiert)
    let interruptionCount: Int
    static func compute(start: Date, end: Date?, now: Date, events: [EventSummary], epochs: [EpochSummary], gaps: [InterruptionGap]) -> NightStatistics
}
```

- [ ] **Step 1: Tests** (t0 = `Date(timeIntervalSince1970: 0)`):
  - `testSnoringDurationAndPercentage`: 8 h Session, Schnarchen 1800 s + 1800 s → snoringDuration 3600, snoringPercentage 12.5, snoringCount 2.
  - `testCountsByType`: 3 speech, 1 cough, 2 whispering → Zähler.
  - `testRestlessPhases`: Epochen [F,T,T,F,T,F,F,T,T,T] (30 s Abstand, unsortiert übergeben) → total 10, restless 6, 60.0 %, phases 3.
  - `testOpenSessionUsesNow`: end nil, now = t0 + 3600 → duration 3600.
  - `testZeroDurationYieldsZeroPercentages` (Review Focus 3): start == end, keine Epochen, ein Schnarch-Ereignis → snoringPercentage 0, restlessPercentage 0, keine NaN (`XCTAssertFalse(x.isNaN)`).
  - `testInterruptionCount`: 2 gaps → 2.
- [ ] **Step 2: Implementieren.**
- [ ] **Step 3: Statischer Check.**
- [ ] **Step 4: Commit** `Add NightStatistics with tests`

---

### Task 14: SleepSessionController, AppDependencies, App-Einstieg

**Files:**
- Create: `SleepTracker/Session/SleepSessionController.swift`, `SleepTracker/App/AppDependencies.swift`
- Modify: `SleepTracker/App/SleepTrackerApp.swift`

**Interfaces:**
- Consumes: Task 2, 9, 10, 11, 12.
- Produces:

```swift
enum SessionMode: Equatable { case night; case test(fileURL: URL) }   // .test wird in Task 23 implementiert; in Task 14 wirft start(.test) ControllerError.unsupported

enum ControllerError: LocalizedError { case alreadyRunning, microphoneDenied, classifierUnavailable(String), unsupported
    var errorDescription: String?   // deutsch
}

@MainActor final class SleepSessionController: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isTestRun: Bool = false
    @Published private(set) var startDate: Date?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var liveLevel: Double = LevelMeter.silenceFloor
    @Published private(set) var eventCounts: [SoundEventType: Int] = [:]
    @Published private(set) var isInFallAsleepDelay: Bool = false
    @Published private(set) var topLabels: [RankedLabel] = []
    @Published var errorMessage: String?                 // für Alerts; nil = kein Fehler
    var isCharging: Bool                                 // UIDevice.current.isBatteryMonitoringEnabled = true im init; batteryState == .charging || .full
    init(repository: SessionRepository, fileStore: FileStore, settingsStore: SettingsStore, sourceFactory: @escaping (DispatchQueue) -> AudioSource, classifierFactoryProvider: @escaping (LabelMapping) -> SoundClassifierFactory, knownLabelsProvider: @escaping () throws -> [String])
    static func requestMicrophonePermission() async -> Bool   // AVAudioApplication.requestRecordPermission()
    func start(mode: SessionMode) async throws
    func stop()
}
```

Ablauf `start(.night)`:
1. `guard !isRunning`. Mikrofon-Berechtigung prüfen (`requestMicrophonePermission`), sonst `.microphoneDenied`.
2. `labels = try knownLabelsProvider()`; `mapping = LabelMapping(knownLabels: labels)`.
3. `settings = settingsStore.settings`; `session = try repository.createSession(startDate: now, settings: settings, isTest: false)`.
4. `queue = DispatchQueue(label: "sleeptracker.analysis", qos: .userInitiated)`; `source = sourceFactory(queue)`; `clipWriter = ClipWriter(fileStore:, sessionID: session.id)` (die Sample-Rate liefert die Pipeline über `prepare(sampleRate:)` beim Segmentbeginn).
5. `pipeline = AudioPipeline(source:, config: Config(settings:, countingStart: settings.fallAsleepDelay, ringBufferDuration: 10, levelUpdateInterval: 0.2, epochDuration: 30, sessionStart: now), mapping:, clipWriter:, classifierFactory: classifierFactoryProvider(mapping), clock: { Date().timeIntervalSince(now) })`; `pipeline.delegate = self`; `try pipeline.start()` (bei Fehler Session als endedUnexpectedly beenden und rethrow).
6. `isRunning = true`, Timer (1 s, Main RunLoop): `elapsed`, `isInFallAsleepDelay = elapsed < settings.fallAsleepDelay`.
7. Zweiter Timer alle 120 s: `try? repository.save()`.

Delegate-Callbacks (kommen auf der Queue) → `Task { @MainActor in ... }` bzw. `DispatchQueue.main.async`:
- Level → `liveLevel`. Epoche → `repository.addEpoch(to: session, timestamp: start + epoch.start, averageDecibels:, peakDecibels:, motionIntensity: 0, isRestless: false)`.
- `didStartEvent` → `eventCounts[type, default: 0] += 1`.
- `didFinalizeEvent` → `repository.addEvent(...)` mit `startDate + event.start / event.end`.
- `didRecordGap` → `repository.updateGaps(pipeline.gaps, for: session)`.
- `didReportError` → `errorMessage`.
- `pipelineDidFinish` → `stop()`.
- `didProduceTopLabels` → `topLabels` (höchstens 2× pro Sekunde; Throttle über `Date`).

`stop()`: Timer invalidieren; `pipeline.stop()`; `repository.finishSession(session, endDate: Date(), status: .ended, gaps: pipeline.gaps)`; alle Published zurücksetzen; `isRunning = false`.

`AppDependencies`:
```swift
@MainActor final class AppDependencies: ObservableObject {
    let fileStore: FileStore
    let modelContainer: ModelContainer
    let repository: SessionRepository
    let settingsStore: SettingsStore
    let sessionController: SleepSessionController
    let clipPlayer: ClipPlayer                           // Task 16; in Task 14 zunächst ohne, Task 16 ergänzt
    init() throws
    // fileStore = try FileStore.makeDefault(); try fileStore.prepareDirectories()
    // config = ModelConfiguration("SleepTracker", schema: SessionRepository.schema, url: fileStore.storeURL, allowsSave: true, cloudKitDatabase: .none)
    // modelContainer = try ModelContainer(for: SessionRepository.schema, configurations: [config])
    // try? fileStore.applyProtection(to: fileStore.storeURL)
    // repository = SessionRepository(context: modelContainer.mainContext, fileStore: fileStore)
    // _ = try? repository.markStaleRunningSessions()
    // settingsStore = SettingsStore()
    // sessionController = SleepSessionController(repository:, fileStore:, settingsStore:, sourceFactory: { MicrophoneAudioSource(callbackQueue: $0) }, classifierFactoryProvider: { SoundClassifierService.makeFactory(mapping: $0) }, knownLabelsProvider: { try SoundClassifierService.knownLabels() })
}
```

`SleepTrackerApp`: `@State private var dependencies: AppDependencies?` und `@State private var startupError: String?`, befüllt im `init()` via `do { dependencies = try AppDependencies() } catch { startupError = ... }` (`_dependencies = State(initialValue: ...)`). Body: wenn dependencies vorhanden → `RootTabView().environmentObject(deps).environmentObject(deps.sessionController).environmentObject(deps.settingsStore).modelContainer(deps.modelContainer).preferredColorScheme(.dark)`; sonst `Text("Die App konnte den Speicher nicht öffnen: \(startupError)")`.

- [ ] **Step 1: Controller, AppDependencies, App implementieren.**
- [ ] **Step 2: Statischer Check**: `Timer.scheduledTimer(withTimeInterval:repeats:block:)` mit `[weak self]`; `AVAudioApplication.requestRecordPermission()` in `unverified.md` (Fallback `AVAudioSession.sharedInstance().requestRecordPermission`); `ModelConfiguration`-Initializer mit `url:` und `cloudKitDatabase: .none` in `unverified.md`; `import UIKit` nur in der Controller-Datei für `UIDevice`.
- [ ] **Step 3: Commit** `Add sleep session controller, dependency container and app wiring`

---

### Task 15: Tab "Heute Nacht" (Start-Ansicht, Hinweise, Nachtbildschirm)

**Files:**
- Create: `SleepTracker/Features/Tonight/TonightView.swift`, `SleepTracker/Features/Tonight/StartHintsSheet.swift`, `SleepTracker/Features/Tonight/NightScreenView.swift`
- Modify: `SleepTracker/App/RootTabView.swift` (Tab 1 → `TonightView()`)

**Interfaces:**
- Consumes: `SleepSessionController` (EnvironmentObject), `SettingsStore` (EnvironmentObject), `Formatters`, `Theme`.

Verhalten:
- `TonightView`: wenn `controller.isRunning` → `NightScreenView()`, sonst Start-Ansicht: Titel "Schlafprotokoll", Untertitel "Bereit für die Nacht", großer runder Button "Schlaf starten" (SF `moon.zzz.fill`), darunter "Einschlafverzögerung: 15 min" aus `settingsStore.settings.fallAsleepDelay` via `Formatters.minutes`. Tap → `showHints = true` (Sheet). `.alert("Fehler", isPresented: Binding auf controller.errorMessage != nil)` mit Text.
- `StartHintsSheet(onStart: () -> Void)`: Liste mit zwei bis drei Hinweisen: wenn `!controller.isCharging` → gelber Hinweis "Das iPhone lädt nicht. Schließe es ans Ladekabel an, damit die Aufnahme die ganze Nacht läuft." (SF `battery.25`); immer "Lege das iPhone mit dem Display nach unten auf die Matratze, in Kopfnähe." (SF `iphone.gen3.radiowaves.left.and.right`); "Während der Einschlafverzögerung werden noch keine Ereignisse gezählt." Button "Jetzt starten" → `Task { do { try await controller.start(mode: .night) } catch { controller.errorMessage = error.localizedDescription } }` und Sheet schließen. Button "Abbrechen".
- `NightScreenView`: Hintergrund `Theme.nightDim`, Textfarben gedimmt (`.white.opacity(0.6)`), große Uhrzeit `Formatters.clock(controller.elapsed)`, kleiner Text "Einschlafverzögerung läuft" solange `isInFallAsleepDelay`; Pegelbalken: `ProgressView(value: normalizedLevel)` mit `normalizedLevel = max(0, min(1, (liveLevel + 80) / 80))`; Zählerzeile mit `Theme.color(for:)`-Icons für snoring und speech aus `eventCounts`; großer Button "Aufwachen / Beenden" → `controller.stop()`.

- [ ] **Step 1: Views implementieren.** Jede View mit `#Preview` ohne Abhängigkeiten, die Hardware brauchen, wird weggelassen (Previews brauchen Environment-Objekte; stattdessen keine Previews).
- [ ] **Step 2: Statischer Check** (Binding für Alert: `Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })`).
- [ ] **Step 3: Commit** `Add Tonight tab with start hints and night screen`

---

### Task 16: Tab "Nächte": Liste, einfache Detailansicht, ClipPlayer

**Files:**
- Create: `SleepTracker/Features/Nights/NightsListView.swift`, `SleepTracker/Features/Nights/NightRowView.swift`, `SleepTracker/Features/NightDetail/NightDetailView.swift`, `SleepTracker/Features/NightDetail/EventRowView.swift`, `SleepTracker/Features/NightDetail/ClipPlayer.swift`, `SleepTracker/Session/SleepSession+Statistics.swift`
- Modify: `SleepTracker/App/RootTabView.swift` (Tab 2 → `NightsListView()`), `SleepTracker/App/AppDependencies.swift` (`clipPlayer` ergänzen und als EnvironmentObject injizieren in `SleepTrackerApp`)

**Interfaces (Produces):**

```swift
extension SleepSession {
    func statistics(now: Date = Date()) -> NightStatistics   // mappt events/epochs/gaps auf Summaries
}

@MainActor final class ClipPlayer: NSObject, ObservableObject {
    @Published private(set) var playingPath: String?
    @Published var errorMessage: String?
    init(fileStore: FileStore, sessionManager: AudioSessionManager = .shared)
    func toggle(relativePath: String)    // spielt oder pausiert; anderer Pfad -> stoppt alten, startet neuen; vor Start sessionManager.configureForPlayback()
    func stop()                          // player = nil, playingPath = nil, sessionManager.deactivate()
    // AVAudioPlayerDelegate über eine private Helper-Klasse `PlayerDelegateProxy: NSObject, AVAudioPlayerDelegate` (nicht MainActor), die audioPlayerDidFinishPlaying auf Main weiterreicht und `stop()` auslöst
}
```

Verhalten:
- `NightsListView`: `@Query(sort: \SleepSession.startDate, order: .reverse) var sessions: [SleepSession]`; `NavigationStack` mit Titel "Nächte"; leere Liste → `ContentUnavailableView("Noch keine Nächte", systemImage: "moon.zzz", description: Text("Starte heute Nacht die erste Aufnahme."))`; `ForEach` → `NavigationLink(value: session.id)` oder direkt `NavigationLink { NightDetailView(session: session) } label: { NightRowView(session:) }`; `.onDelete` → `dependencies.repository.deleteSession` je Index (Fehler → Alert).
- `NightRowView`: Zeile 1 `Formatters.nightDate(startDate)` + Badge "Test" wenn `isTest`, Badge "Unerwartet beendet" wenn Status; Zeile 2: Dauer, "Schnarchen 23 min", "Sprechen 4×", "Unruhe 12 %" aus `statistics()`.
- `NightDetailView(session:)`: `ScrollView` mit Abschnitt "Zusammenfassung" (Gesamtdauer, Schnarchzeit `Formatters.minutes` + `percent`, Sprech-Ereignisse, Husten nur wenn > 0, Unruhe-Index (Phase 1 zeigt "–" wenn keine Epoche unruhig markiert und Phase 2 füllt), Unterbrechungen), Abschnitt "Ereignisse": chronologische `EventRowView` je Ereignis; `.navigationTitle(Formatters.nightDate(...))`.
- `EventRowView(event:, onDelete:)`: Icon `Theme.color(for:)`, `type.germanName`, `Formatters.time(start)`–`time(end)`, Dauer, Konfidenz als Prozent; wenn `clipRelativePath != nil`: Button Play/Pause (`play.circle.fill` / `pause.circle.fill`), `disabled(sessionController.isRunning)`; Swipe-Action "Löschen" → `repository.deleteEvent`.

- [ ] **Step 1: Implementieren.**
- [ ] **Step 2: Statischer Check**: `@Query` benötigt `import SwiftData`; `.onDelete(perform:)` mit `IndexSet`; `AVAudioPlayer(contentsOf:)` wirft; `player.delegate` ist `weak` → Proxy im `ClipPlayer` stark halten. Einträge `unverified.md`: `ContentUnavailableView`-Initializer; `@Query`-Sortierung mit `order: .reverse`.
- [ ] **Step 3: Commit** `Add Nights list, night detail with event list and clip playback`

---

### Task 17: README (Phase 1) und Phase-1-Verifikation

**Files:**
- Modify: `README.md`
- Read: `docs/unverified.md`

- [ ] **Step 1: README schreiben** (deutsch) mit Abschnitten: 1) Kurzbeschreibung und Funktionsumfang (Phase 1 fertig, Phase 2 folgt), 2) Schritt-für-Schritt für den Mac mit englischen Menünamen (Xcode aus dem App Store, `brew install xcodegen`, `xcodegen generate`, `open SleepTracker.xcodeproj`, **Xcode > Settings > Accounts** Apple-ID, Target → **Signing & Capabilities** → Team, iPhone anschließen, **Settings > Privacy & Security > Developer Mode**, Run, **Settings > General > VPN & Device Management** vertrauen, 7-Tage-Hinweis bei kostenloser Apple-ID), 3) Empfohlene Nutzung (Ladekabel, Display nach unten in Kopfnähe, erster Test tagsüber über Testmodus sobald Phase 2 da ist), 4) "Ungeprüfte Stellen" = Inhalt von `docs/unverified.md` gruppiert nach Datei, 5) Bekannte Grenzen (keine Personentrennung, Genauigkeit des Apple-Klassifikators, Bewegung nur über Matratze, Clip-Dateinamen in UTC).
- [ ] **Step 2: Verifikation (ohne Compiler)**, Ergebnisse als Checkliste in die Commit-Message:
  - `find SleepTracker SleepTrackerTests -name '*.swift'` – jede Datei liegt unter einem in `project.yml` referenzierten Pfad.
  - `grep -rn "TODO\|FIXME\|fatalError" SleepTracker` → leer (außer dokumentiert).
  - `grep -rln "^import" ` – jede Datei, die `AVAudioPCMBuffer`/`AVAudioFormat` nutzt, importiert `AVFoundation`; SwiftData-Dateien `SwiftData`; SoundAnalysis-Datei `SoundAnalysis`; Views `SwiftUI`.
  - Info.plist mit `plistlib` geparst, Keys `NSMicrophoneUsageDescription`, `NSMotionUsageDescription`, `UIBackgroundModes` vorhanden.
  - Alle Protokoll-Methoden, die Fakes implementieren, stimmen mit den Protokollen überein (Signaturen per grep nebeneinanderstellen).
  - `python3 - <<'PY'` kleine Skript-Prüfung: jede Datei hat balancierte `{}`.
- [ ] **Step 3: Commit** `Complete phase 1: README with setup guide and unverified items`

---

# Phase 2

> **Änderung (Nutzerentscheidung, 2026-10-20, später revidiert):** Tasks 18 und 19 (Bewegung/Unruhe über CoreMotion) waren zunächst zurückgestellt; Task 20 wurde deshalb ohne Bewegungsspur gebaut. Der Nutzer hat danach entschieden, Tasks 18 und 19 **doch umzusetzen**. Reihenfolge ab hier: 18 → 19 → 21 → 26 (Bewegung in Zeitachse und Nachtanzeigen nachrüsten) → 22 (mit Sektion "Bewegung") → 23 (mit Sektion "Bewegung" im Debug-Bereich) → 24 → 25 → Final-Review. Task 21 behält die CSV-Spalten `motion_intensity`/`is_restless` (jetzt mit echten Werten). Die README (Task 25) beschreibt Bewegung als umgesetzte Funktion mit dem Hinweis, dass Accelerometer-Updates im Hintergrund ungeprüft sind (Spec B9).

### Task 18: Bewegungslogik: MotionEpochAggregator, MotionBaselineCalibrator, MotionAnalyzer (TDD)

**Files:**
- Create: `SleepTracker/Motion/MotionEpochAggregator.swift`, `SleepTracker/Motion/MotionBaselineCalibrator.swift`, `SleepTracker/Motion/MotionAnalyzer.swift`
- Test: `SleepTrackerTests/MotionTests.swift`

**Interfaces (Produces):**

```swift
struct RawMotionEpoch: Equatable { let index: Int; let start: TimeInterval; let intensity: Double }

struct MotionEpochAggregator {
    init(epochDuration: TimeInterval = 30, highPassAlpha: Double = 0.05)
    mutating func add(magnitude: Double, at time: TimeInterval) -> [RawMotionEpoch]   // EMA-Hochpass: erstes Sample setzt ema = magnitude (deviation 0); deviation = |magnitude - ema|; danach ema += alpha * (magnitude - ema); intensity = Summe der deviations je Epoche; Epochenlogik wie LevelEpochAggregator (leere Epochen überspringen, Zeit rückwärts -> aktuelle Epoche)
    mutating func finish() -> RawMotionEpoch?
}

struct MotionBaselineCalibrator {
    init(calibrationDuration: TimeInterval = 300, epochDuration: TimeInterval = 30, minimumBaseline: Double = 0.01)
    private(set) var baseline: Double?            // gesetzt, sobald calibrationDuration/epochDuration Epochen gesammelt sind: max(median(intensities), minimumBaseline)
    var isCalibrated: Bool { baseline != nil }
    mutating func add(_ epoch: RawMotionEpoch)    // ignoriert weitere Epochen nach Kalibrierung
}

struct MotionEpoch: Equatable { let index: Int; let start: TimeInterval; let intensity: Double; let isRestless: Bool }

struct MotionConfig: Equatable {
    var epochDuration: TimeInterval = 30
    var calibrationDuration: TimeInterval = 300
    var restlessFactor: Double = 3.0
    var highPassAlpha: Double = 0.05
    var minimumBaseline: Double = 0.01
    init(settings: AppSettings)   // restlessFactor, calibrationDuration aus settings
    init()                        // Defaults
}

struct MotionAnalyzer {
    init(config: MotionConfig)
    var baseline: Double? { get }
    mutating func add(magnitude: Double, at time: TimeInterval) -> [MotionEpoch]   // isRestless = calibrator.isCalibrated && intensity > baseline * restlessFactor; Epochen während der Kalibrierung sind nicht unruhig
    mutating func finish() -> MotionEpoch?
}
```

- [ ] **Step 1: Tests**:
  - `testConstantMagnitudeHasZeroIntensity`: 1.0 bei t = 0...31 (1 s Schritte) → eine RawMotionEpoch index 0 intensity 0.
  - `testDeviationAccumulates`: alpha 0.5: 1.0@0, 2.0@1, 1.0@2, dann 1.25@31 → Epoche 0 intensity 1.5 ± 1e-9 (dev 0, 1.0, 0.5).
  - `testAggregatorFinishFlushes`: ein Sample → finish liefert Epoche; zweites finish nil.
  - `testCalibratorUsesMedianAfterEnoughEpochs`: calibration 90, epoch 30: add 1, 5 → isCalibrated false; add 2 → baseline 2.
  - `testCalibratorAppliesMinimum`: Intensitäten 0, 0, 0 → baseline 0.01.
  - `testCalibratorMedianOfEvenCount`: calibration 60: 1, 3 → 2.
  - `testAnalyzerFlagsRestlessAfterCalibration`: config calibration 60, epoch 30, factor 3, alpha 1.0 (dev = Differenz zum vorherigen Sample): Samples so wählen, dass Epochen-Intensitäten [1, 1, 10, 2] entstehen (z. B. je Epoche ein Sprung von 0 auf x und zurück: Werte 0 bei t = 30k, x bei 30k + 1, 0 bei 30k + 2 ergeben intensity 2x; also x = 0.5, 0.5, 5, 1), Zeit bis 120 plus finish → isRestless == [false, false, true, false], baseline 1.
- [ ] **Step 2: Implementieren.**
- [ ] **Step 3: Statischer Check.**
- [ ] **Step 4: Commit** `Add motion epoch aggregation, baseline calibration and analyzer with tests`

---

### Task 19: MotionSource (CoreMotion), EpochMerger, Integration in den Controller

**Files:**
- Create: `SleepTracker/Motion/MotionSource.swift`, `SleepTracker/Session/EpochMerger.swift`
- Modify: `SleepTracker/Session/SleepSessionController.swift`, `SleepTracker/App/AppDependencies.swift`
- Test: `SleepTrackerTests/EpochMergerTests.swift`

**Interfaces (Produces):**

```swift
protocol MotionSourceDelegate: AnyObject {
    func motionSource(_ source: MotionSource, didSample magnitude: Double, at time: TimeInterval)   // time = Sekunden seit Session-Start; auf beliebiger Queue
}
protocol MotionSource: AnyObject {
    var delegate: MotionSourceDelegate? { get set }
    var isAvailable: Bool { get }
    func start(referenceDate: Date) throws
    func stop()
}
final class CoreMotionSource: MotionSource {
    init(updateInterval: TimeInterval = 0.05)
    // isAvailable = manager.isAccelerometerAvailable; start: manager.accelerometerUpdateInterval = updateInterval; manager.startAccelerometerUpdates(to: operationQueue) { data, error in guard let data else { return }; let a = data.acceleration; magnitude = sqrt(a.x*a.x + a.y*a.y + a.z*a.z); time = Date().timeIntervalSince(referenceDate) }; stop: manager.stopAccelerometerUpdates()
}
enum MotionError: LocalizedError { case unavailable }   // "Kein Bewegungssensor verfügbar."

struct EpochRecord: Equatable {
    let index: Int
    let start: TimeInterval
    let averageDecibels: Double
    let peakDecibels: Double
    let motionIntensity: Double
    let isRestless: Bool
}
struct EpochMerger {
    init(expectsMotion: Bool, lagTolerance: Int = 1)   // lagTolerance: wie viele Indizes ein halber Eintrag hinter dem neuesten liegen darf, bevor er mit Defaults geflusht wird
    mutating func add(level: LevelEpoch) -> [EpochRecord]
    mutating func add(motion: MotionEpoch) -> [EpochRecord]
    mutating func finish() -> [EpochRecord]              // alle Reste, Defaults: dB = LevelMeter.silenceFloor, motion 0/false; sortiert nach index
}
```

Controller-Änderungen: init bekommt `motionSourceFactory: () -> MotionSource?` (nil im Testmodus); Published `liveMotionMagnitude: Double`, `motionBaseline: Double?`, `isMotionActive: Bool`. Beim Start (`.night`): `motionSource = motionSourceFactory()`, falls `isAvailable` → `start(referenceDate: now)` (Fehler → nur `errorMessage`, Session läuft weiter), `motionAnalyzer = MotionAnalyzer(config: MotionConfig(settings:))`, `merger = EpochMerger(expectsMotion: motionActive)`. Motion-Samples werden auf eine eigene Serial Queue `motionQueue` geleitet, dort `motionAnalyzer.add` → Epochen → Main: `merger.add(motion:)`; Level-Epochen → Main: `merger.add(level:)`; jeder `EpochRecord` → `repository.addEpoch(...)` mit allen Feldern. `liveMotionMagnitude` höchstens 5×/s aktualisieren. `stop()`: `motionSource.stop()`, `motionAnalyzer.finish()` → `merger.add(motion:)`, dann `merger.finish()` → persistieren. `AppDependencies`: `motionSourceFactory: { CoreMotionSource() }`.

- [ ] **Step 1: Tests** (`EpochMergerTests`):
  - `testEmitsWhenBothHalvesPresent`: add(level 0) → []; add(motion 0) → [EpochRecord(index 0, avg, peak, intensity, restless)].
  - `testOrderIndependent`: motion zuerst, dann level → ein Record.
  - `testWithoutMotionEmitsImmediately`: expectsMotion false → add(level 0) → [Record mit motion 0/false].
  - `testFlushesLaggingLevelEntries`: expectsMotion true, lagTolerance 1: level 0, level 1 → []; level 2 → [Record index 0 mit motion 0/false]; motion 1 → [Record index 1].
  - `testFinishFlushesAllSorted`: level 3, motion 1 → finish → [index 1 (dB silenceFloor), index 3 (motion 0)].
- [ ] **Step 2: Implementieren.**
- [ ] **Step 3: Statischer Check** (`CMMotionManager`, `startAccelerometerUpdates(to:withHandler:)`, `CMAccelerometerData.acceleration` (`CMAcceleration` mit x/y/z); Eintrag `unverified.md`: Accelerometer-Updates im Hintergrund).
- [ ] **Step 4: Commit** `Add CoreMotion source, epoch merger and motion integration in the session controller`

---

### Task 20: Detailansicht: Zeitachsen-Diagramm und vollständige Zusammenfassung

**Files:**
- Create: `SleepTracker/Features/NightDetail/NightTimelineChart.swift`
- Modify: `SleepTracker/Features/NightDetail/NightDetailView.swift`

**Interfaces:**

```swift
struct TimelinePoint: Identifiable { let id: Int; let time: Date; let decibels: Double; let motion: Double; let isRestless: Bool }
struct TimelineEvent: Identifiable { let id: UUID; let type: SoundEventType; let start: Date; let end: Date }
struct NightTimelineChart: View {
    let points: [TimelinePoint]     // aus epochs sortiert
    let events: [TimelineEvent]
    let range: ClosedRange<Date>    // session start...end
}
```

Aufbau: `VStack` mit drei `Chart`s gleicher Breite und gemeinsamer x-Domain (`.chartXScale(domain: range)`):
1. Lautstärke: `LineMark(x: .value("Zeit", p.time), y: .value("dB", p.decibels))`, `.foregroundStyle(Theme.accent)`, `.chartYScale(domain: -80...0)`, Höhe 120.
2. Bewegung: `BarMark(x: .value("Zeit", p.time), y: .value("Bewegung", p.motion))` mit `.foregroundStyle(p.isRestless ? Color.orange : Color.gray)`, Höhe 80.
3. Ereignisse: `ForEach(events) { e in RectangleMark(xStart: .value("Start", e.start), xEnd: .value("Ende", e.end), y: .value("Typ", e.type.germanName)).foregroundStyle(Theme.color(for: e.type)) }`, Höhe 20 × Anzahl vorhandener Typen + 20; `.chartYAxis` mit Typnamen.
Legende unter dem Chart (farbige Punkte, deutsche Namen). Die Detailansicht zeigt den Chart zwischen Zusammenfassung und Ereignissen; Unruhe-Index wird jetzt aus `restlessPercentage`/`restlessPhaseCount` gezeigt ("12 % unruhig, 4 Phasen").

- [ ] **Step 1: Implementieren.**
- [ ] **Step 2: Statischer Check** (`import Charts`; `RectangleMark(xStart:xEnd:y:)` existiert; alternativ `xStart/xEnd/yStart/yEnd`; Eintrag in `unverified.md`).
- [ ] **Step 3: Commit** `Add night timeline chart to the detail view`

---

### Task 21: CSV-Export (TDD) und ShareLink

**Files:**
- Create: `SleepTracker/Persistence/CSVExporter.swift`
- Modify: `SleepTracker/Features/NightDetail/NightDetailView.swift`
- Test: `SleepTrackerTests/CSVExporterTests.swift`

**Interfaces (Produces):**

```swift
struct EventExportRow: Equatable { let type: SoundEventType; let start: Date; let end: Date; let maxConfidence: Double; let averageConfidence: Double; let clipRelativePath: String? }
struct EpochExportRow: Equatable { let timestamp: Date; let motionIntensity: Double; let isRestless: Bool; let averageDecibels: Double; let peakDecibels: Double }
enum CSVExporter {
    static let header = "record_type,timestamp,end,type,max_confidence,avg_confidence,clip,motion_intensity,is_restless,db_avg,db_peak"
    static func makeCSV(events: [EventExportRow], epochs: [EpochExportRow]) -> String   // Header, dann Epochen (nach timestamp), dann Ereignisse (nach start); Zeitstempel Formatters.csvTimestamp; Zahlen mit String(format: "%.3f") bzw. "%.1f" für dB; Booleans "true"/"false"; leere Felder leer; Zeilen mit "\n", Datei endet mit "\n"
    static func writeTemporaryFile(csv: String, fileName: String) throws -> URL   // FileManager.default.temporaryDirectory/fileName, atomar schreiben
    static func fileName(for start: Date) -> String   // "schlafprotokoll-yyyyMMdd.csv" (UTC)
}
```

- [ ] **Step 1: Tests**:
  - `testHeaderAndRows`: eine Epoche (t0 = 1970-01-01T00:00:00Z, motion 1.5, restless true, dB -42.25 / -30) und ein Ereignis (speech, t0+10 … t0+20, 0.9, 0.75, clip "Clips/a/b.m4a") → exakt:
    ```
    record_type,timestamp,end,type,max_confidence,avg_confidence,clip,motion_intensity,is_restless,db_avg,db_peak
    epoch,1970-01-01T00:00:00Z,,,,,,1.500,true,-42.3,-30.0
    event,1970-01-01T00:00:10Z,1970-01-01T00:00:20Z,speech,0.900,0.750,Clips/a/b.m4a,,,,
    ```
    (plus abschließendes `\n`).
  - `testEmptyYieldsHeaderOnly`.
  - `testRowsAreSorted`.
  - `testFileName`: `fileName(for: t0) == "schlafprotokoll-19700101.csv"`.
- [ ] **Step 2: Implementieren.** In `NightDetailView` Toolbar-Button mit `ShareLink(item: exportURL)` – `exportURL` wird beim Erscheinen der View per `task { }` erzeugt (`try? CSVExporter.writeTemporaryFile`); solange nil → Button deaktiviert.
- [ ] **Step 3: Statischer Check** (`ShareLink(item: URL)` erfordert `URL: Transferable`, vorhanden ab iOS 16; Eintrag in `unverified.md`).
- [ ] **Step 4: Commit** `Add CSV export with ShareLink in the night detail view`

---

### Task 22: Einstellungen-Tab

**Files:**
- Create: `SleepTracker/Features/Settings/SettingsView.swift`
- Modify: `SleepTracker/App/RootTabView.swift` (dritter Tab "Einstellungen", `gearshape.fill`)

Verhalten (`Form`, Bindings auf `settingsStore.settings`):
- Sektion "Aufnahme": Stepper "Einschlafverzögerung" 0–60 min in 5-min-Schritten (`fallAsleepDelay / 60`).
- Sektion "Erkennung": je `SoundEventType.allCases` ein `Slider` 0.3…0.95 Schritt 0.05 mit Label `germanName` und Wert als Prozent; Stepper "Mindestfenster" 1–5; Stepper "Ende-Lücke" 2–15 s; Stepper "Zusammenführen bis" 0–60 s; Stepper "Max. Ereignisdauer" 1–30 min.
- Sektion "Clips": Stepper "Sprech-Clips pro Nacht" 0–200 (Schritt 10); Stepper "Schnarch-Clips: Abstand" 1–60 min; Stepper "Schnarch-Clips pro Nacht" 0–100 (Schritt 5).
- Sektion "Bewegung": Stepper "Unruhe-Faktor" 1.5–10 Schritt 0.5 (`String(format: "%.1f")`).
- Sektion "Speicher": Text "Clips belegen X MB" (`ByteCountFormatter`, Wert aus `fileStore.clipsTotalSize()` beim Erscheinen), Button "Clips aller Nächte löschen" (destruktiv, `confirmationDialog`), Button "Alle Daten löschen" (destruktiv, `confirmationDialog` "Wirklich alle Nächte, Ereignisse und Clips löschen?") → `repository.deleteAllData()`; beide disabled während `sessionController.isRunning`.
- Sektion "Weitere": Button "Auf Standardwerte zurücksetzen"; `NavigationLink("Debug") { DebugView() }` (Task 23; in Task 22 ein Platzhalter-Text, den Task 23 ersetzt).
- Alle Stepper-Bindings über `Binding(get:set:)` mit Umrechnung (Minuten ↔ Sekunden).

- [ ] **Step 1: Implementieren.**
- [ ] **Step 2: Statischer Check** (`Stepper(value:in:step:)` mit `Double`-Bindings; `Slider(value:in:step:)`; `confirmationDialog(_:isPresented:titleVisibility:actions:)`).
- [ ] **Step 3: Commit** `Add settings tab with thresholds, clip limits, storage and reset`

---

### Task 23: FileAudioSource, Testmodus und Debug-Bereich

**Files:**
- Create: `SleepTracker/Audio/FileAudioSource.swift`, `SleepTracker/Features/Debug/DebugView.swift`, `SleepTracker/Features/Debug/TestModeView.swift`
- Modify: `SleepTracker/Session/SleepSessionController.swift` (`start(mode: .test(fileURL:))`), `SleepTracker/Features/Settings/SettingsView.swift` (NavigationLink → `DebugView()`), `SleepTracker/App/AppDependencies.swift`

**Interfaces (Produces):**

```swift
final class FileAudioSource: AudioSource {
    init(fileURL: URL, callbackQueue: DispatchQueue, chunkFrames: AVAudioFrameCount = 4096)
    // start(): file = try AVAudioFile(forReading: fileURL); monoFormat aus file.processingFormat.sampleRate; delegate.didBeginSegmentWith(monoFormat); dann auf callbackQueue eine Schleife: buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames); try file.read(into: buffer); wenn frameLength == 0 -> audioSourceDidFinish, Ende; sonst MonoDownmix.makeMonoBuffer -> didProduce(mono, framePosition); framePosition += frameLength; Schleife über callbackQueue.async (nicht rekursiv tief, sondern jede Iteration als eigener Block), Abbruch wenn `isStopped`
    // stop(): isStopped = true
}
```

Controller `start(mode: .test(fileURL:))`: keine Mikrofon-Berechtigung nötig; `isTestRun = true`; `settings` kopieren mit `fallAsleepDelay = 0`; Session mit `isTest: true`; Quelle `FileAudioSource(fileURL:, callbackQueue: queue)`; keine Bewegung; Clips wie gewohnt; `pipelineDidFinish` → `stop()`. Der Controller bekommt im init zusätzlich `fileSourceFactory: @escaping (URL, DispatchQueue) -> AudioSource` (AppDependencies: `{ FileAudioSource(fileURL: $0, callbackQueue: $1) }`).

`DebugView`: Sektionen: "Verfügbare Labels" (Liste aus `try? SoundClassifierService.knownLabels()`, Anzahl im Header, gemappte Labels mit Kategorie-Icon markiert; Fehler als Text); "Live-Klassifikation" (Top-5 aus `sessionController.topLabels` mit Konfidenz als Prozent, Hinweis "Nur während einer laufenden Aufnahme" wenn nicht running); "Bewegung" (`liveMotionMagnitude` mit 3 Dezimalen, `motionBaseline`); `NavigationLink("Testmodus") { TestModeView() }`.

`TestModeView`: Text-Erklärung, Button "Audiodatei wählen" → `.fileImporter(isPresented:, allowedContentTypes: [.audio], allowsMultipleSelection: false)`; Ergebnis-URL: `startAccessingSecurityScopedResource()`, Datei nach `FileManager.default.temporaryDirectory/testmode-<uuid>.<ext>` kopieren, `stopAccessingSecurityScopedResource()`, dann `try await sessionController.start(mode: .test(fileURL: copy))`; während `isRunning && isTestRun`: `ProgressView` mit "Analyse läuft …", Live-Zähler und Button "Abbrechen" (`stop()`); nach Ende Hinweis "Test-Session gespeichert. Sie erscheint unter Nächte mit dem Hinweis Test." Button disabled, wenn eine Nacht läuft.

- [ ] **Step 1: FileAudioSource implementieren.**
- [ ] **Step 2: Controller erweitern, DebugView, TestModeView.**
- [ ] **Step 3: Statischer Check** (`UTType.audio` braucht `import UniformTypeIdentifiers`; `fileImporter`-Result ist `Result<[URL], Error>`; `AVAudioFile(forReading:)`; `file.read(into:)` wirft; Einträge `unverified.md`).
- [ ] **Step 4: Commit** `Add file audio source, test mode and debug view`

---

### Task 24: CI-Workflow

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Workflow schreiben**: `on: [push, pull_request]`, `runs-on: macos-15`, Schritte: checkout; `brew install xcodegen`; `xcodegen generate`; Simulator-Auswahl per Skript:
  ```bash
  DEVICE=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; names=[dev['name'] for k,v in d.items() if 'iOS' in k for dev in v if dev['name'].startswith('iPhone')]; print(names[-1] if names else 'iPhone 16')")
  echo "DEVICE=$DEVICE" >> "$GITHUB_ENV"
  ```
  dann `xcodebuild -project SleepTracker.xcodeproj -scheme SleepTracker -destination "platform=iOS Simulator,name=$DEVICE" -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build test | tee build.log | xcpretty || (tail -200 build.log; exit 1)` – ohne `xcpretty`-Abhängigkeit: stattdessen `set -o pipefail; xcodebuild ... 2>&1 | tee build.log | grep -E "error:|warning: unre|Test Case|Executed|BUILD|TEST" ; exit ${PIPESTATUS[0]}`. Artefakt `build.log` hochladen (`actions/upload-artifact@v4`, `if: always()`).
- [ ] **Step 2: Statischer Check** (YAML parsebar; Pfade stimmen).
- [ ] **Step 3: Commit** `Add CI workflow building and testing on the iOS simulator`

---

### Task 25: README-Abschluss und Gesamtverifikation

**Files:**
- Modify: `README.md`, `docs/unverified.md`

- [ ] **Step 1: README aktualisieren**: Funktionsumfang Phase 2 (Bewegung, Diagramm, Einstellungen, CSV, Debug/Testmodus, CI), Abschnitt "CI" (Badge-Pfad `.github/workflows/build.yml`, was der Lauf prüft), Testmodus-Anleitung (Datei in "Dateien"-App ablegen, Einstellungen > Debug > Testmodus), "Ungeprüfte Stellen" komplett aus `docs/unverified.md`, "Bekannte Grenzen" ergänzen (Bewegung im Hintergrund, Kalibrierung in der Einschlafphase, Clip-Zeitstempel UTC).
- [ ] **Step 2: Gesamtverifikation** wie Task 17 Step 2 über alle Dateien, zusätzlich: jede `@Published`-Property wird nur auf dem Main Actor gesetzt (grep nach `DispatchQueue.main` / `Task { @MainActor` in Delegate-Callbacks des Controllers); jede Protokoll-Konformität vollständig (grep der Protokoll-Methoden gegen die Implementierungen); `project.yml`-Pfade; Workflow-YAML.
- [ ] **Step 3: Commit** `Complete phase 2: README, unverified items and verification`

---

### Task 26: Bewegung in Zeitachse und Nachtanzeigen nachrüsten (nach Task 19 und 21 ausführen)

Task 20 wurde gebaut, als Bewegung zurückgestellt war. Dieser Task ergänzt die Bewegungsspur im Diagramm und zeigt den Unruhe-Index an, sobald eine Nacht Bewegungsdaten hat.

**Files:**
- Modify: `SleepTracker/Session/SleepSession+Statistics.swift`, `SleepTracker/Features/NightDetail/NightTimelineChart.swift`, `SleepTracker/Features/NightDetail/NightDetailView.swift`, `SleepTracker/Features/Nights/NightRowView.swift`
- Test: `SleepTrackerTests/SleepSessionMotionTests.swift`

**Interfaces:**
- Consumes: `EpochSample.motionIntensity`, `EpochSample.isRestless` (Task 9, ab Task 19 mit echten Werten befüllt); `NightStatistics.restlessPercentage`, `restlessPhaseCount`, `totalEpochCount` (Task 13).
- Produces:

```swift
extension SleepSession {
    /// true, wenn mindestens eine Epoche eine Bewegungsintensität > 0 hat (Bewegung wurde aufgezeichnet).
    var hasMotionData: Bool { get }
}

struct TimelinePoint: Identifiable {          // erweitert
    let id: Int
    let time: Date
    let decibels: Double
    let motion: Double
    let isRestless: Bool
}

struct NightTimelineChart: View {             // erweitert
    let points: [TimelinePoint]
    let events: [TimelineEvent]
    let range: ClosedRange<Date>
    let showsMotion: Bool
}
```

Verhalten:
- Zwischen Lautstärke- und Ereignis-Chart ein drittes Chart "Bewegung" (Höhe 80), nur wenn `showsMotion`: je Epoche ein Balken über 30 s Breite, bevorzugt `RectangleMark(xStart: .value("Start", p.time), xEnd: .value("Ende", p.time.addingTimeInterval(30)), yStart: .value("Bewegung", 0.0), yEnd: .value("Bewegung", p.motion))`, Farbe `p.isRestless ? Color.orange : Color.gray`; gleiche x-Domain und x-Achse wie die anderen Charts; darunter eine kleine Legende "unruhig" (orange) / "ruhig" (grau).
- `NightDetailView`: `TimelinePoint` mit `motion: epoch.motionIntensity`, `isRestless: epoch.isRestless`; `showsMotion: session.hasMotionData`. Zusammenfassung "Unruhe-Index": wenn `hasMotionData` → "\(Formatters.percent(stats.restlessPercentage)) unruhig, \(stats.restlessPhaseCount) Phasen", sonst "–".
- `NightRowView`: "Unruhe \(Formatters.percent(stats.restlessPercentage))" wenn `hasMotionData`, sonst "Unruhe –".

- [ ] **Step 1: Tests** (`SleepSessionMotionTests`, `@MainActor`, In-Memory-Container wie in `SessionRepositoryTests`):
  - `testNoEpochsMeansNoMotionData`: Session ohne Epochen → `hasMotionData == false`.
  - `testZeroIntensityMeansNoMotionData`: drei Epochen mit `motionIntensity 0` → `false`.
  - `testPositiveIntensityMeansMotionData`: Epochen 0, 0.2, 0 → `true`.
- [ ] **Step 2: Implementieren.**
- [ ] **Step 3: Statischer Check** (`RectangleMark(xStart:xEnd:yStart:yEnd:)`-Labels; Eintrag in `unverified.md` mit Fallback `BarMark(x: .value("Zeit", p.time, unit: .minute), y: .value("Bewegung", p.motion))`).
- [ ] **Step 4: Commit** `Show motion in the night timeline and restlessness in night summaries`

---

## Self-Review-Notizen

- Spec-Abdeckung: Funktionen 1–9 → Tasks 15, 10/12, 11, 6, 7/8/10, 4, 18/19, 9, 16/20/21/22/23. CI → 24. README → 17/25. Dateischutz → 9 (FileStore) und 14 (Store-Datei). Inkrementelles Speichern → 14 (Insert + save je Ereignis/Epoche, zusätzlich 120-s-Timer). Stale-Sessions → 9/14. Testmodus → 23. Label-Mapping zentral → 5. Einschlafverzögerung → 6/12/14.
- Typkonsistenz: `ClipWriting.prepare(sampleRate:)` ist in Task 10 definiert; die Pipeline (Task 12) ruft es in `didBeginSegmentWith` auf. `AudioPipeline.Config.sessionStart: Date` ist in Task 12 definiert. `DetectorConfig(settings:countingStart:)` wird von der Pipeline genutzt. `SessionRepository.schema` wird von `AppDependencies` und den Tests genutzt.
- Review Focus: 1 → Task 4, 2 → Task 4 und 6, 3 → Task 13, 4 → Task 12, 5 → Task 2 und 9.
