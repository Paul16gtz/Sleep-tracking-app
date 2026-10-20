# Spezifikation: Schlafprotokoll (Sleep Tracking App, iOS)

Diese Datei ist die verbindliche Spezifikation. Teil A ist die Vorgabe von Paul,
Teil B dokumentiert die Entscheidungen zu Punkten, die die Vorgabe offen lässt.
Code, Bezeichner und Kommentare sind Englisch; UI-Texte sind Deutsch.

---

## Teil A: Vorgabe

### Kontext
Persönliche iPhone-App, die nachts aufzeichnet, ob der Nutzer schnarcht, im Schlaf
spricht und wie unruhig er schläft. Nur für ein eigenes iPhone, nicht für den App
Store. Alles läuft lokal: keine Server, keine Cloud, keine Analytics, keine
Netzwerkzugriffe.

Die Entwicklung findet in einer Linux-Umgebung ohne Swift-Compiler statt. Der Build
passiert später auf dem Mac mit Xcode. Daraus folgt:
- Konservativer Swift-Code, nur gut dokumentierte, stabile Apple-APIs.
- Nie behaupten, dass etwas "funktioniert" oder "kompiliert".
- README führt einen Abschnitt "Ungeprüfte Stellen" mit allen API-Unsicherheiten.

### Technische Vorgaben
- Swift, SwiftUI, SwiftData, Swift Charts. iOS 17.0, nur iPhone, nur Hochformat.
- Keine Third-Party-Dependencies. Nur AVFoundation, SoundAnalysis, CoreMotion,
  SwiftData, Charts, UIKit (nur wo nötig).
- Xcode-Projekt per XcodeGen (`project.yml`). Keine `.xcodeproj` im Repo
  (`.gitignore`).
- Swift 5 Language Mode, minimale Concurrency-Strictness. Audio-Callbacks laufen auf
  Hintergrund-Threads. UI-Updates mit `@MainActor`. Dedizierte Serial Queues für
  die Audio-Analyse.
- Bundle Identifier `com.paul.sleeptracker`, Development Team leer.
- App-Name "Schlafprotokoll".

### Info.plist / Capabilities
- `NSMicrophoneUsageDescription` (deutsch).
- `NSMotionUsageDescription` (deutsch).
- `UIBackgroundModes`: `audio`.
- Dateischutz `FileProtectionType.completeUntilFirstUserAuthentication` für alle
  geschriebenen Dateien (SwiftData-Store und Clip-Ordner), weil bei gesperrtem
  Gerät geschrieben wird.

### Funktionen

#### 1. Nachtaufnahme starten/stoppen
- Großer Button "Schlaf starten". Danach dunkler Bildschirm mit laufender Dauer,
  Live-Pegel, Zählern für Schnarchen und Sprechen, Button "Aufwachen / Beenden".
- Einstellbare Einschlafverzögerung (Standard 15 min). Während dieser Zeit wird
  aufgenommen, aber kein Ereignis gezählt. Bewegung und Pegel werden protokolliert.
- Hinweis beim Start, wenn das iPhone nicht lädt (`UIDevice.current.batteryState`,
  `isBatteryMonitoringEnabled`). Start bleibt möglich.
- Hinweis beim Start: iPhone mit Display nach unten auf die Matratze in Kopfnähe.

#### 2. Audio-Pipeline
- `AVAudioSession` Kategorie `.record` (oder `.playAndRecord` mit Begründung),
  Mode `.measurement`.
- `AVAudioEngine` mit Tap auf dem Input-Node. Puffer gehen parallel an:
  a) Sound-Klassifikator, b) Pegelmessung, c) Ringpuffer (letzte 10 s PCM),
  d) Clip-Writer, falls ein Ereignis aufgezeichnet wird.
- Robustheit: Unterbrechungen (`AVAudioSession.interruptionNotification`),
  Route-Changes, Media-Services-Reset behandeln; Engine automatisch neu starten.
  Jede Unterbrechung als Lücke in der Session protokollieren.
- Niemals die ganze Nacht im RAM halten.

#### 3. Geräuscherkennung (SoundAnalysis)
- `SNAudioStreamAnalyzer` mit `SNClassifySoundRequest(classifierIdentifier: .version1)`
  auf eigener Serial Queue.
- Fensterdauer ca. 1,5 s, Überlappung 0,5. Falls nicht konfigurierbar, Standard
  nehmen und dokumentieren.
- Relevante Klassen: snoring, speech; zusätzlich cough und whispering, falls
  vorhanden. Label-Namen nicht aus dem Gedächtnis: zur Laufzeit über
  `knownClassifications` lesen, im Debug-Bildschirm zeigen, nur existierende Labels
  mappen. Mapping Label → Ereignistyp zentral an einer Stelle.
