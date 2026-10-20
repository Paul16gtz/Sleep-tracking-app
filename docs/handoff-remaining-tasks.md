# Übergabe: verbleibende Tasks (21–25, Final) und zurückgestellte Tasks (18, 19)

Dieses Dokument enthält alles, was eine andere Session braucht, um die restlichen Tasks des Plans
(`docs/plan.md`) nach demselben Verfahren auszuführen wie Tasks 1–20: pro Task ein frischer
Implementer-Subagent, danach ein Reviewer, bei Findings Fix-Runden mit Re-Review.
Für jeden Task stehen hier (1) der **Brief** (der Task-Text aus `docs/plan.md`, wörtlich) und
(2) der **Dispatch-Prompt** für den Implementer, so wie er in dieser Session verwendet worden wäre.
Am Ende stehen die generischen Reviewer- und Re-Review-Prompts.

Stand der Übergabe: Tasks 1–17 abgeschlossen und reviewt, Task 20 wird in der ursprünglichen Session
abgeschlossen. Nutzerentscheidung: Tasks 18 und 19 (Bewegung/Unruhe) sind zurückgestellt; ihre
Texte stehen in Teil B, damit sie später nachgerüstet werden können.

---

## Teil 0: Rahmen, der für jeden Dispatch gilt

### 0.1 Arbeitsbedingungen und Global Constraints (Inhalt von `constraints.md`)

## Arbeitsbedingungen (gelten für jeden Task)

- **Kein Compiler verfügbar.** Es gibt in dieser Umgebung weder `swift` noch `xcodebuild`. Jeder "Run"-Schritt der TDD-Schleife wird durch einen **statischen Check** ersetzt: Test und Implementierung noch einmal lesen und für jedes benutzte Symbol prüfen, dass es mit exakt dieser Signatur in diesem Plan oder im Code definiert ist (Typen, Optionals, Labels, `mutating`, `throws`, Imports). Der echte Lauf passiert später auf dem Mac und in CI.
- **Reihenfolge trotzdem TDD:** Test zuerst schreiben und committen können, dann Implementierung. Testdatei und Implementierung im selben Commit ist in Ordnung.
- **Unsicherheiten protokollieren:** Jede API-Stelle, bei der die Signatur nicht sicher ist, kommt mit Datei und Zeile als Stichpunkt nach `docs/unverified.md` (anlegen, falls nicht vorhanden). Task 17 und Task 25 übernehmen diese Liste in die README.
- **Konventionen:** Code, Bezeichner, Kommentare Englisch. UI-Strings Deutsch, direkt im Code (keine Localizable-Dateien). Keine `TODO`/`FIXME`, keine Platzhalter. Keine Force-Unwraps außer bei `floatChannelData` nach Format-Prüfung. Jede reine Logik-Datei beginnt mit `import Foundation`; Dateien, die SwiftUI, XCTest, SwiftData, AVFoundation, SoundAnalysis, CoreMotion oder Charts brauchen, beginnen mit diesem Import (Foundation wird re-exportiert); weitere Imports nur wo nötig. Reine Logik liegt in `struct`s ohne Framework-Imports außer Foundation. Klassen mit UI-State sind `@MainActor final class ... : ObservableObject`.
- **Commits:** Nach jedem Task ein Commit mit aussagekräftiger Message. Kein Modellname in Code oder Kommentaren; in Commit-Messages nur der vorgegebene Co-Authored-By-Footer.

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


## Verweise
- Spezifikation: docs/spec.md (Teil B enthält Entscheidungen zu Audio-Kategorie, Zeitmodell, Threading, Merging, Dateischutz).
- Unsicherheiten-Liste: docs/unverified.md (anhängen, nicht überschreiben).

### 0.2 Zusätzliche Entscheidungen aus dem Ledger, die diese Tasks betreffen

- Commit-Footer (als letzte Zeilen jeder Commit-Message):
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01XdQEbPkhuzCnrxa8rQgFYf
  ```
  Subagents auf anderen Modellen setzen ggf. ihren eigenen Modellnamen; das ist akzeptiert.
- Bewegung/Unruhe ist zurückgestellt: Task 22 ohne Sektion "Bewegung", Task 23 ohne Live-Bewegung
  im Debug-Bereich, Task 21 behält die CSV-Spalten `motion_intensity`/`is_restless` (Werte 0/false),
  UI zeigt den Unruhe-Index als "–". README (Task 25) nennt Bewegung als offene Funktion.
- Store-Pfad: `Application Support/SleepTracker/Store/SleepTracker.store`; Clips unter
  `Application Support/SleepTracker/Clips/<session-id>/`. Clip-Dateinamen in UTC.
- SwiftData-To-many-Arrays (`session.events`, `session.epochs`) sind ungeordnet: vor Anzeige,
  Statistik und Export immer sortieren.
- `SessionRepository.deleteAllData()` kann bei sehr vielen Daten den Main Actor blockieren:
  Task 22 zeigt währenddessen einen Fortschritts-/Wartehinweis.
- `SoundClassifierService` hat `static func knownLabels() throws -> [String]` und eine
  Instanz-Property `effectiveWindowDuration: TimeInterval` (für den Debug-Screen).
- `SleepSessionController` publiziert u. a. `isRunning`, `isTestRun`, `topLabels: [RankedLabel]`,
  `eventCounts`, `errorMessage`; `start(mode: .test(fileURL:))` wirft derzeit
  `ControllerError.unsupported` und wird in Task 23 implementiert. Der Controller-Init hat die
  Parameter `repository:fileStore:settingsStore:sourceFactory:classifierFactoryProvider:knownLabelsProvider:`;
  Task 23 ergänzt `fileSourceFactory`.
- Hinweis aus Review 14: `isRunning` wird false, bevor die letzten Epochen/Ereignisse gespeichert
  sind (eine Main-Queue-Runde später). UI, die beim Übergang einmalig rechnet, würde sie verpassen;
  SwiftData-Beobachtung (`@Query`, Model-Objekte) ist davon nicht betroffen.
- Deferred Minors aus den Reviews stehen in `.superpowers/sdd/plan/progress.md` (gitignored, nur in
  der ursprünglichen Session) und sollen vom Final-Review triagiert werden; die für diese Tasks
  relevanten sind oben aufgeführt.

### 0.3 Ablauf pro Task (Subagent-Driven Development)

1. BASE = `git rev-parse HEAD` notieren.
2. Implementer dispatchen (Prompt unten; Modell: Sonnet für reine Logik/Docs, Opus für
   SwiftUI/Framework-Integration). Der Implementer committet selbst, pusht nicht.
3. Review-Paket erzeugen: `git log --oneline BASE..HEAD`, `git diff --stat BASE..HEAD`,
   `git diff -U10 BASE..HEAD` in eine Datei; Reviewer mit Brief, Report-Datei und Diff-Datei
   dispatchen (generischer Reviewer-Prompt in Teil C).
4. Bei Critical/Important: Fix-Runde (Findings wörtlich an den Implementer), danach Re-Review
   (Prompt in Teil C), höchstens fünf Runden. Minors nur notieren.
5. Pushen: `git push -u origin claude/festive-pascal-nwjpr5`.

---

## Teil A: Tasks 21–25 und Final

### Task 21: CSV-Export (TDD) und ShareLink

#### Brief (aus docs/plan.md)

```markdown
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

```

#### Dispatch-Prompt für den Implementer (Modell: Sonnet)

```
You are implementing Task 21: CSV export (TDD) plus a ShareLink in the night detail view for the iOS app "Schlafprotokoll" (sleep tracker; Swift/SwiftUI/SwiftData, iOS 17).

