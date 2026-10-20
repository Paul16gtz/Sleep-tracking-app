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