- Konfidenz-Schwellenwert pro Kategorie, einstellbar (Standard 0,6).

#### 4. Ereigniserkennung (reine Logik, TDD)
`EventDetector` macht aus Klassifikationsergebnissen (Zeit, Label, Konfidenz)
Ereignisse mit Start und Ende:
- Ereignis beginnt nach mindestens N aufeinanderfolgenden Fenstern über Schwelle
  (Standard 2).
- Ereignis endet, wenn X Sekunden kein Treffer kommt (Standard 4 s).
- Ereignisse desselben Typs mit weniger als Y Sekunden Abstand (Standard 10 s)
  werden zusammengeführt.
- Maximale Ereignisdauer konfigurierbar; längere Phasen werden geteilt.
- Pro Ereignis: Typ, Start, Ende, maximale und durchschnittliche Konfidenz.
- Unit-Tests für alle Randfälle: Ausreißer, Lücken, Zusammenführung, Ereignis bei
  Session-Ende, Einschlafverzögerung.

#### 5. Audio-Clips
- Clip = 5 s Pre-Roll aus Ringpuffer + Ereignis + 5 s Post-Roll, max. 60 s.
- AAC in `.m4a`, Mono, moderate Bitrate. Ablage
  `Application Support/Clips/<session-id>/`, Dateiname mit Zeitstempel und Typ.
- Sprechen: jedes Ereignis bekommt einen Clip (Limit pro Nacht, Standard 50).
- Schnarchen: alle Ereignisse zählen, Clips höchstens 1 pro 10 min, max. 20 pro
  Nacht, beides einstellbar.
- Ringpuffer und Clip-Auswahllogik als reine, getestete Logik.

#### 6. Lautstärke
- RMS in dBFS pro Puffer, aggregiert in 30-s-Epochen: Durchschnitt und Spitze.
- Live-Pegel für den Nachtbildschirm, gedrosselt auf max. ~5 Updates/s.

#### 7. Bewegung / Unruhe (CoreMotion)
- `CMMotionManager`, Beschleunigung ca. 20 Hz während der Session. Prüfen und
  dokumentieren, ob Accelerometer-Updates im Hintergrund zuverlässig laufen;
  andernfalls Alternative vorschlagen.
- Pro Sample: Abweichung des Beschleunigungsbetrags von gleitender Basislinie
  (Hochpass), aufsummiert pro 30-s-Epoche → Bewegungsintensität.
- Kalibrierung: erste 5 Minuten Ruhebasislinie. Epoche "unruhig", wenn über
  Basislinie × Faktor (einstellbar).
- Unruhe-Index: Anteil unruhiger Epochen und Anzahl zusammenhängender Unruhephasen.
- Aggregation und Kalibrierung als reine, getestete Logik.

#### 8. Datenmodell (SwiftData)
- `SleepSession`: id, Start, Ende, Status (läuft / beendet / unerwartet beendet),
  Snapshot der Einstellungen, Unterbrechungs-Lücken.
- `SoundEvent`: id, Session, Typ, Start, Ende, max./avg. Konfidenz, optionaler
  relativer Clip-Pfad.
- `EpochSample`: Session, Zeitstempel, Bewegungsintensität, unruhig ja/nein,
  dB avg, dB peak.
- Inkrementelles Speichern (spätestens alle 2 Minuten).
- Beim App-Start: Sessions mit Status "läuft" ohne aktiven Recorder → "unerwartet
  beendet". Daten bleiben erhalten.

#### 9. Auswertung und UI
Tab-Leiste mit drei Tabs:
1. Heute Nacht: Start/Stopp und Live-Bildschirm.
2. Nächte: Liste aller Sessions (Datum, Dauer, Schnarch-Minuten, Anzahl
   Sprech-Ereignisse, Unruhe-Index). Wischen zum Löschen inkl. Clips.
   Detailansicht: Zusammenfassung (Gesamtdauer, Schnarchzeit in Minuten und %,
   Sprech-Ereignisse, Husten falls vorhanden, Unruhe-Index, Unterbrechungen);
   Zeitachse mit Swift Charts (Lautstärke Linie, Bewegung Balken, Ereignisse als
   farbige Markierungen); Ereignisliste chronologisch mit Play/Pause
   (`AVAudioPlayer`) und Einzel-Löschen; Export per `ShareLink` als CSV.