## Task Description
Read your task brief first — it is your requirements, with exact signatures, the exact CSV header, number formats and test strings to use verbatim:
<WORKSPACE>/task-21-brief.md

Then read the project-wide working conditions and constraints:
<WORKSPACE>/constraints.md

Also read docs/spec.md Teil A section 9 (Export per ShareLink: CSV mit Epochen und Ereignissen der Nacht).

## Context — read these existing files; they are the source of truth for what you consume:
- SleepTracker/Shared/Formatters.swift — `Formatters.csvTimestamp(_:)` (ISO 8601, UTC, e.g. "1970-01-01T00:00:00Z").
- SleepTracker/Shared/SoundEventType.swift (rawValue used in the `type` column).
- SleepTracker/Persistence/Models.swift — SleepSession (startDate, endDate, events, epochs), SoundEvent (type, startDate, endDate, maxConfidence, averageConfidence, clipRelativePath), EpochSample (timestamp, motionIntensity, isRestless, averageDecibels, peakDecibels). SwiftData arrays are UNORDERED: sort before export (the exporter sorts again defensively).
- SleepTracker/Features/NightDetail/NightDetailView.swift (Task 16/20: a List with sections; you add a toolbar ShareLink).

Binding design points:
- `CSVExporter` is a pure `enum` in SleepTracker/Persistence/CSVExporter.swift with `import Foundation` only. Header exactly as in the brief. Rows: epochs first (sorted by timestamp), then events (sorted by start). Field formats: timestamps via `Formatters.csvTimestamp`; `max_confidence`/`avg_confidence`/`motion_intensity` with `String(format: "%.3f")`; `db_avg`/`db_peak` with `String(format: "%.1f")`; booleans "true"/"false"; empty fields empty; comma separator; lines joined with "\n" and a trailing "\n". Use `Locale(identifier: "en_US_POSIX")`-independent formatting: `String(format:)` uses the C locale for %f (decimal point), which is what we want — state this in a comment.
- Escaping: `clipRelativePath` can contain no commas (UUID + timestamp + type), but implement a minimal CSV escape anyway: if a field contains a comma, quote, or newline, wrap it in double quotes and double inner quotes. Add one test for it (`testFieldWithCommaIsQuoted`).
- Motion is deferred (user decision): the columns `motion_intensity` and `is_restless` stay in the header and are filled from the model (0.000/false today).
- `writeTemporaryFile(csv:fileName:) throws -> URL`: `FileManager.default.temporaryDirectory.appendingPathComponent(fileName)`, write atomically with `.utf8`.
- `fileName(for start: Date) -> String` = "schlafprotokoll-yyyyMMdd.csv" with a UTC `DateFormatter` (`en_US_POSIX`).
- NightDetailView: add `@State private var exportURL: URL?`; in `.task { }` (or `.onAppear`) build the rows from the session (sorted), call `CSVExporter.makeCSV` and `writeTemporaryFile`, assign the URL; toolbar: `ToolbarItem(placement: .topBarTrailing) { if let url = exportURL { ShareLink(item: url) { Label("Exportieren", systemImage: "square.and.arrow.up") } } else { Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary) } }`. Regenerate the file when an event is deleted (call the same builder after a successful delete). Keep everything else in the view unchanged.