3. Einstellungen: Einschlafverzögerung, Schwellenwerte, Mindestfenster, Lücke,
   Merge-Abstand, Clip-Limits, Unruhe-Faktor, Speicherverbrauch der Clips, "Alle
   Daten löschen" mit Bestätigung, Zugang zum Debug-Bereich:
   Klassifikator-Top-5 live, Liste aller Labels, Live-Bewegungswerte, Testmodus
   (Audiodatei aus "Dateien" importieren und durch dieselbe Pipeline schicken,
   Ergebnis als Test-Session speichern).

Design: dunkel, ruhig, Dark Mode Standard, Nachtbildschirm gedimmt, SF Symbols,
keine aufwendigen Animationen.

### Architektur
```
SleepTracker/
  App/          App-Einstieg, Dependency-Setup
  Audio/        AudioSessionManager, AudioCaptureService, RingBuffer, ClipWriter, LevelMeter
  Analysis/     SoundClassifierService, LabelMapping, EventDetector, ClipPolicy
  Motion/       MotionService, MotionEpochAggregator, Calibration
  Session/      SleepSessionController (orchestriert eine Nacht)
  Persistence/  SwiftData-Modelle, Repository, FileStore mit Dateischutz
  Features/     Tonight, Nights, NightDetail, Settings, Debug (Views + ViewModels)
  Shared/       Formatter, Settings-Modell, Utilities
SleepTrackerTests/
docs/plan.md
project.yml
README.md
```
- Hardware-Zugriffe hinter Protokollen, damit die Logik mit Fakes testbar ist.
- XCTest für: EventDetector, RingBuffer, ClipPolicy, Epochen-Aggregation,
  Kalibrierung, Nacht-Statistiken, CSV-Export.

### CI
`.github/workflows/build.yml`: macOS-Runner, XcodeGen installieren, Projekt
generieren, mit `xcodebuild` für den Simulator bauen und testen, ohne Signing.

### README (deutsch)
Kurzbeschreibung; Schritt-für-Schritt für den Mac mit englischen Menünamen
(Xcode, `brew install xcodegen`, `xcodegen generate`, Apple-ID unter
Xcode > Settings > Accounts, Team unter Signing & Capabilities, Developer Mode
unter Settings > Privacy & Security > Developer Mode, Vertrauen unter
Settings > General > VPN & Device Management, 7-Tage-Hinweis); empfohlene Nutzung;
"Ungeprüfte Stellen"; bekannte Grenzen.

### Lieferumfang
- Phase 1 (MVP): Projekt-Setup, Audio-Pipeline, Klassifikation, EventDetector,
  Clips, SwiftData, Tab "Heute Nacht", einfache Nächte-Liste mit Clip-Wiedergabe,
  Unit-Tests der Logik, README.
- Phase 2: Bewegung/Unruhe, Diagramme, Einstellungen, CSV-Export, Debug-Bereich mit
  Testmodus, CI-Workflow.
Phase 1 wird vollständig abgeschlossen und committet, bevor Phase 2 beginnt.

---

## Teil B: Entscheidungen zu offenen Punkten

Diese Punkte lässt die Vorgabe offen oder stellt sie zur Begründung. Die
Entscheidungen gelten für die Umsetzung.

### B1. Audio-Session-Kategorie
Während der Nacht: `.record` mit Mode `.measurement`. Begründung: `.record` hat
keinen Ausgabepfad, ist die einfachste Kategorie für Hintergrundaufnahme und
vermeidet Routing-Fragen (Receiver vs. Speaker), die `.playAndRecord` mit sich
bringt. Clip-Wiedergabe findet nur außerhalb einer laufenden Session statt; dafür
wird die Session kurz auf `.playback` umgestellt. Während eine Nacht läuft, sind
die Play-Buttons deaktiviert.

### B2. Zeitmodell
Alle Analyse-Zeiten sind "Sekunden seit Session-Start" (`TimeInterval`). Die
Audio-Pipeline leitet sie aus Frame-Zählern ab: `segmentBase + frames/sampleRate`.
Nach jeder Unterbrechung beginnt ein neues Segment, dessen `segmentBase` die
Wanduhr-Zeit seit Session-Start beim Neustart ist; der `SNAudioStreamAnalyzer` wird
dabei neu erzeugt. Absolute Zeitpunkte für die Persistenz ergeben sich aus
`session.startDate + offset`. Vorteil: Der Testmodus mit Datei läuft schneller als
Echtzeit durch dieselbe Pipeline, weil keine Wanduhr nötig ist.

### B3. Mono-Konvertierung
Der Input-Node liefert sein natives Format (Float32, native Sample-Rate, 1 oder
mehr Kanäle). Direkt nach dem Tap wird auf Mono Float32 reduziert (Kanäle
mitteln). Alle Konsumenten (Klassifikator, Pegel, Ringpuffer, Clip-Writer)
arbeiten auf Mono Float32 in der nativen Sample-Rate.

### B4. Threading und Persistenz
Audio-Tap-Callbacks laufen auf einem AVAudioEngine-Thread. Die Analyse läuft auf
einer eigenen Serial Queue (`analysisQueue`). Ergebnisse (Ereignisse, Pegel,
Epochen) werden an den `SleepSessionController` auf dem Main Actor übergeben.
Sämtliche SwiftData-Zugriffe laufen auf dem Main Actor über den Haupt-Context.
Die Schreibrate ist niedrig (Epoche alle 30 s, wenige Ereignisse pro Minute), so
dass das unkritisch ist und Data Races beim ModelContext ausgeschlossen sind.

### B5. Speicherung zusammengesetzter Werte in SwiftData
Einstellungs-Snapshot und Unterbrechungs-Lücken werden als JSON-`Data` gespeichert
(Codable-Structs), mit typisierten Zugriffs-Properties. Status wird als `String`
(Raw Value eines Enums) gespeichert. Das vermeidet Unsicherheiten über die
SwiftData-Unterstützung für verschachtelte Codable-Arrays.

### B6. Zusammenführen von Ereignissen und Clips
Der `EventDetector` hält ein beendetes Ereignis als "pending" zurück, bis die
Merge-Lücke (Y s) ohne neuen Treffer desselben Typs verstrichen ist. Beginnt
innerhalb der Lücke ein neues Ereignis desselben Typs, wird das pending Ereignis
fortgesetzt statt ein neues erzeugt. Nach außen gibt der Detektor drei Signale:
`eventStarted` (für den Clip-Start), `eventEnded` (tentativ, für den Post-Roll)
und `eventFinalized` (für die Persistenz). Ein Clip gehört zum finalisierten
(ggf. zusammengeführten) Ereignis. Wird ein Ereignis fortgesetzt, während der
Clip noch im Post-Roll ist, läuft der Clip weiter (bis max. 60 s).

### B7. Erkennungslatenz und Pre-Roll
Ein Ereignis wird erst nach N Fenstern erkannt, also typischerweise 1,5 bis 2,5 s
nach dem akustischen Beginn. Der Clip-Start zieht aus dem Ringpuffer
`preRoll + (detectionTime - eventStart)` Sekunden, gedeckelt auf die
Ringpuffer-Länge (10 s). So enthält der Clip trotz Latenz den Anfang des
Ereignisses.

### B8. Testmodus
`AudioSource` ist ein Protokoll mit `start/stop` und einem Buffer-Callback.
`MicrophoneAudioSource` (AVAudioEngine) und `FileAudioSource` (liest eine
`AVAudioFile` in Blöcken) implementieren es. Der Testmodus baut die identische
Pipeline mit `FileAudioSource` auf, ohne Bewegungserfassung, und speichert eine
Session mit Kennzeichen `isTest = true`.

### B9. Bewegung im Hintergrund
`CMMotionManager`-Accelerometer-Updates laufen weiter, solange die App dank
Hintergrund-Audio nicht suspendiert wird. Das ist die gängige Erfahrung, aber
nicht von Apple garantiert. Wird im README als ungeprüft markiert. Fallback,
falls es nicht zuverlässig läuft: `CMSensorRecorder` (liefert Daten verzögert,
batch-weise) oder Verzicht auf Bewegung im Hintergrund.

### B10. Dateischutz
Standard-Schutzklasse für App-Dateien auf iOS ist bereits
`completeUntilFirstUserAuthentication`. Trotzdem setzt `FileStore` das Attribut
explizit auf dem Clip-Verzeichnis, jedem Clip und auf dem Store-Verzeichnis und
der Store-Datei nach dem Anlegen. Der SwiftData-Store liegt per
`ModelConfiguration(url:)` in `Application Support/SleepTracker/Store/SleepTracker.store`.
Die Clips liegen entsprechend unter `Application Support/SleepTracker/Clips/<session-id>/`
(alle App-Dateien unter dem gemeinsamen Ordner `Application Support/SleepTracker/`).

### B11. Einstellungen
`AppSettings` ist ein Codable-Struct mit allen einstellbaren Werten und
Standardwerten. `SettingsStore` (ObservableObject, MainActor) lädt und speichert
es als JSON in `UserDefaults`. Phase 1 nutzt die Standardwerte; die Einstellungs-UI
kommt in Phase 2.

### B12. Session-Status "läuft" ohne Recorder
Beim App-Start, bevor irgendeine Session gestartet werden kann, markiert das
Repository alle Sessions mit Status `running` als `endedUnexpectedly` und setzt
`endDate` auf den Zeitstempel der letzten gespeicherten Epoche bzw. des letzten
Ereignisses, sonst auf `startDate`.