Environment facts:
- NO Swift compiler here. TDD in order: write `SleepTrackerTests/CSVExporterTests.swift` first (all four brief tests plus `testFieldWithCommaIsQuoted`), then the implementation. Hand-trace `testHeaderAndRows` character by character against your formatting code (the expected string in the brief is binding, including `-42.3` for -42.25 under %.1f rounding — note: `String(format: "%.1f", -42.25)` yields "-42.2" or "-42.3" depending on binary representation; -42.25 is exactly representable, and C rounds half to even → "-42.2". Check this carefully: if your trace yields "-42.2", change the test input to -42.26 so the expected "-42.3" holds, and say so in the report; the brief's intent is a one-decimal dB value). Never claim it "compiles" or "passes"; write "statically checked".
- Imports: exporter `Foundation`; view adds nothing beyond SwiftUI. English identifiers/comments; German UI strings ("Exportieren"). No TODO/FIXME, no force unwraps.
- Every uncertainty → docs/unverified.md (append only; e.g. `ShareLink(item: URL)` availability with a file URL, `ToolbarItem(placement: .topBarTrailing)` on iOS 17 vs `.navigationBarTrailing`).
- Only create CSVExporter.swift and CSVExporterTests.swift and modify NightDetailView.swift (plus docs/unverified.md). `git add` with explicit paths (never `git add -A`).
- Work from the repo root on branch `claude/festive-pascal-nwjpr5`. Commit on this branch; do not push. Commit message from the brief ("Add CSV export with ShareLink in the night detail view") plus the footer from Teil 0.2 as the last lines.

## You Do Not Dispatch Subagents
Do all the work yourself; never spawn a subagent or reviewer.

## Self-Review
Header string identical to the brief; row order; number formats; trailing newline; empty input → header only; sorting; ShareLink disabled state while the file is not ready; file regenerated after deletes.

## Report Format
Write your full report to <WORKSPACE>/task-21-report.md (implemented, hand traces, TDD order, files, self-review, concerns, unverified entries). Then reply with ONLY (under 15 lines): Status (DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT), commits, one-line check summary, concerns, report path.
```

Reviewer-Schwerpunkte für Task 21: exakter Header-String und Zeilenformat gegen den Brief nachrechnen
(inkl. `%.1f`-Rundung von -42.25), Sortierung, Trailing-Newline, CSV-Escaping, `ShareLink(item: URL)`,
Toolbar-Placement, Regeneration nach Löschen, Tests schreiben vor Implementierung.

---

### Task 22: Einstellungen-Tab

#### Brief (aus docs/plan.md)

```markdown
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

```

**Abweichung durch Nutzerentscheidung:** Die Sektion "Bewegung" (Unruhe-Faktor) entfällt, solange
Bewegung zurückgestellt ist. Alle anderen Sektionen bleiben.

#### Dispatch-Prompt für den Implementer (Modell: Opus)

```
You are implementing Task 22: the "Einstellungen" tab for the iOS app "Schlafprotokoll" (sleep tracker; SwiftUI, iOS 17). UI language is German; code is English.

## Task Description
Read your task brief first — it is your requirements, with the exact German labels, ranges and steps to use verbatim:
<WORKSPACE>/task-22-brief.md

Then read the project-wide working conditions and constraints:
<WORKSPACE>/constraints.md

Also read docs/spec.md Teil A section 9 (tab 3 "Einstellungen") and the "Änderung" note at the top of "# Phase 2" in docs/plan.md.

## BINDING CHANGE (user decision): motion/restlessness is deferred. Omit the "Bewegung" section (no Unruhe-Faktor stepper). Everything else in the brief stays.

## Context — read these existing files; they are the source of truth for what you consume:
- SleepTracker/Shared/SettingsStore.swift (`@Published var settings: AppSettings`, `resetToDefaults()`), SleepTracker/Shared/AppSettings.swift (all fields; `threshold(for:)`, `setThreshold(_:for:)`), SleepTracker/Shared/SoundEventType.swift (`germanName`, `allCases`), SleepTracker/Shared/Formatters.swift, SleepTracker/Shared/Theme.swift.
- SleepTracker/App/AppDependencies.swift (`fileStore`, `repository`, `sessionController`, `clipPlayer`), SleepTracker/Persistence/FileStore.swift (`clipsTotalSize() -> Int64`, `deleteAllClips() throws`), SleepTracker/Persistence/SessionRepository.swift (`deleteAllData() throws`), SleepTracker/Session/SleepSessionController.swift (`isRunning`).
- SleepTracker/App/RootTabView.swift (add the third tab "Einstellungen", `systemImage: "gearshape.fill"`, content `SettingsView()`; keep tabs 1 and 2 unchanged).

Binding design points:
- `SettingsView` is a `NavigationStack { Form { … } }` with `.navigationTitle("Einstellungen")`, dark background like the other tabs (`.scrollContentBackground(.hidden)` + `.background(Theme.background)`).
- Bindings: build them with `Binding(get:set:)` on `settingsStore.settings` so each change goes through the store's `didSet` save. Minute values: `Binding<Double>(get: { settingsStore.settings.fallAsleepDelay / 60 }, set: { settingsStore.settings.fallAsleepDelay = $0 * 60 })`. Thresholds: `Binding<Double>(get: { settingsStore.settings.threshold(for: type) }, set: { settingsStore.settings.setThreshold($0, for: type) })`.
- Sections and controls exactly as the brief lists them (labels, ranges, steps): "Aufnahme" (Einschlafverzögerung 0–60 min, Schritt 5), "Erkennung" (one Slider 0.3…0.95 step 0.05 per SoundEventType with the value as percent; Steppers Mindestfenster 1–5, Ende-Lücke 2–15 s, Zusammenführen bis 0–60 s, Max. Ereignisdauer 1–30 min), "Clips" (Sprech-Clips pro Nacht 0–200 step 10, Schnarch-Clips: Abstand 1–60 min, Schnarch-Clips pro Nacht 0–100 step 5), "Speicher" (Text "Clips belegen X MB" via `ByteCountFormatter` from `fileStore.clipsTotalSize()` loaded in `.task`/`.onAppear` into `@State`; Button "Clips aller Nächte löschen" and Button "Alle Daten löschen", both `role: .destructive`, each behind a `confirmationDialog` — "Wirklich alle Nächte, Ereignisse und Clips löschen?" for the second — both `.disabled(sessionController.isRunning)`; show a `ProgressView` overlay with "Lösche …" while the deletion runs because `deleteAllData()` can take a while on the main actor; refresh the storage size afterwards), "Weitere" (Button "Auf Standardwerte zurücksetzen" → `settingsStore.resetToDefaults()`; `NavigationLink("Debug") { Text("Debug folgt") }` as a placeholder that Task 23 replaces with `DebugView()`).
- Steppers show their current value in the label, e.g. `Stepper("Einschlafverzögerung: \(Int(minutes)) min", value: binding, in: 0...60, step: 5)`; Sliders with a `Text` showing `Formatters.percent(value * 100)`.
- Error handling: deletion errors → `@State private var errorMessage: String?` with an `.alert("Fehler", …)`.
- Deleting all data while a clip is playing: call `clipPlayer.stop()` first.
- No `#Preview`.

Environment facts:
- NO Swift compiler here. Use mainstream SwiftUI API with exact labels: `Stepper(_:value:in:step:)` with Double bindings, `Slider(value:in:step:)`, `confirmationDialog(_:isPresented:titleVisibility:actions:message:)`, `Form`, `Section("…")`, `ByteCountFormatter`. List the APIs you relied on in the report. Never claim it "compiles"; write "statically checked". Every doubt → docs/unverified.md (append only, file:line).
- Imports: `SwiftUI`. English identifiers/comments; German UI strings verbatim. No TODO/FIXME, no force unwraps.
- Only create SleepTracker/Features/Settings/SettingsView.swift and modify RootTabView.swift (plus docs/unverified.md). `git add` with explicit paths only.
- Work from the repo root on branch `claude/festive-pascal-nwjpr5`. Commit; do not push. Commit message "Add settings tab with thresholds, clip limits, storage and reset" plus the footer from Teil 0.2.

## You Do Not Dispatch Subagents

## Self-Review
Every setting in the brief (except Bewegung) has a control with the stated range/step; every change persists through the store; destructive actions confirmed and disabled while recording; storage size refreshes after deletion; strings German.

## Report Format
Write your full report to <WORKSPACE>/task-22-report.md. Then reply with ONLY (under 15 lines): Status, commits, one-line check summary, concerns, report path.
```

Reviewer-Schwerpunkte für Task 22: Bindings schreiben über den Store (didSet → save), Ranges/Schritte
wie im Brief, keine Bewegungs-Sektion, Bestätigungsdialoge, `disabled` während Aufnahme,
Fortschrittsanzeige beim Löschen, Speicheranzeige, Platzhalter-Link "Debug".

---

### Task 23: FileAudioSource, Testmodus und Debug-Bereich

#### Brief (aus docs/plan.md)

```markdown
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

```

**Abweichung durch Nutzerentscheidung:** Die Sektion "Bewegung" (Live-Bewegungswerte, Basislinie)
im Debug-Bereich entfällt; der Controller bekommt keine `motionSourceFactory`.

#### Dispatch-Prompt für den Implementer (Modell: Opus)

```
You are implementing Task 23: FileAudioSource, the test mode and the Debug area for the iOS app "Schlafprotokoll" (sleep tracker; Swift/SwiftUI, iOS 17, AVFoundation, SoundAnalysis). This lets the user test the detection pipeline during the day with an audio file instead of the microphone.

## Task Description
Read your task brief first — it is your requirements:
<WORKSPACE>/task-23-brief.md

Then read the project-wide working conditions and constraints:
<WORKSPACE>/constraints.md

Also read docs/spec.md Teil A section 9 (Debug-Bereich, Testmodus) and Teil B section B8 (test mode design: same pipeline, FileAudioSource, fall-asleep delay 0, session isTest = true, no motion).

## BINDING CHANGE (user decision): motion/restlessness is deferred. The Debug view has NO "Bewegung" section; do not add any motion source or motion published properties to the controller.

## Context — read these existing files; they are the source of truth (do not guess signatures):
- SleepTracker/Audio/AudioSource.swift (`AudioSource`, `AudioSourceDelegate` incl. `audioSourceDidFinish`), SleepTracker/Audio/MonoDownmix.swift (`makeMonoBuffer(from:monoFormat:)`), SleepTracker/Audio/MicrophoneAudioSource.swift (reference implementation of the segment protocol).
- SleepTracker/Session/SleepSessionController.swift — `start(mode:)` with `SessionMode.test(fileURL:)` currently throwing `ControllerError.unsupported`; init parameters; the `pipelineDidFinish` path already calls `stop()`; `topLabels` published (throttled).
- SleepTracker/Session/AudioPipeline.swift (`Config.countingStart`), SleepTracker/App/AppDependencies.swift (controller construction), SleepTracker/Analysis/SoundClassifierService.swift (`knownLabels()`, `effectiveWindowDuration`), SleepTracker/Analysis/LabelMapping.swift (`candidates`, `init(knownLabels:)`, `type(for:)`), SleepTracker/Analysis/ClassificationWindow.swift (`RankedLabel`), SleepTracker/Features/Settings/SettingsView.swift (replace the "Debug" placeholder link with `DebugView()`), SleepTracker/Shared/Formatters.swift, Theme.swift, SoundEventType.swift.

Binding design points:
- `FileAudioSource: AudioSource` (SleepTracker/Audio/FileAudioSource.swift): `init(fileURL:callbackQueue:chunkFrames: AVAudioFrameCount = 4096)`; `start()`: `file = try AVAudioFile(forReading: fileURL)`; `monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate, channels: 1, interleaved: false)` (throw `FileAudioSourceError.unsupportedFormat` if nil); on `callbackQueue`: `delegate?.audioSource(self, didBeginSegmentWith: monoFormat)`, then a read loop where EACH iteration is its own `callbackQueue.async` block (no deep recursion, no tight loop blocking the queue): allocate `AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames)`, `try file.read(into: buffer)`; if `buffer.frameLength == 0` → `delegate?.audioSourceDidFinish(self)` and stop; else `MonoDownmix.makeMonoBuffer(from: buffer, monoFormat:)` → `delegate?.audioSource(self, didProduce: mono, framePosition: framePosition)`, `framePosition += Int64(buffer.frameLength)`, schedule the next iteration; abort when `isStopped`. Read errors → `delegate?.audioSource(self, didFailWith:)` then finish. `stop()` sets `isStopped = true` (thread-safe: set it on `callbackQueue` via async or use a lock; simplest: all state on `callbackQueue`).
- Controller: add init parameter `fileSourceFactory: @escaping (URL, DispatchQueue) -> AudioSource` (AppDependencies passes `{ FileAudioSource(fileURL: $0, callbackQueue: $1) }`). `start(mode: .test(fileURL:))`: no microphone permission; `isTestRun = true`; copy settings with `fallAsleepDelay = 0`; `createSession(..., isTest: true)`; source from `fileSourceFactory`; the rest identical to `.night` (clip writer, pipeline, timers). Make sure `stop()` resets `isTestRun`. Keep the existing `.night` flow byte-for-byte except for shared refactoring you need (state it in the report).
- `DebugView` (SleepTracker/Features/Debug/DebugView.swift): `Form` with sections: "Verfügbare Labels" (loads `try SoundClassifierService.knownLabels()` in `.task` into `@State`; header shows the count; each row shows the label and, when `LabelMapping(knownLabels:).type(for:)` maps it, the type icon + `germanName`; on error show the German message "Klassifikator nicht verfügbar: …"); "Live-Klassifikation" (Top-5 from `sessionController.topLabels` with `Formatters.percent(confidence * 100)`; when `!sessionController.isRunning` show "Nur während einer laufenden Aufnahme"); "Testmodus" with `NavigationLink("Testmodus") { TestModeView() }`. Title "Debug".
- `TestModeView` (SleepTracker/Features/Debug/TestModeView.swift): explanation text (German: what the test mode does, that the result appears under "Nächte" with the badge "Test"); Button "Audiodatei wählen" → `.fileImporter(isPresented:allowedContentTypes: [.audio], allowsMultipleSelection: false)`; on `.success(let urls)`: take the first URL, `let accessed = url.startAccessingSecurityScopedResource()`, copy to `FileManager.default.temporaryDirectory.appendingPathComponent("testmode-\(UUID().uuidString).\(url.pathExtension)")` (remove an existing file first), `if accessed { url.stopAccessingSecurityScopedResource() }`, then `Task { do { try await sessionController.start(mode: .test(fileURL: copy)) } catch { errorMessage = error.localizedDescription } }`; on `.failure` set `errorMessage`. While `sessionController.isRunning && sessionController.isTestRun`: `ProgressView()` with "Analyse läuft …", live counters (`eventCounts` for all types), Button "Abbrechen" → `sessionController.stop()`. After a run (track with `@State private var didRun`), show "Test-Session gespeichert. Sie erscheint unter Nächte mit dem Hinweis Test." The choose button is `.disabled(sessionController.isRunning)`. Alert "Fehler" for `errorMessage`.
- Replace the placeholder in SettingsView with `NavigationLink("Debug") { DebugView() }`.
- No `#Preview`.

Environment facts:
- NO Swift compiler here. Use documented API with exact labels; list each AVFoundation/SwiftUI API relied upon in the report: `AVAudioFile(forReading:)`, `processingFormat`, `read(into:)` throws, `AVAudioPCMBuffer(pcmFormat:frameCapacity:)` (optional), `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)` with `Result<[URL], Error>`, `UTType.audio` (needs `import UniformTypeIdentifiers`), security-scoped resource calls. Never claim it "compiles"; write "statically checked". Every doubt → docs/unverified.md (append only, file:line + fallback).
- Imports: FileAudioSource `AVFoundation`; views `SwiftUI` (+ `UniformTypeIdentifiers` in TestModeView). English identifiers/comments; German UI strings. No TODO/FIXME, no force unwraps.
- No unit tests are required for FileAudioSource (hardware-adjacent), but if you can add a small test that reads a generated WAV via `AVAudioFile(forWriting:settings:)` in the simulator test bundle and counts delivered frames, do it as `FileAudioSourceTests` (optional; say whether you added it).
- Only create/modify the files named here plus docs/unverified.md. `git add` with explicit paths only.
- Work from the repo root on branch `claude/festive-pascal-nwjpr5`. Commit; do not push. Commit message "Add file audio source, test mode and debug view" plus the footer from Teil 0.2.

## You Do Not Dispatch Subagents

## Self-Review
Segment protocol honored (didBeginSegment before the first buffer; framePosition from 0; didFinish exactly once; not after stop()); no deep recursion; test mode uses delay 0 and isTest = true; `.night` flow unchanged; Debug shows labels and mapping; security-scoped resource released; German strings.

## Report Format
Write your full report to <WORKSPACE>/task-23-report.md. Then reply with ONLY (under 15 lines): Status, commits, one-line check summary, concerns, report path.
```

Reviewer-Schwerpunkte für Task 23: Segment-Protokoll der `FileAudioSource` (Begin vor erstem Puffer,
Frame-Zähler, `didFinish` genau einmal, Abbruch bei `stop()`), keine Blockade der Queue, Controller-
Testpfad (Delay 0, isTest, Reset von `isTestRun`), `.fileImporter`-Signatur, Security-Scoped-Resource,
Debug-Label-Liste mit Mapping, keine Bewegungs-Sektion.

---

### Task 24: CI-Workflow

#### Brief (aus docs/plan.md)

```markdown
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

```

#### Dispatch-Prompt für den Implementer (Modell: Sonnet)

```
You are implementing Task 24: the GitHub Actions CI workflow for the iOS app "Schlafprotokoll" (XcodeGen project, iOS 17, unit tests on the simulator, no code signing).

## Task Description
Read your task brief first: <WORKSPACE>/task-24-brief.md
Then read the constraints: <WORKSPACE>/constraints.md
Also read project.yml (scheme name `SleepTracker`, targets `SleepTracker` and `SleepTrackerTests`) and docs/spec.md section "CI".

Binding design points:
- File: .github/workflows/build.yml. Trigger: `on: [push, pull_request]`. Job `build-and-test` on `runs-on: macos-15`. `timeout-minutes: 60`.
- Steps: `actions/checkout@v4`; `brew install xcodegen`; `xcodegen generate`; select a simulator with the python snippet from the brief (prefer the newest available iPhone; fall back to "iPhone 16"), export it via `$GITHUB_ENV`; optionally `xcodebuild -version` and `xcrun simctl list devices available | head -40` for diagnostics; then build and test:
  `set -o pipefail; xcodebuild -project SleepTracker.xcodeproj -scheme SleepTracker -destination "platform=iOS Simulator,name=$DEVICE" -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" -derivedDataPath build/DerivedData clean build test 2>&1 | tee build.log | grep -E "error:|warning: unre|Test Case|Executed|BUILD|TEST|\\*\\* " ; exit ${PIPESTATUS[0]}` (no xcpretty dependency). Use `shell: bash` for steps that need PIPESTATUS.
- Upload `build.log` as an artifact with `actions/upload-artifact@v4`, `if: always()`, name `xcodebuild-log`, `retention-days: 7`.
- Add a `concurrency` group keyed by `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true`.
- Keep the YAML minimal and commented in English. Validate it with `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml'))"` if PyYAML is available (else check indentation by eye) and record the result in the report.
- Append to docs/unverified.md: simulator name resolution on the runner image; whether `macos-15` ships an Xcode with iOS 17+/18 simulators; `CODE_SIGNING_ALLOWED=NO` sufficiency for the test host; possible need for `-skipPackagePluginValidation` (not expected: no packages).
- Also add a short "CI" paragraph to README.md under "Tests" (German): what the workflow does, where to find the log artifact. (Task 25 will finalize the README; keep this paragraph small.)

Environment facts: no Xcode here; nothing can be run. English comments in YAML; German README prose. Only create build.yml and modify README.md and docs/unverified.md. `git add` with explicit paths only. Work on branch `claude/festive-pascal-nwjpr5`; commit, do not push. Commit message "Add CI workflow building and testing on the iOS simulator" plus the footer from Teil 0.2.

## You Do Not Dispatch Subagents

## Report
Write <WORKSPACE>/task-24-report.md (YAML validation output, assumptions). Reply with ONLY: Status, commits, one-line summary, concerns, report path.
```

Reviewer-Schwerpunkte für Task 24: gültiges YAML, `set -o pipefail`/`PIPESTATUS` unter `shell: bash`,
Simulator-Auswahl robust, Artefakt immer hochgeladen, keine Signierung, Scheme-/Projektnamen stimmen
mit `project.yml` überein.

---

### Task 25: README-Abschluss und Gesamtverifikation

#### Brief (aus docs/plan.md)

```markdown
### Task 25: README-Abschluss und Gesamtverifikation

**Files:**
- Modify: `README.md`, `docs/unverified.md`

- [ ] **Step 1: README aktualisieren**: Funktionsumfang Phase 2 (Bewegung, Diagramm, Einstellungen, CSV, Debug/Testmodus, CI), Abschnitt "CI" (Badge-Pfad `.github/workflows/build.yml`, was der Lauf prüft), Testmodus-Anleitung (Datei in "Dateien"-App ablegen, Einstellungen > Debug > Testmodus), "Ungeprüfte Stellen" komplett aus `docs/unverified.md`, "Bekannte Grenzen" ergänzen (Bewegung im Hintergrund, Kalibrierung in der Einschlafphase, Clip-Zeitstempel UTC).
- [ ] **Step 2: Gesamtverifikation** wie Task 17 Step 2 über alle Dateien, zusätzlich: jede `@Published`-Property wird nur auf dem Main Actor gesetzt (grep nach `DispatchQueue.main` / `Task { @MainActor` in Delegate-Callbacks des Controllers); jede Protokoll-Konformität vollständig (grep der Protokoll-Methoden gegen die Implementierungen); `project.yml`-Pfade; Workflow-YAML.
- [ ] **Step 3: Commit** `Complete phase 2: README, unverified items and verification`

---

## Self-Review-Notizen

- Spec-Abdeckung: Funktionen 1–9 → Tasks 15, 10/12, 11, 6, 7/8/10, 4, 18/19, 9, 16/20/21/22/23. CI → 24. README → 17/25. Dateischutz → 9 (FileStore) und 14 (Store-Datei). Inkrementelles Speichern → 14 (Insert + save je Ereignis/Epoche, zusätzlich 120-s-Timer). Stale-Sessions → 9/14. Testmodus → 23. Label-Mapping zentral → 5. Einschlafverzögerung → 6/12/14.
- Typkonsistenz: `ClipWriting.prepare(sampleRate:)` ist in Task 10 definiert; die Pipeline (Task 12) ruft es in `didBeginSegmentWith` auf. `AudioPipeline.Config.sessionStart: Date` ist in Task 12 definiert. `DetectorConfig(settings:countingStart:)` wird von der Pipeline genutzt. `SessionRepository.schema` wird von `AppDependencies` und den Tests genutzt.
- Review Focus: 1 → Task 4, 2 → Task 4 und 6, 3 → Task 13, 4 → Task 12, 5 → Task 2 und 9.
```

#### Dispatch-Prompt für den Implementer (Modell: Sonnet)

```
You are implementing Task 25: the final README update and the whole-project verification pass (no compiler) for the iOS app "Schlafprotokoll".

## Task Description
Read your task brief first: <WORKSPACE>/task-25-brief.md
Then read the constraints: <WORKSPACE>/constraints.md
Read README.md (Phase-1 version from Task 17 plus the CI paragraph from Task 24), docs/unverified.md (complete list), docs/spec.md, and the "Änderung" note at the top of "# Phase 2" in docs/plan.md (motion deferred).

Your job:
1. Update README.md (German, English menu names):
   - "Funktionsumfang": Phase 2 items now present — Einstellungen-Tab, Zeitachsen-Diagramm (Lautstärke + Ereignisse), CSV-Export per ShareLink, Debug-Bereich mit Testmodus, CI-Workflow. State explicitly that Bewegung/Unruhe (CoreMotion) is NOT implemented (deferred by decision) and that the Unruhe-Index shows "–"; the data model keeps the fields for a later extension (see docs/handoff-remaining-tasks.md Teil B).
   - "CI": what `.github/workflows/build.yml` does (XcodeGen, simulator build + tests, log artifact) and that a red run is the first place to look for compile errors from the "Ungeprüfte Stellen".
   - "Testmodus": step by step — Audiodatei in der Dateien-App ablegen (z. B. AirDrop/iCloud Drive), Einstellungen > Debug > Testmodus > "Audiodatei wählen", warten bis "Test-Session gespeichert", Ergebnis unter Nächte mit Badge "Test"; Hinweis, dass die Einschlafverzögerung im Testmodus 0 ist und Clips wie gewohnt entstehen.
   - "Ungeprüfte Stellen": regenerate the section from the CURRENT docs/unverified.md (every entry, grouped, with file:line; keep the "zuerst prüfen" list and add the new compile-critical items from Tasks 20–24: Swift Charts marks/axis labels, ShareLink with a file URL, fileImporter/UTType, AVAudioFile reading, CI simulator selection). A script must confirm every file:line reference from docs/unverified.md appears in the README; put the script and its output in the report.
   - "Bekannte Grenzen": add Bewegung im Hintergrund nicht umgesetzt, Kalibrierung entfällt, Clip-Zeitstempel UTC, Klassifikator-Labels zur Laufzeit prüfen, Hintergrund-Neustart nach langen Unterbrechungen ungeprüft.
2. Whole-project verification (same checks as Task 17, over ALL files) — commands and outputs in the report:
   - every Swift file under SleepTracker/ or SleepTrackerTests/ (`project.yml` source roots);
   - `grep -rn "TODO\|FIXME\|fatalError" SleepTracker SleepTrackerTests` → none;
   - import check per framework (AVFoundation, SwiftData, SoundAnalysis, SwiftUI, Charts, Combine, UIKit, UniformTypeIdentifiers) with grep;
   - Info.plist keys via plistlib;
   - brace/paren balance script over all Swift files;
   - protocol conformance grep (AudioSource, AudioSourceDelegate, SoundClassifying, SoundClassifierDelegate, ClipWriting, AudioPipelineDelegate) against real and fake implementers, now including FileAudioSource;
   - every `@Published` property is mutated only inside `@MainActor` types or inside `DispatchQueue.main.async`/`Task { @MainActor in }` blocks: grep the controller, ClipPlayer and views and list each off-main mutation you find (expected none);
   - `.github/workflows/build.yml` parses as YAML; `project.yml` parses as YAML.
   If a check fails, do NOT fix code; report precisely (file:line) as a concern.
3. Commit README.md and docs/unverified.md (if you normalized it) with message "Complete phase 2: README, unverified items and verification" plus the footer from Teil 0.2; do not push; `git add` with explicit paths only.

Environment facts: no compiler; never claim the project compiles or runs. German prose, English menu names. Do not modify Swift files.

## You Do Not Dispatch Subagents

## Report
Write <WORKSPACE>/task-25-report.md (README outline, all verification commands + outputs, violations, files changed, concerns). Reply with ONLY: Status, commits, one-line verification summary, concerns, report path.
```

Reviewer-Schwerpunkte für Task 25: Vollständigkeit der "Ungeprüften Stellen" gegen docs/unverified.md,
Faktentreue (Pfade, Funktionsumfang ohne Bewegung), Verifikationsergebnisse plausibel (eine oder zwei
Prüfungen selbst wiederholen), keine Behauptung, dass etwas kompiliert.

---

### Final: Whole-Branch-Review, eine Fix-Welle, Abschluss

Kein Brief im Plan; dies ist der letzte Schritt des SDD-Verfahrens (`superpowers:subagent-driven-development`,
Abschnitt "Final Review" und "Finish"), danach `superpowers:finishing-a-development-branch`.

#### Ablauf

1. `MERGE_BASE=$(git merge-base origin/main HEAD)`; Review-Paket über den gesamten Branch erzeugen
   (`git log --oneline MERGE_BASE..HEAD`, `git diff --stat MERGE_BASE..HEAD`, `git diff -U10 MERGE_BASE..HEAD`
   in eine Datei; das Paket ist groß — der Reviewer liest es in Durchgängen).
2. Final-Reviewer auf dem leistungsfähigsten verfügbaren Modell dispatchen (Prompt unten).
3. Bei Findings: GENAU EINE Fix-Welle (ein Subagent mit der kompletten Findings-Liste), danach genau
   ein Re-Review über den Fix-Bereich (Re-Review-Prompt aus Teil C, mit der Findings-Liste).
4. Restliche Findings adjudizieren (parken mit Begründung oder als Ruling festhalten).
5. Alle Rulings sammeln und dem Nutzer ausgeben; Workspace `.superpowers/sdd/plan` löschen;
   pushen; `superpowers:finishing-a-development-branch` aufrufen (Optionen: Branch so lassen /
   PR erstellen — PR nur auf ausdrücklichen Wunsch).

#### Dispatch-Prompt für den Final-Reviewer (Modell: das stärkste verfügbare)

```
You are a Senior Code Reviewer with expertise in iOS (Swift 5 language mode, SwiftUI, SwiftData, AVFoundation, SoundAnalysis, Swift Charts) and concurrency. Review the complete branch of the personal iOS app "Schlafprotokoll" (sleep tracker: records all night with the screen locked, classifies snoring/speech with SoundAnalysis, stores clips and SwiftData sessions, shows nights with a chart and CSV export). Nothing on this branch has ever been compiled: the environment has no Xcode. Your single most valuable output is a list of things Xcode or XCTest would reject or that would misbehave at runtime on a device, ranked by severity, plus a triage of the deferred minor findings.

## What was implemented
Read docs/spec.md (the binding spec; Teil B holds design decisions), docs/plan.md (tasks 1–25; tasks 18/19 deferred by the user — motion/restlessness is NOT implemented, the Unruhe-Index shows "–"), README.md (setup, "Ungeprüfte Stellen" = known API uncertainties — do not re-report those as findings unless you can say concretely that the code is wrong and how to fix it; DO report any uncertain API that is NOT listed there), docs/unverified.md.

## Deferred minors and rulings to triage
Read <WORKSPACE>/progress.md (the SDD ledger): every line starting with "Task N: minor (deferred)" is a known small issue; every "Ruling:" is a controller decision. Triage the minors: which must be fixed before this branch is handed to the user for the first device build, which can wait. Say so explicitly per item (by task number and one-liner).

## Git range
Base: <MERGE_BASE>   Head: <HEAD>
Diff file: <REVIEW_PACKAGE_PATH> (commit list, stat, full diff with context). It is large: review it in passes (Shared/Audio/Analysis → Persistence/Session → Features/App → tests/docs) and say which pass found what. Read-only on this checkout; do not mutate the working tree, index, HEAD or branches. You may read any file in the repo.

## What to check
- Plan alignment: all planned functionality present (phases 1 and 2 minus motion); deviations justified by a ledger ruling or clearly improvements.
- Compile hazards across file boundaries: every call site matches its declaration (labels, optionals, throws, mutating, static/instance); protocol conformances complete (real and fake); actor isolation (@MainActor classes conforming to non-isolated protocols → nonisolated witnesses; @Published mutated only on main); imports; Swift 5 mode with minimal strict concurrency.
- Runtime hazards on device: background recording across lock/interruptions/route changes; audio session category switches between recording and clip playback; SwiftData main-context usage, cascade deletes, file protection; clip files and the ring buffer memory; timers.
- Tests: do they verify behavior (hand-check two or three expectations against the implementation); are the fakes faithful to the real protocols; is anything asserted that cannot be true.
- Security/privacy: no network, no analytics, files protected, microphone usage string present.
- Documentation: README complete and honest (no "works"/"compiles" claims); "Ungeprüfte Stellen" complete vs the code.

## The spec is a vision document
For behavior the spec is silent on, judge by what a reasonable person using this software would expect; a spec's silence is not permission.

## Declined to judge
Before your verdict, list every behavior you considered and set aside as outside the plan or spec, one line each, with the reason.

## You Do Not Dispatch Subagents
Do all of this review yourself.

## Output Format
### Strengths
### Issues
#### Critical (Must Fix)   — compile-breaking across files, data loss, crash, recording silently stops
#### Important (Should Fix)
#### Minor (Nice to Have)
For each issue: file:line, what's wrong, why it matters, how to fix.
### Deferred-minor triage
### Recommendations
### Declined to judge
### Assessment
**Ready to merge?** [Yes | No | With fixes]
**Reasoning:** [1-2 sentences]
```

#### Dispatch-Prompt für die eine Fix-Welle (Modell: Opus)

```
You own the single fix wave after the final whole-branch review of the iOS app "Schlafprotokoll" (Swift 5 mode, iOS 17; no compiler available here). Read docs/spec.md Teil B, <WORKSPACE>/constraints.md and the final review report at <FINAL_REVIEW_REPORT_PATH>. Fix EVERY Critical and Important finding listed below and the deferred minors the reviewer marked "fix before first device build". Do not widen scope beyond the findings. Keep public types and protocol surfaces unless a finding requires a change; if you must change one, update every conformer and caller and say so.

## Findings (verbatim)
<COMPLETE_FINDINGS_LIST>

Rules: statically re-check every edited line (exact API labels, optionals, isolation) and list the checks per finding; keep tests green by reasoning (hand-trace any test whose code or expectation you touch); update docs/unverified.md and README "Ungeprüfte Stellen" if an entry changes; one commit per logical group or one commit overall with message "Address final review findings" plus the footer from Teil 0.2; `git add` with explicit paths only; do not push. Write a fix report to <WORKSPACE>/final-fix-report.md: per finding what changed (file:line), checks run, open items you could not fix and why. You do not dispatch subagents. Reply with ONLY: Status, commits, one-line summary, open items, report path.
```

---

## Teil B: Zurückgestellte Tasks 18 und 19 (Bewegung/Unruhe über CoreMotion)

Diese Tasks waren im Plan vorgesehen und sind durch Nutzerentscheidung zurückgestellt. Die Briefs
stehen unverändert hier; die Dispatch-Prompts berücksichtigen den Stand des Codes nach Task 20
(Controller mit Stop-Flow aus Task 14, zwei Charts, Einstellungen ohne Bewegungs-Sektion).
Beim Nachrüsten zusätzlich nötig: (a) Task-22-Sektion "Bewegung" mit Stepper "Unruhe-Faktor" 1.5–10
Schritt 0.5 (`settings.restlessFactor`); (b) Task-23-Debug-Sektion "Bewegung" mit
`liveMotionMagnitude` (3 Dezimalen) und `motionBaseline`; (c) Task-20-Chart um das Bewegungs-
BarMark erweitern (Höhe 80, `isRestless ? .orange : .gray`) und `TimelinePoint` um
`motion: Double`, `isRestless: Bool` ergänzen; (d) UI: "Unruhe –" nur noch, wenn keine Epochen
vorliegen, sonst "X % unruhig, N Phasen"; (e) README: Bewegung als Funktion aufnehmen und
`NSMotionUsageDescription` erklären (CMMotionManager-Accelerometer braucht keinen Prompt).

### Task 18: Bewegungslogik: MotionEpochAggregator, MotionBaselineCalibrator, MotionAnalyzer (TDD)

#### Brief (aus docs/plan.md)

```markdown
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

```

#### Dispatch-Prompt für den Implementer (Modell: Sonnet)

```
You are implementing Task 18: the pure motion/restlessness logic (MotionEpochAggregator, MotionBaselineCalibrator, MotionAnalyzer) with TDD for the iOS app "Schlafprotokoll" (sleep tracker; Swift, iOS 17). This re-activates a deferred feature; nothing hardware-related is in this task.

## Task Description
Read your task brief first — it is your requirements, with exact signatures, values and test cases to use verbatim:
<WORKSPACE>/task-18-brief.md
Then read the constraints: <WORKSPACE>/constraints.md
Also read docs/spec.md Teil A section 7 (Bewegung/Unruhe) and Teil B section B9.

## Context
Existing code you depend on (read them): SleepTracker/Shared/AppSettings.swift (`restlessFactor: Double` default 3.0, `motionCalibrationDuration: TimeInterval` default 300), SleepTracker/Audio/LevelEpochAggregator.swift (the epoch index logic to mirror: index = floor(time / epochDuration) clamped to ≥ current; empty epochs skipped; time going backwards stays in the current epoch; `finish()` flushes once). The later Task 19 feeds `MotionAnalyzer.add(magnitude:at:)` with accelerometer magnitudes (in g, ~20 Hz) and session-relative seconds, and persists `MotionEpoch`s merged with level epochs.

Semantics (binding): EMA high-pass with `highPassAlpha` (first sample sets ema = magnitude, deviation 0; afterwards deviation = |magnitude − ema| computed BEFORE updating ema, then ema += alpha·(magnitude − ema)); intensity = sum of deviations per epoch; the calibrator collects the first `calibrationDuration / epochDuration` epochs (integer, at least 1) and sets baseline = max(median(intensities), minimumBaseline) (median of an even count = mean of the two middle values); epochs during calibration are never restless; afterwards `isRestless = intensity > baseline × restlessFactor`.

Environment facts: NO Swift compiler here; TDD in order (tests first); every "run" is a static check with hand traces of every test (compute the sample sequences for `testAnalyzerFlagsRestlessAfterCalibration` explicitly: alpha 1.0 makes deviation = |current − previous|). Pure logic files: `import Foundation` only. English identifiers/comments. No TODO/FIXME, no force unwraps. Only create the four files the brief names (three sources, one test file); `git add` with explicit paths only. Work on branch `claude/festive-pascal-nwjpr5`; commit, do not push; commit message from the brief plus the footer from Teil 0.2.

## You Do Not Dispatch Subagents

## Self-Review
All brief tests present with exact names; `MotionConfig` has both inits; `RawMotionEpoch`/`MotionEpoch` Equatable with fields in the brief's order; calibrator ignores epochs after calibration; `MotionAnalyzer.finish()` runs the flushed epoch through the same restless rule.

## Report
Write <WORKSPACE>/task-18-report.md (implemented, hand traces, TDD order, files, self-review, concerns). Reply with ONLY: Status, commits, one-line check summary, concerns, report path.
```

Reviewer-Schwerpunkte für Task 18: Handtraces aller Tests (insbesondere Median bei gerader Anzahl,
`minimumBaseline`, Epochen während der Kalibrierung nicht unruhig), Epochenindex-Logik identisch zum
LevelEpochAggregator, Interfaces exakt wie im Brief.

### Task 19: MotionSource (CoreMotion), EpochMerger, Integration in den Controller

#### Brief (aus docs/plan.md)

```markdown
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

```

#### Dispatch-Prompt für den Implementer (Modell: Opus)

```
You are implementing Task 19: the CoreMotion source, the EpochMerger and the motion integration in SleepSessionController for the iOS app "Schlafprotokoll" (sleep tracker; Swift, iOS 17). Task 18 (pure motion logic) must already be merged.

## Task Description
Read your task brief first — it is your requirements, with exact signatures and test cases to use verbatim:
<WORKSPACE>/task-19-brief.md
Then read the constraints: <WORKSPACE>/constraints.md
Also read docs/spec.md Teil A section 7 and Teil B sections B4 (threading), B9 (motion in background: unverified; fallback CMSensorRecorder).

## Context — read these existing files (source of truth):
- SleepTracker/Motion/MotionAnalyzer.swift (`MotionAnalyzer(config:)`, `add(magnitude:at:) -> [MotionEpoch]`, `finish() -> MotionEpoch?`, `baseline`), SleepTracker/Motion/MotionEpochAggregator.swift (`MotionEpoch`), SleepTracker/Audio/LevelEpochAggregator.swift (`LevelEpoch`), SleepTracker/Audio/LevelMeter.swift (`silenceFloor`).
- SleepTracker/Session/SleepSessionController.swift — read it fully. It is `@MainActor`, conforms to `AudioPipelineDelegate` with `nonisolated` witnesses that hop via `DispatchQueue.main.async`; the stop flow keeps the stopped session alive until in-flight main-queue hops have run (FIFO), then releases it. Level epochs currently go straight to `repository.addEpoch(... motionIntensity: 0, isRestless: false)`. You replace that with the merger.
- SleepTracker/App/AppDependencies.swift (controller construction; add `motionSourceFactory: { CoreMotionSource() }`), SleepTracker/Persistence/SessionRepository.swift (`addEpoch(to:timestamp:averageDecibels:peakDecibels:motionIntensity:isRestless:)`), SleepTracker/Shared/AppSettings.swift (`restlessFactor`, `motionCalibrationDuration`).

Binding design points:
- `MotionSource`/`MotionSourceDelegate`/`CoreMotionSource`/`MotionError` exactly as the brief. `CoreMotionSource` uses `CMMotionManager`, `isAccelerometerAvailable`, `accelerometerUpdateInterval = 0.05`, `startAccelerometerUpdates(to: OperationQueue, withHandler:)` with a dedicated serial `OperationQueue` (`maxConcurrentOperationCount = 1`, `qualityOfService = .utility`); magnitude = sqrt(x²+y²+z²) from `data.acceleration`; time = `Date().timeIntervalSince(referenceDate)`; `stop()` → `stopAccelerometerUpdates()`. Not started in test mode.
- `EpochMerger` exactly as the brief (pure struct, Foundation only, with the `lagTolerance` flush rule and `finish()` sorted by index; defaults dB = `LevelMeter.silenceFloor`, motion 0/false).
- Controller: new init parameter `motionSourceFactory: @escaping () -> MotionSource?` (AppDependencies passes `{ CoreMotionSource() }`; tests/test mode pass `{ nil }` or the controller skips motion when `isTestRun`). New published: `liveMotionMagnitude: Double` (≤ 5 updates/s), `motionBaseline: Double?`, `isMotionActive: Bool`. On `.night` start: create the source; if `isAvailable`, `start(referenceDate: now)` (errors → `errorMessage` only); `motionAnalyzer = MotionAnalyzer(config: MotionConfig(settings:))`; `merger = EpochMerger(expectsMotion: isMotionActive)`. Motion samples arrive on the OperationQueue: a `nonisolated` delegate witness hops to a dedicated serial `DispatchQueue` ("sleeptracker.motion") where `motionAnalyzer.add` runs (keep the analyzer state on that queue only), and completed `MotionEpoch`s hop to main (`DispatchQueue.main.async`) into `merger.add(motion:)`; level epochs (already on main) go into `merger.add(level:)`; every `EpochRecord` → `repository.addEpoch(...)` with all fields. `liveMotionMagnitude` updated from the motion queue to main at most 5×/s. `stop()`: `motionSource.stop()`, then on the motion queue `motionAnalyzer.finish()` → hop to main → `merger.add(motion:)`, then `merger.finish()` → persist — and this must happen BEFORE the stopped session is released: enqueue it in the same main-queue FIFO before the release block (read the existing stop flow and extend it; explain the ordering in the report).
- Keep the existing audio paths unchanged.

Environment facts: NO Swift compiler. TDD for the pure part: write `SleepTrackerTests/EpochMergerTests.swift` first (all five brief tests), then EpochMerger; then the CoreMotion source and the controller changes. Imports: MotionSource.swift `CoreMotion` + Foundation; EpochMerger Foundation only. English identifiers/comments; German error strings ("Kein Bewegungssensor verfügbar."). No TODO/FIXME, no force unwraps. Append docs/unverified.md: accelerometer updates in the background while audio keeps the app alive (B9), `startAccelerometerUpdates(to:withHandler:)` signature, `CMAcceleration` fields, main-actor hops ordering at stop. Only create/modify the files named in the brief plus docs/unverified.md; `git add` with explicit paths only. Branch `claude/festive-pascal-nwjpr5`; commit, do not push; commit message from the brief plus the footer from Teil 0.2.

## You Do Not Dispatch Subagents

## Self-Review
Merger emits exactly once per index; lag flush rule; no motion in test mode; analyzer state confined to the motion queue; all published properties mutated on main; final motion epoch persisted before the session is released; `AppDependencies` updated.

## Report
Write <WORKSPACE>/task-19-report.md. Reply with ONLY: Status, commits, one-line check summary, concerns, report path.
```

Reviewer-Schwerpunkte für Task 19: Thread-Zuständigkeiten (OperationQueue → Motion-Queue → Main),
Stop-Reihenfolge gegenüber der Session-Freigabe, Merger-Tests (Lag-Flush, Sortierung in `finish()`),
CoreMotion-Signaturen, kein Start im Testmodus.

---

## Teil C: Generische Reviewer- und Re-Review-Prompts

### C.1 Task-Reviewer (nach jedem Implementer)

```
You are reviewing one task's implementation: first whether it matches its requirements, then whether it is well-built. This is a task-scoped gate, not a merge review.

## What Was Requested
Read the task brief: <WORKSPACE>/task-<N>-brief.md
Global constraints — read: <WORKSPACE>/constraints.md
<task-specific binding points and controller rulings; the "Reviewer-Schwerpunkte" above>

## What the Implementer Claims They Built
Read the implementer's report: <WORKSPACE>/task-<N>-report.md

## Diff Under Review
**Base:** <BASE_SHA>   **Head:** <HEAD_SHA>
**Diff file:** <DIFF_FILE>
Read the diff file once — it contains the commit list, a stat summary, and the full diff with surrounding context, and it is your view of the change. Do not re-run git commands. You may read a consumed source file to verify a call site (name the check). Read-only: do not mutate the working tree, the index, HEAD or branches.

## You Do Not Dispatch Subagents
Do all of this review yourself.

## Do Not Trust the Report
Treat the implementer's report as unverified claims. Verify against the diff. No compiler exists in this environment: the expected evidence is static checking and hand traces; your main value is catching what Xcode would reject (wrong API labels, missing members, isolation errors) and spec deviations. Hand-trace every test the brief specifies.

## Part 1: Spec Compliance — Missing / Extra / Misunderstood with file:line; ⚠️ for anything not verifiable from the diff.
## Part 2: Code Quality — structure, error handling, DRY, edge cases, tests verify real behavior.

Your final message is the report itself: begin directly with the spec-compliance verdict; every line is a verdict, a finding with file:line, or a check you ran. No preamble, no closing summary.

## Calibration
Important = cannot be trusted until fixed (compile-breaking code, missing member, wrong value/string from the brief, missed requirement, test asserting nothing). Polish = Minor. Plan-mandated defects → Important, labeled plan-mandated.

## Output Format
### Spec Compliance
- ✅ Spec compliant | ❌ Issues found: [...]
- ⚠️ Cannot verify from diff: [...]
### Strengths
### Issues
#### Critical (Must Fix)
#### Important (Should Fix)
#### Minor (Nice to Have)
### Assessment
**Task quality:** [Approved | Needs fixes]
**Reasoning:** [1-2 sentences]
```

### C.2 Fix-Runde (an den ursprünglichen Implementer, sonst frischer Implementer mit Report-Datei)

```
Task <N> review came back with the findings below; please fix them (fix round <R> of 5), then append a "Fix round <R>" section to <WORKSPACE>/task-<N>-report.md (what changed per finding, the static checks re-run — and the covering tests, named — and the new commit SHA) and reply with the short status contract.

Findings (verbatim from the reviewer):
<FINDINGS>

Controller notes: <rulings, scope limits>. Keep public interfaces unchanged unless a finding requires otherwise. No compiler is available; statically re-check every edited line. Commit on the same branch with the same footer convention; do not push; `git add` with explicit paths only.
```

### C.3 Scoped Re-Review (nach jeder Fix-Runde)

```
You are re-reviewing one task's fix round. A previous review produced findings; an implementer has attempted to fix them. Your job is to verdict each finding and inspect the fix diff — nothing else.

## The Task
Read the task brief: <WORKSPACE>/task-<N>-brief.md

## The Findings Under Verification
<FINDINGS, one per bullet, verbatim>

## The Fix
Read the implementer's report (fix reports are appended at the end): <WORKSPACE>/task-<N>-report.md
**Fix base:** <FIX_BASE_SHA> (the head the previous review saw)   **Head:** <HEAD_SHA>
**Diff file:** <DIFF_FILE>
Read the diff file once; do not re-run git commands. Read-only on this checkout.

## You Do Not Dispatch Subagents

## Scope
Verdict every finding ADDRESSED or NOT ADDRESSED with file:line evidence ("attempted" is not addressed). Inspect the fix diff for new Critical/Important breakage. Do NOT re-review code the fix did not touch; out-of-scope observations go in their own section. No compiler exists; static evidence only.

## Output Format
### Finding Verdicts
### New Breakage in the Fix Diff
### Out-of-Scope Observations
### Verdict
**Fix round:** [All findings addressed, no new Critical/Important breakage | Findings remain open] — list the open ones.
```

---

*Platzhalter:* `<WORKSPACE>` ist das SDD-Arbeitsverzeichnis (in der ursprünglichen Session
`.superpowers/sdd/plan`, gitignored; in einer neuen Session neu anlegen und `constraints.md` aus Teil 0.1
dort ablegen, Briefs aus `docs/plan.md` extrahieren). `<BASE_SHA>`/`<HEAD_SHA>`/`<DIFF_FILE>` pro Task einsetzen.
