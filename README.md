# Schlafprotokoll

Persönliche iPhone-App, die nachts aufzeichnet, ob du schnarchst und ob du im Schlaf sprichst. Sie ist nur für das eigene iPhone gedacht, nicht für den App Store. Alles läuft lokal auf dem Gerät: keine Server, keine Cloud, keine Analytics, keine Netzwerkzugriffe.

> **Wichtig zum Stand:** Der gesamte Code wurde in einer Linux-Umgebung **ohne Swift-Compiler, ohne Xcode und ohne XcodeGen** geschrieben. Bisher wurde nichts gebaut, nichts ausgeführt und kein Test gestartet. Dieses README behauptet deshalb an keiner Stelle, dass die App baut oder funktioniert. Der erste Schritt auf dem Mac ist, das Projekt zu bauen. Wo es dabei am ehesten hakt, steht im Abschnitt [Ungeprüfte Stellen](#4-ungeprüfte-stellen).

## Inhalt

1. [Kurzbeschreibung und Funktionsumfang](#1-kurzbeschreibung-und-funktionsumfang)
2. [Einrichtung auf dem Mac, Schritt für Schritt](#2-einrichtung-auf-dem-mac-schritt-für-schritt)
3. [Empfohlene Nutzung](#3-empfohlene-nutzung)
4. [Ungeprüfte Stellen](#4-ungeprüfte-stellen)
5. [Bekannte Grenzen](#5-bekannte-grenzen)
6. [Projektstruktur](#6-projektstruktur)
7. [Tests](#7-tests)

Weitere Dokumente: `docs/spec.md` (verbindliche Spezifikation und Entscheidungen), `docs/plan.md` (Umsetzungsplan), `docs/unverified.md` (vollständige englische Liste der Unsicherheiten, aus der Abschnitt 4 entstanden ist).

---

## 1. Kurzbeschreibung und Funktionsumfang

Die App nimmt über Nacht das Mikrofon auf, lässt jeden Audio-Schnipsel vom System-Klassifikator von Apple (SoundAnalysis, `SNClassifySoundRequest` mit `.version1`) auf Schnarchen, Sprechen, Husten und Flüstern prüfen und macht daraus Ereignisse mit Start, Ende und Konfidenz. Zu Ereignissen speichert sie kurze Audio-Clips, damit du dir morgens anhören kannst, was erkannt wurde. Die Nacht liegt nicht im Arbeitsspeicher: Ein Ringpuffer hält nur die letzten 10 Sekunden, Clips werden direkt in Dateien geschrieben.

Technik: Swift 5, SwiftUI, SwiftData, AVFoundation, SoundAnalysis. iOS 17.0, nur iPhone, nur Hochformat. Keine Drittanbieter-Abhängigkeiten. Das Xcode-Projekt wird mit XcodeGen aus `project.yml` erzeugt und ist nicht eingecheckt.

### Phase 1: Quellcode vollständig, noch nie gebaut

- **Tab „Heute Nacht“:** Großer Button „Schlaf starten“, dann ein Hinweisblatt (Ladekabel nur, wenn das iPhone nicht lädt; iPhone mit dem Display nach unten in Kopfnähe auf die Matratze; Einschlafverzögerung). Danach der gedimmte Nachtbildschirm mit laufender Dauer, Live-Pegel in dBFS, Zählern für Schnarchen und Sprechen und dem Button „Aufwachen / Beenden“.
- **Audio-Pipeline:** Mikrofon über `AVAudioEngine` (Audio-Session `.record` mit Mode `.measurement`, Hintergrund-Audio), Reduktion auf Mono Float32, Pegel als RMS in dBFS, 30-Sekunden-Epochen mit Durchschnitt und Spitze, Live-Pegel auf höchstens 5 Updates pro Sekunde gedrosselt. Unterbrechungen (Anruf, Wecker, Siri), Route-Wechsel und Media-Services-Reset führen zu einem automatischen Neustart und werden als Lücke protokolliert.
- **Erkennung:** Klassifikator mit 1,5-Sekunden-Fenstern und Überlappung 0,5. Die Label-Namen werden zur Laufzeit aus `knownClassifications` gelesen; nur Labels, die es wirklich gibt, werden einer Ereignisart zugeordnet. Der `EventDetector` macht daraus Ereignisse (mindestens N Fenster über der Schwelle, Ende nach einer Lücke, Zusammenführen naher Ereignisse, Teilen sehr langer Ereignisse).
- **Clips:** AAC in `.m4a`, Mono. Ein Clip enthält 5 s Pre-Roll aus dem Ringpuffer (die Erkennungslatenz wird ausgeglichen), das Ereignis und 5 s Post-Roll, höchstens 60 s. Sprech-Ereignisse bekommen je einen Clip (höchstens 50 pro Nacht), Schnarch-Ereignisse zählen alle, aber Clips gibt es höchstens einen je 10 Minuten und 20 pro Nacht. Husten und Flüstern werden wie Sprechen behandelt (je Ereignis ein Clip, eigener Zähler).
- **Speicherung:** SwiftData auf dem Main Actor, inkrementell (spätestens alle 120 s). Beim App-Start werden Nächte, die noch als „läuft“ markiert sind, als „Unerwartet beendet“ gekennzeichnet; ihre Daten bleiben erhalten.
- **Tab „Nächte“:** Liste aller Nächte (Datum, Dauer, Schnarchminuten, Anzahl Sprech-Ereignisse, Unruhe-Index). Wischen löscht eine Nacht samt Clips (die laufende Nacht lässt sich nicht löschen). Die Detailansicht zeigt die Zusammenfassung (Gesamtdauer, Schnarchzeit in Minuten und Prozent, Sprech-Ereignisse, Husten falls vorhanden, Unruhe-Index, Unterbrechungen) und die chronologische Ereignisliste mit Play/Pause für Clips und Einzel-Löschen per Wischen. Während eine Nacht läuft, sind die Play-Buttons deaktiviert.
- **Tests:** Unit-Tests für die gesamte reine Logik, siehe [Tests](#7-tests).

### Phase 2: folgt nach der Prüfung von Phase 1

- Tab „Einstellungen“ (Einschlafverzögerung, Schwellenwerte, Mindestfenster, Lücke, Merge-Abstand, Clip-Limits, Speicherverbrauch der Clips, „Alle Daten löschen“).
- Zeitachse in der Nachtansicht mit Swift Charts (Lautstärke als Linie, Ereignisse als farbige Markierungen).
- CSV-Export per `ShareLink`.
- Debug-Bereich (Klassifikator-Top-5 live, Liste aller Labels) und Testmodus (Audiodatei aus „Dateien“ importieren und durch dieselbe Pipeline schicken, Ergebnis als Test-Session speichern).
- CI-Workflow (GitHub Actions, macOS-Runner, Build und Tests im Simulator ohne Signing).

### Zurückgestellt: Bewegung und Unruhe (CoreMotion)

Die Bewegungserfassung über CoreMotion (Beschleunigungssensor, Kalibrierung, „unruhige“ Epochen, Unruhe-Index) ist auf deine Entscheidung hin **zurückgestellt und nicht Teil dieser Lieferung**. Folgen:

- Die App greift derzeit nicht auf CoreMotion zu.
- Der **Unruhe-Index wird überall als „–“ angezeigt**, weil keine Bewegungsdaten aufgezeichnet werden. Bewusst nicht „0 %“: Das würde eine gemessene ruhige Nacht vortäuschen.
- Das Datenmodell behält die Felder für eine spätere Erweiterung (`EpochSample.motionIntensity`, `EpochSample.isRestless`, in Einstellungen `restlessFactor` und `motionCalibrationDuration`). Aktuell werden dort feste Werte gespeichert (Intensität 0, nicht unruhig).
- `NSMotionUsageDescription` steht schon in der `Info.plist`, damit eine spätere Erweiterung keine Plist-Änderung braucht.

### Standardwerte

In Phase 1 gibt es noch keine Einstellungs-Oberfläche; es gelten diese Standardwerte (`SleepTracker/Shared/AppSettings.swift`).

| Wert | Standard |
|---|---|
| Einschlafverzögerung | 900 s (15 min) |
| Konfidenz-Schwelle je Kategorie | 0,6 |
| Mindestanzahl aufeinanderfolgender Fenster | 2 |
| Ende eines Ereignisses nach Lücke von | 4 s |
| Zusammenführen gleicher Ereignisse bei Abstand unter | 10 s |
| Längste Ereignisdauer (längere werden geteilt) | 600 s |
| Clip: Pre-Roll / Post-Roll / Maximum | 5 s / 5 s / 60 s |
| Sprech-Clips pro Nacht (höchstens) | 50 |
| Schnarch-Clips: Mindestabstand / höchstens pro Nacht | 600 s / 20 |
| Ringpuffer | 10 s (fest) |
| Epochenlänge | 30 s (fest) |
| Live-Pegel | höchstens 5 Updates pro Sekunde (fest) |

---

## 2. Einrichtung auf dem Mac, Schritt für Schritt

Die Menünamen stehen auf Englisch, weil Xcode und macOS bei dir auf Englisch laufen.

**Voraussetzungen:** ein Mac mit Xcode (nötig ist ein Xcode mit iOS-17-SDK, also Xcode 15 oder neuer), [Homebrew](https://brew.sh), ein iPhone mit iOS 17 oder neuer, ein Kabel zum Anschließen, eine Apple-ID (die kostenlose reicht).

1. **Xcode installieren.** Xcode aus dem Mac App Store laden, einmal starten, Lizenz akzeptieren und die angebotenen Zusatzkomponenten installieren lassen.
2. **XcodeGen installieren.**
   ```bash
   brew install xcodegen
   ```
3. **Repository holen und Projekt erzeugen.** Im Repository-Ordner:
   ```bash
   git clone https://github.com/Paul16gtz/Sleep-tracking-app
   cd Sleep-tracking-app
   xcodegen generate
   ```
   Danach prüfen (siehe [Ungeprüfte Stellen](#4-ungeprüfte-stellen), U1 und U2): `SleepTracker/Info.plist` darf im Target `SleepTracker` nicht unter **Build Phases > Copy Bundle Resources** stehen, und das Test-Target muss `TEST_HOST` und `BUNDLE_LOADER` gesetzt haben.
4. **Projekt öffnen.**
   ```bash
   open SleepTracker.xcodeproj
   ```
5. **Apple-ID in Xcode anmelden:** **Xcode > Settings > Accounts**, unten links `+`, **Apple ID** wählen und anmelden.
6. **Team setzen:** Links im Project Navigator das Projekt `SleepTracker` wählen, dann das Target `SleepTracker`, Reiter **Signing & Capabilities**: bei **Team** deine Apple-ID („Personal Team“) wählen. „Automatically manage signing“ ist durch das Projekt schon an.
   - Die Bundle-ID ist `com.paul.sleeptracker`. Lehnt Apple sie ab (Meldung wie „Failed to register bundle identifier“, weil sie schon vergeben ist), ändere `PRODUCT_BUNDLE_IDENTIFIER` im Target `SleepTracker` in `project.yml` auf etwas Eigenes (z. B. `com.deinname.sleeptracker`) und führe `xcodegen generate` erneut aus.
   - Weil das Projekt aus `project.yml` erzeugt wird und `DEVELOPMENT_TEAM` dort leer ist, geht ein in Xcode gesetztes Team bei jedem erneuten `xcodegen generate` verloren. Entweder das Team danach wieder wählen oder lokal die Team-ID in `project.yml` eintragen (nicht committen).
7. **iPhone anschließen.** Per Kabel verbinden, das iPhone entsperren und auf dem iPhone „Trust This Computer“ bestätigen. In der Xcode-Symbolleiste oben das iPhone als **Run Destination** wählen.
8. **Developer Mode aktivieren (einmalig, auf dem iPhone):** **Settings > Privacy & Security > Developer Mode** einschalten und das iPhone neu starten lassen; nach dem Neustart die Rückfrage bestätigen. Der Eintrag erscheint auf dem iPhone in der Regel erst, nachdem es einmal mit Xcode verbunden war.
9. **Bauen und starten:** **Run** (⌘R). Beim ersten Mal baut Xcode alles neu. Schlägt der Build fehl, ist das nach dem Stand des Projekts ausdrücklich möglich: Es wurde noch nie kompiliert. Die Fehlermeldungen lassen sich meist einer Stelle in [Ungeprüfte Stellen](#4-ungeprüfte-stellen) zuordnen; dort steht auch jeweils ein Fallback.
10. **Entwicklerzertifikat vertrauen (beim ersten Start auf dem iPhone):** Meldet das iPhone „Untrusted Developer“, unter **Settings > General > VPN & Device Management** bei „Developer App“ deine Apple-ID antippen und **Trust** wählen. Danach die App erneut starten.
11. **Mikrofon erlauben.** Beim ersten Start einer Nacht fragt iOS nach dem Mikrofonzugriff. Ohne Zustimmung startet keine Nacht.
12. **Tests ausführen:** Als Run Destination einen iPhone-Simulator wählen und **Product > Test** (⌘U). Die Tests brauchen weder Mikrofon noch Gerät. Details im Abschnitt [Tests](#7-tests).

> **Kostenlose Apple-ID: 7 Tage.** Mit einer kostenlosen Apple-ID läuft das Provisioning-Profil nach 7 Tagen ab, danach startet die App nicht mehr. Dann das iPhone anschließen und mit ⌘R neu installieren. Die App vorher **nicht** löschen: Mit ihr verschwinden alle gespeicherten Nächte und Clips. Installiere am besten kurz vor einer Nacht neu und starte die App einmal, statt am Abend vor einer ungültigen App zu stehen.

---

## 3. Empfohlene Nutzung

- **Ladekabel anschließen.** Eine Nacht mit Mikrofon, Klassifikator und Dateischreiben ist für den Akku nicht trivial. Die App warnt beim Start, wenn das iPhone nicht lädt; der Start bleibt trotzdem möglich.
- **iPhone mit dem Display nach unten in Kopfnähe auf die Matratze legen.** Nicht unter Kissen oder Decke, sonst dämpft der Stoff die Geräusche.
- **Nicht aus dem App-Umschalter wegwischen.** Die App nimmt im Hintergrund weiter auf, solange sie läuft (`UIBackgroundModes = audio`). Sie hält den Bildschirm nicht wach; die automatische Sperre darf greifen. Dass die Aufnahme bei gesperrtem Bildschirm die ganze Nacht durchläuft, ist ungeprüft (siehe U20, U21, U45).
- **Störungen vermeiden.** Anrufe, Wecker und Siri unterbrechen die Aufnahme kurz (die App startet danach selbst neu und vermerkt eine Lücke). Ein aktiver Fokus wie „Do Not Disturb“ sollte viele solcher Unterbrechungen verhindern; das ist nicht geprüft.
- **Einschlafverzögerung beachten.** Standard sind 15 Minuten: Währenddessen wird aufgenommen, aber kein Ereignis gezählt und kein Clip erzeugt. Die Dauer ist in Phase 1 noch nicht einstellbar.
- **Erster Test tagsüber.** Sobald der Testmodus aus Phase 2 da ist: **Einstellungen > Debug > Testmodus**, dort eine Audiodatei mit Schnarchen oder Sprechen aus „Dateien“ importieren und durch dieselbe Pipeline schicken. Bis dahin geht ein Test nur mit einer echten Aufnahme: Start, dann mindestens 15 Minuten warten (Einschlafverzögerung), dann etwas vorspielen oder selbst Geräusche machen und beenden. Zeigen sich dabei gar keine Ereignisse, ist der erste Verdacht die Zuordnung der Label-Namen (U32).
- **Wie Ereignisse und Clips entstehen.** Der Klassifikator soll alle 0,75 s ein Ergebnis für ein 1,5-s-Fenster liefern (U34, U35). Ein Ereignis wird erst erkannt, wenn mindestens 2 Fenster hintereinander die Schwelle (0,6) überschreiten, also etwa 1,5 bis 2,5 s nach dem Beginn des Geräuschs. Weil die App die letzten 10 s im Ringpuffer hält, enthält der Clip trotzdem den Anfang (5 s Pre-Roll plus ausgeglichene Latenz). Sprech-Ereignisse bekommen jeweils einen Clip (bis 50 pro Nacht), Schnarch-Ereignisse zählen alle, Clips dafür höchstens einen je 10 Minuten (bis 20 pro Nacht). Nach 4 s ohne Treffer endet ein Ereignis; Ereignisse derselben Art mit weniger als 10 s Abstand werden zu einem zusammengeführt.
- **Clips anhören.** Tab „Nächte“, Nacht antippen, bei einem Ereignis den Play-Button. Das geht nur, wenn gerade keine Nacht läuft (die App wechselt dafür kurz auf die Audio-Session-Kategorie `.playback`).
- **Löschen.** In der Nächte-Liste löscht Wischen eine Nacht samt Clips, in der Detailansicht löscht Wischen ein einzelnes Ereignis samt Clip. Eine automatische Bereinigung alter Clips gibt es nicht; „Alle Daten löschen“ kommt mit Phase 2.

### Wo liegen die Daten?

Alles liegt im App-Container unter `Application Support/SleepTracker/`:

- SwiftData-Store: `Application Support/SleepTracker/Store/SleepTracker.store`
- Clips: `Application Support/SleepTracker/Clips/<session-id>/<yyyyMMdd-HHmmss>-<art>.m4a` (Zeit im Dateinamen in **UTC**, siehe Bekannte Grenzen)
- Einstellungen: als JSON in `UserDefaults`

Clips enthalten echtes Audio aus deinem Schlafzimmer. Die App setzt auf Ordner, Clips, Store-Ordner und Store-Datei den Dateischutz `completeUntilFirstUserAuthentication` (die Dateien sind nach dem ersten Entsperren seit dem Start lesbar, weil nachts bei gesperrtem Gerät geschrieben wird). Ob der Schutz auf dem Gerät tatsächlich gesetzt ist, ist ungeprüft (U13, U15, U16). Übertragen wird nichts.

---

## 4. Ungeprüfte Stellen

Es gab beim Schreiben weder Compiler noch Xcode noch XcodeGen noch ein Gerät. Jede Stelle unten ist eine API-Signatur, ein Verhalten oder eine Werkzeug-Annahme, die nur statisch geprüft werden konnte. Dieser Abschnitt enthält **alle** 66 Einträge aus `docs/unverified.md` (dort steht der vollständige englische Wortlaut), gruppiert nach Bereich. Die Nummern U1 bis U66 sind nur Verweise in diesem README. „Prüfen“ sagt, woran du erkennst, ob die Annahme stimmt; „Fallback“ nennt die geplante Ausweichlösung, falls nicht.

Hinweis: Prüfschritte, die den **Debug-Bildschirm** oder den **Testmodus** nennen, sind erst mit Phase 2 möglich. In Phase 1 lässt sich stattdessen die Konsole von Xcode und das Verhalten einer echten Nacht verwenden.

### Was du zuerst prüfen solltest

Reihenfolge: Projekt erzeugen, bauen, Tests laufen lassen, dann auf das Gerät.

1. **Direkt nach `xcodegen generate`:**
   - **U1** `Info.plist` taucht nicht unter „Copy Bundle Resources“ auf.
   - **U2** `TEST_HOST` und `BUNDLE_LOADER` des Test-Targets sind gesetzt (sonst „No such module 'SleepTracker'“ beim Testen).
2. **Compile-kritische Stellen**, bei denen die API-Form nicht sicher ist. Wenn der Build hier fehlschlägt, steht der Fallback im jeweiligen Eintrag:
   - **U34** SoundAnalysis: Muster `guard case .enumeratedDurations(let durations)` auf `SNTimeDurationConstraint` (`SoundClassifierService.swift:43-51,74-84`).
   - **U31** `AVAudioApplication.requestRecordPermission()` als `async` (`SleepSessionController.swift:132-134`).
   - **U12** `ModelConfiguration(_:schema:url:allowsSave:cloudKitDatabase:)` mit `.none` (`AppDependencies.swift:23-30`).
   - **U44** `nonisolated`-Witnesses von `AudioPipelineDelegate` auf der `@MainActor`-Klasse (`SleepSessionController.swift:425-473,244-246,262-269`), dazu die Isolationsfragen U47 bis U50, U52 und U53.
   - SwiftData-Makros und -Abfragen: U6, U7, U8, U10, U58.
3. **⌘U im Simulator:** Welche Tests zu welchen Annahmen gehören, steht in den Einträgen (z. B. `testSettingsStorePersists` bei U3, `testMarkStaleRunningSessions` bei U9 und U10, die `AudioPipelineTests` bei U40 und U42).
4. **Auf dem Gerät, in dieser Reihenfolge:**
   - Startet das Mikrofon überhaupt (U17, U18: sonst Meldung „Kein Mikrofon-Eingang verfügbar.“)? Fragt iOS nach der Berechtigung (U31)?
   - Werden Ereignisse erkannt? Wenn bei hörbarem Schnarchen oder Sprechen nichts erscheint, sind die Label-Namen der erste Verdacht (U32); dazu U34 bis U39.
   - Wird ein Clip geschrieben und lässt er sich abspielen (U27 bis U29, U64)?
   - Verhalten über Nacht: Unterbrechungen und Neustart bei gesperrtem Bildschirm (U20, U21, U45), Dateischutz (U13, U15, U16).

### 4.1 Projekt, XcodeGen, Info.plist

- **U1 · `project.yml`:** XcodeGen soll die in `INFOPLIST_FILE` genannte `Info.plist` automatisch aus den Ressourcen des Targets ausschließen. *Prüfen:* Nach `xcodegen generate` darf `SleepTracker/Info.plist` nicht unter „Copy Bundle Resources“ stehen. *Fallback:* im Source-Eintrag des Targets `SleepTracker` `excludes: ["Info.plist"]` ergänzen.
- **U2 · `project.yml` (Target `SleepTrackerTests`, `dependencies: - target: SleepTracker`):** XcodeGen soll `TEST_HOST` und `BUNDLE_LOADER` des Unit-Test-Bundles automatisch aus der Abhängigkeit auf das App-Target setzen; das braucht `@testable import SleepTracker`. (Aus Task 1 zurückgestellt.) *Prüfen:* In den Build Settings von `SleepTrackerTests` zeigt `TEST_HOST` auf die ausführbare Datei in der gebauten App (erwartet `$(BUILT_PRODUCTS_DIR)/SleepTracker.app/SleepTracker`), `BUNDLE_LOADER` ist `$(TEST_HOST)`; ⌘U meldet kein „No such module 'SleepTracker'“. *Fallback:* beide Werte in `project.yml` bei den Settings des Test-Targets eintragen.

### 4.2 Shared: Einstellungen, Symbole, Formatierung

- **U3 · `SleepTracker/Shared/SettingsStore.swift:17`:** `_settings = Published(initialValue: SettingsStore.load(from: userDefaults))` setzt den `@Published`-Speicher direkt im `init`, sodass der `didSet { save() }`-Observer beim Laden nicht feuert. *Prüfen:* Es kompiliert ohne „self used before all stored properties are initialized“ oder eine Observer-auf-Property-Wrapper-Diagnose, und `testSettingsStorePersists` läuft durch.
- **U4 · `SleepTracker/Shared/SoundEventType.swift:25-28`:** Die SF-Symbols-Namen `zzz`, `bubble.left.fill`, `wind`, `ear.fill` müssen in iOS 17 existieren. *Prüfen:* `Image(systemName:)` für jeden Fall in einer Preview rendern; kein Bild darf leer sein.
- **U5 · `SleepTracker/Shared/Formatters.swift:42,52,60-78`:** Die genaue Ausgabe von `DateFormatter` mit `de_DE` und `EE, d. MMM yyyy` (Abkürzung mit oder ohne Punkt, z. B. „Mo., 3. Feb. 2025“, „Juni“ gegen „Jun.“) hängt von der CLDR-Version der iOS-Laufzeit ab. *Prüfen:* `Formatters.nightDate(Date())` für mehrere Monate in Simulator und Gerät ausgeben; außerdem muss `Formatters.csvTimestamp(Date(timeIntervalSince1970: 0))` den Wert `1970-01-01T00:00:00Z` liefern.

### 4.3 SwiftData und Repository

- **U6 · `SleepTracker/Persistence/Models.swift:32-33`:** `@Relationship(deleteRule: .cascade, inverse: \SoundEvent.session)` und `\EpochSample.session` stehen nur auf der Session-Seite; auf der Kind-Seite steht ein einfaches `var session: SleepSession?` (Standard-Löschregel `.nullify`). *Prüfen:* Das Schema baut ohne „inverse“-Diagnosen; `testDeleteSessionRemovesEventsAndClipFolder` findet nach dem Löschen der Session weder `SoundEvent` noch `EpochSample` (Kaskade); `testDeleteEventRemovesClipFile` lässt die Session bestehen.
- **U7 · `SleepTracker/Persistence/Models.swift:35-46,97-104,127-134`:** Die `@Model`-Initializer weisen jede gespeicherte Property zu, auch `events = []`, `epochs = []` und `session = nil`, obwohl diese Standardwerte haben oder optional sind. *Prüfen:* keine Makro-Diagnose („return from initializer without initializing all stored properties“, Relationship-im-init-Warnung) und kein Laufzeit-Trap beim Anlegen einer Instanz vor dem Einfügen.
- **U8 · `SleepTracker/Persistence/Models.swift:25,78`:** `@Attribute(.unique) var id: UUID` muss die `Identifiable`-Anforderung von `PersistentModel` mit `ID == UUID` erfüllen (Views nutzen `session.id`); `EpochSample` hat keine `id` und verlässt sich auf die Standard-`persistentModelID`. *Prüfen:* Es kompiliert, und `NavigationLink(value: session.id)` bekommt eine `UUID`.
- **U9 · `SleepTracker/Persistence/SessionRepository.swift:44-45,65-66`:** Ein neues Ereignis oder eine neue Epoche wird erst eingefügt und dann an `session.events` bzw. `session.epochs` (To-many-Seite) angehängt; SwiftData soll dabei die Gegenrichtung `session` setzen. *Prüfen:* `testMarkStaleRunningSessions` (liest `session.epochs`/`session.events` nach `addEpoch`/`addEvent`) läuft durch, und nach dem Speichern gilt `event.session === session`. *Fallback:* Wird das Anhängen an ein To-many-Array mit etwa 1000 Epochen pro Nacht auf dem Gerät langsam, stattdessen `epoch.session = session` (To-one-Seite) setzen und die Tests wiederholen.
- **U10 · `SleepTracker/Persistence/SessionRepository.swift:88-90`:** `#Predicate<SleepSession> { session in session.statusRaw == runningRaw }` vergleicht einen gespeicherten `String` mit einem erfassten lokalen `String`. *Prüfen:* Es kompiliert, und `testMarkStaleRunningSessions` markiert nur die laufende Session; der Test setzt außerdem voraus, dass Änderungen über die abgerufenen Instanzen in den von `createSession` gelieferten Instanzen sichtbar sind (gleicher Context). *Fallback:* alle Sessions laden und in Swift nach `statusRaw == "running"` filtern.
- **U11 · `SleepTracker/Persistence/SessionRepository.swift:8`:** `static let schema` steht in einer `@MainActor`-Klasse und ist damit Main-Actor-isoliert (`Schema` gilt nicht als `Sendable`). *Prüfen:* `AppDependencies` referenziert es nur aus einem Main-Actor-Kontext; sonst meldet der Compiler einen Isolationsfehler.
- **U12 · `SleepTracker/App/AppDependencies.swift:23-30`:** `ModelConfiguration("SleepTracker", schema:, url:, allowsSave: true, cloudKitDatabase: .none)` nimmt den iOS-17-Initializer `init(_ name: String?, schema: Schema?, url: URL, allowsSave: Bool, cloudKitDatabase: ModelConfiguration.CloudKitDatabase)` und das statische Mitglied `ModelConfiguration.CloudKitDatabase.none` an (der Parameter ist nicht optional, also ist `.none` nicht `Optional.none`); `ModelContainer(for: Schema, configurations: [ModelConfiguration]) throws` ist die Array-Variante. *Prüfen:* Es kompiliert, und die Store-Datei erscheint unter `Application Support/SleepTracker/Store/SleepTracker.store`. *Fallback:* Wird `.none` abgelehnt, das Argument `cloudKitDatabase:` weglassen (die App hat keine iCloud-Berechtigung, `.automatic` synchronisiert also nichts).

### 4.4 Dateisystem und Dateischutz

- **U13 · `SleepTracker/Persistence/FileStore.swift:60,66-69,77,106`:** `setAttributes([.protectionKey: .completeUntilFirstUserAuthentication], ofItemAtPath:)` kann im Simulator werfen oder ignoriert werden; `prepareDirectories`, `clipDirectory(for:)` und `deleteAllClips` rufen `applyProtection` deshalb mit `try?` auf, nur `applyProtection` selbst wirft. *Prüfen (auf dem Gerät):* `FileManager.default.attributesOfItem(atPath:)[.protectionKey]` ist `completeUntilFirstUserAuthentication` für `Clips`, einen Session-Clip-Ordner, `Store` und die Store-Datei.
- **U14 · `SleepTracker/Persistence/FileStore.swift:112-129`:** `clipsTotalSize()` nutzt `FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)` mit `for case let url as URL` und `resourceValues(forKeys:)` (`isRegularFile`, `fileSize`); `fileSize` ist die logische Größe, nicht der belegte Platz auf dem Datenträger. *Prüfen:* `testClipsTotalSizeSumsFiles` liefert 30, und Verzeichnisse tragen nichts bei.
- **U15 · `SleepTracker/Audio/ClipWriter.swift:67-69`:** `applyProtection(to:)` wird direkt nach dem `AVAudioFile`-Init mit `try?` aufgerufen; angenommen wird, dass die Datei dann schon existiert und sonst die Schutzklasse des Clip-Ordners erbt. *Prüfen (auf dem Gerät):* `attributesOfItem(atPath:)[.protectionKey]` eines Clips ist `completeUntilFirstUserAuthentication`.
- **U16 · `SleepTracker/App/AppDependencies.swift:31,56-67`:** Die Store-Datei soll direkt nach dem `ModelContainer`-Init existieren (Store wird sofort geladen), damit `applyProtection` darauf gelingt; `-wal`/`-shm` werden nur geschützt, wenn sie dann existieren. Später angelegte Nebendateien sollen die Schutzklasse des `Store`-Ordners erben (gesetzt in `prepareDirectories`). *Prüfen (auf dem Gerät, nach einer Nacht):* `attributesOfItem(atPath:)[.protectionKey]` ist `completeUntilFirstUserAuthentication` für `SleepTracker.store`, `SleepTracker.store-wal` und `SleepTracker.store-shm`.

### 4.5 AVFoundation: Mikrofon, Audio-Session, Clip-Datei

- **U17 · `SleepTracker/Audio/MicrophoneAudioSource.swift:168-177`:** `inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat, block:)` mit dem eigenen `outputFormat(forBus: 0)` des Knotens; der Trailing-Closure-Typ ist `AVAudioNodeTapBlock` = `(AVAudioPCMBuffer, AVAudioTime) -> Void`, angenommen auf einem Nicht-Echtzeit-Thread der Engine (dort ist das Anlegen der Mono-Kopie in Ordnung). `bufferSize` ist nur eine Anfrage; iOS liefert oft etwa 100 ms (z. B. 4800 Frames bei 48 kHz). *Prüfen (auf dem Gerät):* keine Exception beim Installieren, Puffer kommen etwa alle 0,1 s, `frameLength > 0`, Format entspricht `inputFormat`. *Fallback:* Zeigt die Allokation im Tap Aussetzer, einen kleinen Pool vorab angelegter Mono-Puffer verwenden.
- **U18 · `SleepTracker/Audio/MicrophoneAudioSource.swift:149-159`:** `outputFormat(forBus: 0)` meldet `sampleRate == 0` / `channelCount == 0`, wenn die Session inaktiv ist oder die Berechtigung fehlt (dann `noInputFormat`). Die Zeilen 156-159 vergleichen es zusätzlich mit `inputNode.inputFormat(forBus: 0).sampleRate` (angenommen die Hardware-Rate), um die Exception „format.sampleRate == hwFormat.sampleRate“ direkt nach einem Route-Wechsel zu vermeiden. *Prüfen:* Im Normalbetrieb sind beide Raten auf Gerät und Simulator gleich, sodass `start()` gelingt. *Fallback:* Schlägt `start()` immer mit „Kein Mikrofon-Eingang verfügbar.“ fehl, die Zeilen 153-159 löschen.
- **U19 · `SleepTracker/Audio/MicrophoneAudioSource.swift:180-186,403-412`:** `NotificationCenter.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main)`; angenommen wird, dass sich die Engine bei einer Änderung der Eingabehardware selbst stoppt und diese Notification (auf beliebigem Thread) sendet. *Prüfen:* Ein- und Ausstecken eines Kabel-Headsets während einer Nacht ergibt ein oder zwei Neustarts (je eine Lücke) und keine Neustart-Schleife; eine frisch gestartete Engine sendet die Notification nicht von selbst. *Fallback:* Tritt eine Schleife auf, Konfigurationsänderungen etwa 1 s nach Beginn eines Segments ignorieren.
- **U20 · `SleepTracker/Audio/MicrophoneAudioSource.swift:351-376`:** Interruption: `userInfo[AVAudioSessionInterruptionTypeKey] as? UInt` ergibt `AVAudioSession.InterruptionType(rawValue:)`. Jedes `.ended` startet die Aufnahme neu, mit oder ohne `.shouldResume`; hält eine andere App die Session noch, scheitert die Aktivierung und die Wiederholungskette übernimmt. Ein `.ended` ohne vorheriges `.began` verursacht einen unnötigen Neustart (kurze Lücke). *Prüfen (bei gesperrtem Bildschirm):* Nach Telefonanruf, Wecker der Uhr-App und Siri läuft die Aufnahme weiter und genau eine Lücke wird gespeichert. Außerdem prüfen, ob iOS nach einer Unterbrechung von mehr als 30 s überhaupt noch `.ended` an die App zustellt (z. B. 2 Minuten Anruf bei gesperrtem Bildschirm), weil die App währenddessen eventuell suspendiert wird, solange sie weder aufnimmt noch einen Background-Task hält. *Fallback:* Wird `.ended` nicht zugestellt, gibt es in dieser Schicht keinen; die Lücke bleibt dann bis `stop()` offen.
- **U21 · `SleepTracker/Audio/MicrophoneAudioSource.swift:241-262`:** Der Neustart im Hintergrund bei gesperrtem Bildschirm (`setActive(true)` plus `AVAudioEngine.start()` nach einer beendeten Unterbrechung) soll wegen `UIBackgroundModes = [audio]` erlaubt sein. iOS kann ihn verweigern (z. B. `AVAudioSession.ErrorCode.cannotStartRecording` oder `.insufficientPriority`). Solange Wiederholungen ausstehen, nimmt die App weder auf noch spielt sie, daher hält eine Background-Task-Assertion (Zeilen 298-323) sie vom ersten fehlgeschlagenen Versuch bis zu Erfolg, endgültigem Fehlschlag, `.began` oder `stop()` am Laufen. Rund 30 s Hintergrundzeit decken die Wiederholungen nach 1, 2, 5 und 10 s ab (zusammen 18 s), nicht die nach 30 s. Läuft die Assertion ab, wird `didFailWith(MicrophoneError.restartFailed)` sofort gemeldet, und die 30-s-Wiederholung läuft nur, wenn die App wieder Rechenzeit bekommt. Dass `didFailWith` den Delegate vor der Suspendierung erreicht, ist deshalb nicht sicher; es kann erst ankommen, wenn die App wieder läuft. *Prüfen:* Anruf bei gesperrtem Bildschirm, danach fließen wieder Puffer (Live-Pegel nach dem Entsperren, Lücke geschlossen). Außerdem einen fehlschlagenden Neustart im Hintergrund erzwingen (z. B. in `beginSegment` vorübergehend werfen) und in der Konsole prüfen, dass die Wiederholungen laufen und `didFailWith` ankommt.
- **U22 · `SleepTracker/Audio/MicrophoneAudioSource.swift:378-391`:** `notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt` ergibt `AVAudioSession.RouteChangeReason(rawValue:)`; nur `.oldDeviceUnavailable` und `.newDeviceAvailable` starten neu, damit die durch unser eigenes `setCategory` ausgelöste `.categoryChange` keine Schleife erzeugt. *Prüfen:* Headset ein- und ausstecken erzeugt einen Neustart mit Grund `routeChange`.
- **U23 · `SleepTracker/Audio/MicrophoneAudioSource.swift:327-342`:** Die drei Session-Observer sind mit `object: AVAudioSession.sharedInstance()` registriert; angenommen wird, dass `mediaServicesWereResetNotification` ebenfalls mit diesem Objekt gesendet wird. *Prüfen:* **Settings > Developer > Reset Media Services** während einer Nacht erzeugt eine Lücke mit Grund `mediaServicesReset`, und die Aufnahme läuft weiter. *Fallback:* diesen Observer mit `object: nil` registrieren.
- **U24 · `SleepTracker/Audio/MicrophoneAudioSource.swift:207-224,393-401`:** Nach einem Media-Services-Reset ruft `tearDownEngine()` weiterhin `removeTap(onBus: 0)` und `stop()` auf der alten, ungültigen Engine auf; angenommen wird, dass das harmlos ist. *Prüfen:* mit Reset Media Services kein Absturz. *Fallback:* Für `.mediaServicesReset` die Engine-Referenz verwerfen, ohne sie aufzurufen.
- **U25 · `SleepTracker/Audio/MicrophoneAudioSource.swift:207-224,55-59`:** Eine durch den Abbau entfernte Engine wird in `retiredEngine` gehalten und erst beim nächsten Abbau oder in `deinit` freigegeben, nie innerhalb ihres eigenen `AVAudioEngineConfigurationChange`-Handlers (laut Hinweis in `AVAudioEngine.h` kann das Freigeben der Engine dort einen Deadlock auslösen). Das setzt voraus, dass die auslösende Notification beim nächsten Abbau vom Absender freigegeben wurde. Eine Engine, deren `start()` in `beginSegment` fehlschlägt, wird beim Verlassen der Funktion freigegeben, womöglich im Handler der vorherigen Engine; das gilt als sicher, weil es eine andere Engine ist. *Prüfen:* Etwa zehnmal ein Kabel-Headset während einer Nacht ein- und ausstecken; es gibt keinen Hänger auf dem Main Thread, und jede Änderung erzeugt genau eine Lücke.
- **U26 · `SleepTracker/Audio/AudioSessionManager.swift:14-15,19-20,26`:** `setCategory(_:mode:options:)` (wirft), `setActive(_:)` und `setActive(_:options:)` mit `.notifyOthersOnDeactivation`; `try session.setActive(true)` soll nicht mehrdeutig zur `options:`-Variante sein. *Fallback:* `setActive(true, options: [])`.
- **U27 · `SleepTracker/Audio/ClipWriter.swift:58-64`:** `AVAudioFile(forWriting:settings:commonFormat: .pcmFormatFloat32, interleaved: false)` mit `AVFormatIDKey: kAudioFormatMPEG4AAC` (eine `AudioFormatID`/`UInt32` in `[String: Any]`), `AVSampleRateKey` = native Rate, 1 Kanal, `AVEncoderBitRateKey: 48_000`. *Prüfen (Gerät und Simulator):* `open` gelingt, und ein Clip spielt ab. *Fallback:* `Int(kAudioFormatMPEG4AAC)`; lehnt der Encoder 48 kbit/s bei der nativen Rate ab, `AVEncoderBitRateKey` weglassen oder `AVEncoderAudioQualityKey` nehmen.
- **U28 · `SleepTracker/Audio/ClipWriter.swift:85-87`:** `close()` gibt nur die `AVAudioFile` frei; die AAC-Datei soll in `deinit` abgeschlossen werden (vor iOS 18 gibt es kein `close()`). *Prüfen:* Nach `close()` spielt der Clip vollständig mit `AVAudioPlayer`, und seine Dauer entspricht der geschriebenen Sample-Zahl. *Fallback:* unter iOS 17 keiner nötig, solange nichts anderes die Datei festhält.
- **U29 · `SleepTracker/Audio/ClipWriter.swift:74-83`:** `write(from:)` bekommt einen Puffer im `file.processingFormat` (angenommen Mono Float32 nicht interleaved mit der Clip-Rate), nicht im separat gebauten Mono-Format, weil das Puffer-Format genau zum Processing-Format passen muss. Ein Pre-Roll von bis zu 10 s (480 000 Frames) wird in einem Aufruf geschrieben. *Prüfen:* kein Format-Mismatch-Fehler und keine Kürzung des Pre-Rolls.
- **U30 · `SleepTracker/Audio/MonoDownmix.swift:29,61,83`:** `AVAudioPCMBuffer.stride` soll 1 für nicht interleaved und `channelCount` für interleaved Puffer sein, und bei interleaved Daten ist nur `floatChannelData[0]` gültig. *Prüfen:* Der Testmodus (Phase 2) mit einer Stereo-Datei liefert dieselben Pegel wie die Mono-Version derselben Datei.
- **U31 · `SleepTracker/Session/SleepSessionController.swift:132-134`:** `AVAudioApplication.requestRecordPermission()` soll die iOS-17-Async-Klassenmethode sein (`class func requestRecordPermission() async -> Bool`, importiert aus `requestRecordPermissionWithCompletionHandler:`), die sofort und ohne Abfrage zurückkehrt, wenn der Zugriff schon erlaubt oder verweigert ist. *Prüfen:* Der erste Start zeigt die Systemabfrage mit dem Text aus `NSMicrophoneUsageDescription`; nach dem Verweigern in den Einstellungen wirft `start` `microphoneDenied`. *Fallback:* `await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { granted in continuation.resume(returning: granted) } }` (in iOS 17 veraltet, aber noch vorhanden).

### 4.6 SoundAnalysis

- **U32 · `SleepTracker/Analysis/LabelMapping.swift:9-14`:** Die Kandidaten `snoring`, `speech`, `cough`, `whispering` sind ungeprüfte Vermutungen für die Namen im Label-Satz von `SNClassifySoundRequest(classifierIdentifier: .version1)` (`knownClassifications`); für einen fehlenden Namen wird nichts zugeordnet. **Folge bei falschem Namen: Diese Ereignisart wird nie erkannt, ohne Fehlermeldung.** *Prüfen:* Im Debug-Bildschirm (Phase 2) die ganze Label-Liste lesen und prüfen, dass `availableTypes` alle vier Arten enthält. Fehlt eine, den echten Label-Namen in `LabelMapping.candidates` ergänzen (und ggf. das Fixture in `testMapsOnlyKnownLabels` erweitern).
- **U33 · `SleepTracker/Analysis/SoundClassifierService.swift:42,63`:** `SNClassifySoundRequest(classifierIdentifier: .version1)` ist ein werfender Init (iOS 15+) mit `SNClassifierIdentifier.version1`; `knownClassifications` soll ein `[String]` mit genau diesem Property-Namen sein. *Prüfen:* Es kompiliert, und der Debug-Bildschirm zeigt die vollständige Label-Liste (einige hundert Einträge) aus `SoundClassifierService.knownLabels()`.
- **U34 · `SleepTracker/Analysis/SoundClassifierService.swift:43-51,74-84`:** `windowDuration` soll ein setzbarer `CMTime` sein, und `windowDurationConstraint` soll das Swift-Overlay-Enum `enum SNTimeDurationConstraint { case enumeratedDurations([CMTime]); case durationRange(CMTimeRange) }` sein. Nur `.enumeratedDurations` wird per `guard case` geprüft (die Dauer, die 1,5 s am nächsten liegt, wird genommen); in jedem anderen Fall werden direkt 1,5 s gesetzt. `.version1` soll einen Bereich von etwa 0,5 bis 15 s erlauben, 1,5 s wäre also gültig. Ein Wert außerhalb der Einschränkung soll nicht als Swift-Fehler gemeldet werden (möglicherweise als Objective-C-Exception). *Prüfen (Gerät):* `request.windowDurationConstraint` und `effectiveWindowDuration` (Zeilen 34-36) nach dem Init ausgeben; die Ergebnisse haben dann `timeRange.duration.seconds` von etwa 1,5. *Fallback:* Kompiliert das Muster `guard case .enumeratedDurations(let durations)` nicht (andere Enum-Form oder die Einschränkung wird als Objective-C-Klasse mit `type`/`enumeratedDurations: [NSValue]`/`durationRange: CMTimeRange` importiert), `allowedWindowDuration` samt Aufruf löschen und direkt `request.windowDuration = CMTime(seconds: SoundClassifierService.windowDuration, preferredTimescale: 48_000)` setzen. Ist 1,5 s nicht erlaubt, die tatsächliche Dauer hier im README festhalten (die Erkennungslatenz bei N = 2 Fenstern ändert sich, Spec B7).
- **U35 · `SleepTracker/Analysis/SoundClassifierService.swift:52`:** `overlapFactor` soll ein setzbarer `Double` sein und 0,5 akzeptieren, was ein Ergebnis alle 0,75 s ergibt. *Prüfen:* Die `timeRange.start.seconds` aufeinanderfolgender Ergebnisse unterscheiden sich um etwa 0,75.
- **U36 · `SleepTracker/Analysis/SoundClassifierService.swift:10-15,98-112` (Thread der Ergebnislieferung):** `SNAudioStreamAnalyzer` soll `request(_:didProduce:)`, `request(_:didFailWithError:)` und `requestDidComplete(_:)` synchron auf dem Thread aufrufen, der `analyze(_:atAudioFramePosition:)` / `completeAnalysis()` aufruft, also auf der seriellen Analyse-Queue der Pipeline; `completeAnalysis()` soll die letzten Ergebnisse liefern, bevor es zurückkehrt (die Pipeline gibt den Klassifikator direkt danach frei). *Prüfen:* Vorübergehend `dispatchPrecondition(condition: .onQueue(pipeline.queue))` in `classifier(_:didProduce:topLabels:)` der Pipeline einbauen und eine Nacht auf dem Gerät (später auch den Testmodus) laufen lassen. *Fallback:* Kommen Ergebnisse auf einer internen SoundAnalysis-Queue an, die Analyse-Queue in die Factory geben und in `request(_:didProduce:)` vor dem Delegate-Aufruf mit `queue.async` wechseln (sonst Races im Pipeline-Zustand).
- **U37 · `SleepTracker/Analysis/SoundClassifierService.swift:54,58`:** `SNAudioStreamAnalyzer(format:)` ist nicht failable und akzeptiert das Mono-Float32-nicht-interleaved-Processing-Format mit nativer Rate (48 kHz oder 44,1 kHz; intern umgerechnet); `add(_:withObserver:)` wirft und soll den Observer schwach halten, sodass Service, Analyzer und Service keinen Retain-Zyklus bilden. *Prüfen:* kein `didFailWithError` beim Start auf dem Gerät und mit einer 44,1-kHz-Testdatei; der Memory Graph zeigt nach mehreren Neustarts (Unterbrechungen) keinen verwaisten `SoundClassifierService`. *Fallback:* Hält der Analyzer den Observer stark, in `completeAnalysis()` nach `analyzer.completeAnalysis()` noch `analyzer.removeAllRequests()` aufrufen.
- **U38 · `SleepTracker/Analysis/SoundClassifierService.swift:89,102-103`:** `analyze(_:atAudioFramePosition:)` (`AVAudioBuffer`, `AVAudioFramePosition`) soll `SNClassificationResult.timeRange` aus den übergebenen Frame-Positionen in der Zeitbasis des Analyzer-Formats ableiten, mit Frame 0 bei `CMTime` null, sodass `timeOffset + timeRange.start.seconds` Sekunden seit Session-Start ergibt. *Prüfen (Testmodus, Phase 2):* Eine Datei mit einem bekannten Geräusch bei Sekunde t liefert ein Fenster mit Start nahe t; nach einer Unterbrechung beginnt das erste Fenster des neuen Segments nahe der neuen Segment-Basis.
- **U39 · `SleepTracker/Analysis/SoundClassifierService.swift:100-108`:** `SNRequest`/`SNResult` werden als einfache Protokolltypen verwendet (Swift 5, kein `any`), `SNClassificationResult.classifications` soll `[SNClassification]` mit `identifier: String` und `confidence: Double` sein. *Prüfen:* Es kompiliert; der Debug-Bildschirm zeigt die Top-5-Labels mit Konfidenzen zwischen 0 und 1.

### 4.7 Audio-Pipeline und Session-Controller (Verhalten)

- **U40 · `SleepTracker/Session/AudioPipeline.swift:126,130,407-419`:** Die Pipeline markiert ihre `queue` mit `queue.setSpecific(key:value: ())` (ein frischer `DispatchSpecificKey<Void>` pro Pipeline) und prüft `DispatchQueue.getSpecific(key:) != nil` in den Klassifikator-Callbacks (Zeilen 258-270) und in `stop()` (Zeile 146). Angenommen wird, dass `getSpecific` den Wert auch in einem `queue.sync { }`-Block liefert, der von einem anderen Thread betreten wird (libdispatch: der Block läuft mit `queue` als aktueller Queue). Die Tests verlassen sich darauf: `SleepTrackerTests/AudioPipelineTests.swift:402` löst Fenster innerhalb von `callbackQueue.sync` aus, und die Prüfungen direkt nach `emit` brauchen den synchronen Pfad. *Prüfen:* Die `AudioPipelineTests` laufen durch; scheitern sie nur direkt nach `emit`, nahmen die Fenster den `queue.async`-Pfad (Zeilen 413-419).
- **U41 · `SleepTracker/Session/AudioPipeline.swift:258-270,413-419`:** Ausweichlösung für die Annahme zum Thread der Ergebnislieferung von `SoundClassifierService` (siehe U36). Liefert SoundAnalysis Ergebnisse auf einer eigenen Queue, verschiebt die Pipeline sie mit `queue.async` auf `queue`; der Zustand bleibt race-frei, aber die Ergebnisse kommen dann nach dem Puffer, der sie erzeugt hat, und letzte Fenster aus `completeAnalysis()`, die nach `stop()` bzw. dem Dateiende ankommen, gehen verloren (der Detektor ist dann weg). *Prüfen (Gerät):* Vorübergehend `dispatchPrecondition(condition: .onQueue(queue))` am Anfang von `handleWindow` (Zeile 274) einbauen und eine Nacht sowie später den Testmodus laufen lassen.
- **U42 · `SleepTrackerTests/AudioPipelineTests.swift:243`:** `AVAudioFormat(standardFormatWithSampleRate: 100, channels: 1)` soll auch für die ungewöhnliche Rate 100 Hz ein Mono-Float32-nicht-interleaved-Format liefern (der Init ist failable; sonst scheitert der Test an `XCTUnwrap`), und `AVAudioPCMBuffer` / `MonoDownmix.makeBuffer` sollen es akzeptieren. *Prüfen:* Die `AudioPipelineTests` kommen über `makeHarness` hinaus.
- **U43 · `SleepTracker/Session/SleepSessionController.swift:82-85,128`:** `UIDevice.current.isBatteryMonitoringEnabled = true` einmal im `init`; `batteryState` `.charging` oder `.full` gilt als „lädt“. Im Simulator ist `batteryState` `.unknown`, deshalb erscheint dort der Start-Hinweis „Das iPhone lädt nicht“ immer. *Prüfen (Gerät):* Kabel vor dem Öffnen des Start-Blatts ein- oder ausstecken schaltet den Hinweis um.

### 4.8 Concurrency und Actor-Isolation

Diese Einträge betreffen vor allem, ob der Compiler (Swift 5, `SWIFT_STRICT_CONCURRENCY = minimal`) die Isolation so ableitet wie angenommen. Erwartet sind höchstens Warnungen, aber Fehler sind möglich.

- **U44 · `SleepTracker/Session/SleepSessionController.swift:425-473,244-246,262-269`:** Die `AudioPipelineDelegate`-Methoden sind `nonisolated`-Witnesses der `@MainActor`-Klasse und rufen Main-Actor-Methoden innerhalb von `DispatchQueue.main.async { [weak self] in ... }` auf. Das setzt voraus, dass der Compiler den an `DispatchQueue.main.async` übergebenen Closure als `@MainActor` behandelt; das Erfassen nicht-`Sendable`-Werte (`AudioPipeline`, `LevelEpoch`, `DetectedEvent`) in diesem `@Sendable`-Closure kann in Swift 5 Warnungen erzeugen, Fehler werden nicht erwartet. *Prüfen:* kein Fehler „call to main actor-isolated instance method in a synchronous nonisolated context“. *Fallback:* `DispatchQueue.main.async` behalten und den Rumpf in `MainActor.assumeIsolated { ... }` (iOS 17) packen. **Nicht** auf `Task { @MainActor in ... }` umstellen: `stop()` verlässt sich auf die FIFO-Reihenfolge der Main Queue (sein Freigabe-Block in Zeile 244 muss nach den Sprüngen laufen, die die Pipeline während `pipeline.stop()` eingereiht hat, damit die letzten Ereignisse und die Teil-Epoche noch für die gestoppte Session gespeichert werden), und einzeln erzeugte Tasks haben keine garantierte Reihenfolge.
- **U45 · `SleepTracker/Session/SleepSessionController.swift:259-271`:** `Timer.scheduledTimer(withTimeInterval:repeats:block:)` wird aus dem Main-Actor-`start` nach einem `await` aufgerufen; angenommen läuft das auf dem Main Thread und plant daher im Main-Run-Loop (Default-Modus). Der Block wird eventuell als `@Sendable` importiert, deshalb springt er nur mit `DispatchQueue.main.async` (siehe U44). Angenommen feuern beide Timer bei gesperrtem Bildschirm weiter, weil Hintergrund-Audio die App am Laufen hält. *Prüfen:* `elapsed` stimmt nach dem Entsperren nachts; ein Breakpoint in `saveNow()` wird bei gesperrtem Bildschirm alle 120 s erreicht.
- **U46 · `SleepTracker/Session/SleepSessionController.swift:253-255`:** Die Pipeline-Uhr wird in einem `nonisolated static`-Helfer gebaut, damit der Closure, den die Pipeline auf ihrer Queue aufruft, nicht als Main-Actor-isoliert abgeleitet wird (der Inline-Closure `{ Date().timeIntervalSince(now) }` in der `@MainActor`-Methode würde es; in Swift 5 harmlos, aber er würde die dynamischen Isolationsprüfungen des Swift-6-Sprachmodus auslösen). *Prüfen:* Es kompiliert; Ereigniszeiten einer gespeicherten Nacht passen zur Wanduhr.
- **U47 · `SleepTracker/App/SleepTrackerApp.swift:9-19`:** `App.init()` soll Main-Actor-isoliert sein (das iOS-17-SDK deklariert die `App`-Anforderungen als `@MainActor(unsafe)`), sodass das Anlegen der `@MainActor`-Klasse `AppDependencies` dort erlaubt ist. Der `@State`-Speicher wird mit `_dependencies = State(initialValue:)` / `_startupError = State(initialValue:)` auf jedem Pfad initialisiert. *Prüfen:* keine Isolationsdiagnose; die App zeigt die Tabs, und mit kaputtem Store (z. B. ein Ordner namens `SleepTracker.store`) erscheint der deutsche Fehlertext. *Fallback:* den Initializer als `@MainActor init()` (oder die ganze Struktur als `@MainActor`) markieren.
- **U48 · `SleepTracker/Audio/MicrophoneAudioSource.swift:94-107,298-323`:** `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:) -> UIBackgroundTaskIdentifier`, `endBackgroundTask(_:)` und `UIBackgroundTaskIdentifier.invalid` werden aus dieser nicht-isolierten, nicht-`@MainActor`-Klasse aufgerufen (immer auf dem Main Thread, außer eventuell in `deinit`). Angenommen: Swift 5 mit `SWIFT_STRICT_CONCURRENCY = minimal` gibt für diese `@MainActor`-UIKit-APIs keinen Fehler, der Expiration-Handler läuft auf dem Main Thread, und `endBackgroundTask(_:)` darf aus `deinit` auf einem anderen Thread aufgerufen werden. *Fallback:* die Main-Thread-Aufrufe in `MainActor.assumeIsolated { ... }` (iOS 17) packen und in `deinit` die Kennung erfassen und per `DispatchQueue.main.async` beenden.
- **U49 · `SleepTrackerTests/SessionRepositoryTests.swift:5,14,29`:** Die ganze Testklasse ist `@MainActor` und überschreibt `setUp() async throws` / `tearDown() async throws` (aus Objective-C importiert, ohne Actor-Annotation). *Prüfen:* kein Fehler „different actor isolation from nonisolated overridden declaration“. *Fallback:* die Klassen-Annotation entfernen, jeden Test einzeln mit `@MainActor` markieren und den Container in einem `@MainActor`-Helfer bauen.
- **U50 · `SleepTracker/Features/Tonight/TonightView.swift:5-7,30-89`, `SleepTracker/Features/Tonight/NightScreenView.swift:5-6,30-82`, `SleepTracker/Features/Tonight/StartHintsSheet.swift:5-13,57-74`:** Die Hilfs-Properties und -Methoden außerhalb von `body` (`startView`, `errorBinding`, `startNight()`, `normalizedLevel`, `stopButton`, ...) lesen Mitglieder des `@MainActor`-`SleepSessionController`. Angenommen wird, dass jede View-Struktur durch ihren `@EnvironmentObject`-Wrapper (dessen `wrappedValue` `@MainActor` ist) als `@MainActor` abgeleitet wird (Swift-5-Sprachmodus, SE-0316-Inferenz; mit dem iOS-18-SDK ist `View` selbst `@MainActor`). `startNight()` nutzt zusätzlich `Task { @MainActor in ... }`, sodass der Start und die Zuweisung an `errorMessage` so oder so auf dem Main Actor laufen. *Prüfen:* kein Fehler „main actor-isolated property ... can not be referenced from a non-isolated context“. *Fallback:* die drei View-Strukturen als `@MainActor` markieren.
- **U51 · `SleepTracker/Features/Tonight/TonightView.swift:72-77`:** `Binding(get:set:)` mit Closures, die `controller.errorMessage` lesen und löschen; mit dem iOS-18-SDK können die Closure-Parameter `@Sendable` sein, was in Swift 5 mit minimaler Prüfung höchstens Warnungen ergeben soll. *Prüfen:* Es kompiliert; „OK“ im Alert setzt `errorMessage` auf nil, und der Alert erscheint nicht erneut.
- **U52 · `SleepTracker/Features/Nights/NightsListView.swift:7`, `SleepTracker/Features/NightDetail/NightDetailView.swift:10-11,73-106`, `SleepTracker/Features/NightDetail/EventRowView.swift:11-12,63-76`:** Wie bei den Tonight-Views nutzen die Helfer außerhalb von `body` (`delete(at:)`, `alertBinding`, `delete(_:)`, `playButton(path:)`) die `@MainActor`-Typen `AppDependencies`, `SessionRepository`, `ClipPlayer` und `SleepSessionController`; angenommen wird, dass jede View-Struktur über ihre `@EnvironmentObject`-Wrapper als `@MainActor` abgeleitet wird. `NightRowView` hat keinen solchen Wrapper und nutzt nur nicht-isolierte Mitglieder. *Prüfen:* kein Main-Actor-Isolationsfehler. *Fallback:* diese View-Strukturen als `@MainActor` markieren.
- **U53 · `SleepTracker/Features/NightDetail/ClipPlayer.swift:70-75,141,157-161`:** Der an `PlayerDelegateProxy(onEnd:)` übergebene Closure ist in der `@MainActor`-Klasse geschrieben und ruft `playbackEnded(failed:)` auf; angenommen wird, dass er als Main-Actor-isoliert abgeleitet wird (nicht-`@Sendable`-Closure in isoliertem Kontext) und sich ohne Diagnose in Swift 5 mit minimaler Prüfung als einfaches `(Bool) -> Void` im nicht-isolierten Proxy speichern lässt. Der Proxy ruft ihn nur innerhalb von `DispatchQueue.main.async` auf. *Prüfen:* Es kompiliert ohne „call to main actor-isolated instance method in a synchronous nonisolated context“; nach dem Ende eines Clips springt der Button zurück auf Play. *Fallback:* den Closure-Rumpf in `MainActor.assumeIsolated { ... }` (iOS 17) packen.

### 4.9 SwiftUI und Clip-Wiedergabe

- **U54 · `SleepTracker/Features/Tonight/TonightView.swift:19-27,80-89`, `SleepTracker/Features/Tonight/StartHintsSheet.swift:58-61`:** „Jetzt starten“ ruft `onStart()` (startet den `Task`) und `dismiss()` in derselben Aktion auf. Scheitert `start` sofort (Mikrofon schon verweigert, Klassifikator nicht verfügbar), wird `errorMessage` gesetzt, während das Blatt noch ausblendet, sodass der Alert der `TonightView` während des Schließens angefordert wird. Angenommen zeigt SwiftUI unter iOS 17 den Alert, sobald das Blatt weg ist. *Prüfen:* Mikrofonzugriff in den Einstellungen verweigern, „Schlaf starten“ und „Jetzt starten“ antippen; der Alert „Fehler“ mit „Kein Zugriff auf das Mikrofon. Bitte in den Einstellungen erlauben.“ erscheint. *Fallback:* in `onStart` ein Flag `startRequested` speichern und `startNight()` aus dem `onDismiss` von `.sheet(isPresented:onDismiss:content:)` aufrufen.
- **U55 · `SleepTracker/Features/Tonight/StartHintsSheet.swift:27`:** Das SF Symbol `iphone.gen3.radiowaves.left.and.right` (aus dem Briefing) soll ab SF Symbols 4 / iOS 16 existieren; ein fehlender Name zeigt ein leeres Bild, stürzt aber nicht ab. *Prüfen:* Der Platzierungs-Hinweis zeigt ein iPhone-Symbol. *Fallback:* `iphone.radiowaves.left.and.right` (SF Symbols 1).
- **U56 · `SleepTracker/Features/Tonight/StartHintsSheet.swift:63-70`:** `.foregroundStyle(Theme.background)` am Label-`Text` soll die weiße Label-Farbe von `.buttonStyle(.borderedProminent)` überschreiben und dunklen Text auf dem hellen Akzent ergeben (Weiß auf `Theme.accent` hat wenig Kontrast). *Prüfen:* „Jetzt starten“ zeigt dunklen Text auf dem hellblauen Button. *Fallback:* den Modifier entfernen (weißer Text) oder einen dunkleren Tint nehmen.
- **U57 · `SleepTracker/Features/Tonight/StartHintsSheet.swift:54,50-52`:** Beim `.medium`-Detent auf einem kleinen iPhone (SE, 667 pt) passen die drei Hinweise plus der untere Button eventuell nicht alle hinein; die Liste scrollt dann unter die Button-Leiste, und das Blatt lässt sich auf `.large` ziehen. *Prüfen:* im iPhone-SE-Simulator mit sichtbarem Akku-Hinweis. *Fallback:* `.presentationDetents([.large])` oder `.fraction(0.65)`.
- **U58 · `SleepTracker/Features/Nights/NightsListView.swift:8`:** `@Query(sort: \SleepSession.startDate, order: .reverse)` nimmt den iOS-17-Initializer `Query.init<Value: Comparable>(filter: Predicate<Element>? = nil, sort: KeyPath<Element, Value>, order: SortOrder = .forward, transaction: Transaction? = nil)` an. *Prüfen:* Es kompiliert, und die neueste Nacht steht oben. *Fallback:* `@Query(sort: [SortDescriptor(\SleepSession.startDate, order: .reverse)])`.
- **U59 · `SleepTracker/Features/Nights/NightsListView.swift:17-21`:** `ContentUnavailableView(_ title: LocalizedStringKey, systemImage: String, description: Text?)` (iOS 17) soll der für das String-Literal gewählte Initializer sein. *Prüfen:* Bei leerem Store zeigt der Tab das Mond-Symbol, „Noch keine Nächte“ und „Starte heute Nacht die erste Aufnahme.“. *Fallback:* `ContentUnavailableView { Label("Noch keine Nächte", systemImage: "moon.zzz") } description: { Text("Starte heute Nacht die erste Aufnahme.") }`.
- **U60 · `SleepTracker/Features/Nights/NightsListView.swift:47,49,64-74`:** `.onDelete(perform: delete)` übergibt die Main-Actor-Methode `delete(at:)` als `(IndexSet) -> Void` (Muster der Xcode-SwiftData-Vorlage). `delete(at:)` löst alle Sessions per Index auf, bevor die erste `deleteSession` läuft, und nimmt an, dass `@Query` die Liste nach dem Löschen und `save()` des Repositorys aktualisiert, ohne das gelöschte Objekt erneut anzufassen. `.deleteDisabled(session.status == .running)` soll nur die Wisch-Löschaktion der laufenden Nacht entfernen. *Prüfen:* Zwei Nächte nacheinander per Wischen löschen (die Zeilen verschwinden, ihre `Clips/<uuid>`-Ordner sind weg); während einer laufenden Nacht bietet deren Zeile keine Löschaktion.
- **U61 · `SleepTracker/Features/NightDetail/NightDetailView.swift:18,65-68,97-106`:** Nach `repository.deleteEvent(event)` (Löschen und Speichern) soll SwiftData das Ereignis aus `session.events` entfernen und den beobachtenden `body` benachrichtigen (die Gegenrichtung hat die Standardregel nullify), sodass die Zeile verschwindet und das gelöschte Modell nicht erneut gelesen wird. *Prüfen:* In der Detailansicht bei einem Ereignis „Löschen“ wischen; die Zeile verschwindet, die Zähler der Zusammenfassung sinken, kein Absturz; die Nacht erneut öffnen, das Ereignis bleibt weg. *Fallback:* der View ein `@Query private var events: [SoundEvent]` geben, in `init(session:)` mit `Query(filter: #Predicate<SoundEvent> { $0.session?.id == sessionID }, sort: \SoundEvent.startDate)` gesetzt.
- **U62 · `SleepTracker/Features/NightDetail/NightDetailView.swift:29-31`, `SleepTracker/Features/NightDetail/ClipPlayer.swift:25-28,54-60`:** `onDisappear` der Detailansicht soll sowohl beim Zurückgehen zur Liste als auch beim Tab-Wechsel feuern, sodass ein geladener Clip gestoppt (und die `.playback`-Session freigegeben) wird, bevor man in Tab 1 eine Nacht startet. `stop()` deaktiviert die Session nur, wenn der Player sie selbst aktiviert hat; ein Aufruf während einer laufenden Aufnahme (Detail während der Nacht geöffnet, dann verlassen) lässt die Aufnahme-Session in Ruhe. *Prüfen (Gerät):* Clip abspielen, zu „Heute Nacht“ wechseln (Wiedergabe stoppt), eine Nacht starten; während der Nacht die Details einer Nacht öffnen, zurückgehen und die Tabs wechseln: Der Nachtbildschirm aktualisiert weiter den Pegel, und die gespeicherte Nacht hat zu dieser Zeit keine Lücke.
- **U63 · `SleepTracker/Features/NightDetail/ClipPlayer.swift:139-163`:** Der nicht-isolierte `PlayerDelegateProxy: NSObject, AVAudioPlayerDelegate` nimmt an, dass die Witnesses `audioPlayerDidFinishPlaying(_:successfully:)` und `audioPlayerDecodeErrorDidOccur(_:error:)` (`Error?`) genau zu den optionalen Anforderungen passen (ein knapp verfehlter Treffer erzeugt nur eine Warnung, und die Methode würde nie aufgerufen), und dass AVFoundation sie auf jedem Thread aufrufen darf. *Prüfen:* Ein bis zum Ende gespielter Clip setzt den Button auf `play.circle.fill` zurück; keine Warnung „nearly matches optional requirement“.
- **U64 · `SleepTracker/Features/NightDetail/ClipPlayer.swift:68,76-81,127`:** `AVAudioPlayer(contentsOf:)` wirft bei fehlender oder unlesbarer Datei; `delegate` ist schwach (der Proxy wird in `delegateProxy` gehalten); die `Bool`-Ergebnisse von `prepareToPlay()` (verworfen, importierte Objective-C-Methode) und `play()` (geprüft); `stop()` soll `audioPlayerDidFinishPlaying` nicht aufrufen (ein später Callback eines ersetzten Players wird durch die Identitätsprüfung in Zeile 71 ohnehin ignoriert). *Prüfen:* Ein Tipp auf einen Clip, dessen Datei entfernt wurde, zeigt „Der Clip konnte nicht abgespielt werden.“; der Wechsel von einem laufenden Clip zu einem anderen spielt den zweiten bis zum Ende.
- **U65 · `SleepTracker/Features/NightDetail/EventRowView.swift:63-76`:** `.buttonStyle(.borderless)` soll in der `List`-Zeile nur den Play-Button antippbar machen (mit dem Standardstil würde die ganze Zeile ihn auslösen), und `.disabled(sessionController.isRunning)` mit `.tint(Theme.accent)` soll das Bild in der gedimmten Deaktiviert-Farbe zeigen. *Prüfen:* Ein Tipp auf den Text einer Zeile bewirkt nichts; während einer Nacht wirken die Play-Buttons deaktiviert und reagieren nicht.
- **U66 · `SleepTracker/Features/Nights/NightRowView.swift:12-21`:** Auf einem schmalen iPhone (SE, 320 pt Zeilenbreite) passen das Datum und beide Badges („Test“, „Unerwartet beendet“) eventuell nicht in eine Zeile; die Badges sind `fixedSize()`, also würde das Datum abgeschnitten. *Prüfen:* im iPhone-SE-Simulator mit einer unerwartet beendeten Test-Session. *Fallback:* die Badges in einen eigenen `HStack` unter dem Datum setzen.

---

## 5. Bekannte Grenzen

- **Keine Unterscheidung mehrerer Personen.** Die App hört nur, was im Raum zu hören ist. Schnarchen oder Sprechen von Partnerin, Partner, Fernseher oder Straße lässt sich nicht von deinem trennen und wird mitgezählt.
- **Genauigkeit des Apple-Klassifikators.** Der Klassifikator ist ein allgemeines Modell von Apple, kein auf dich trainiertes. Er kann Schnarchen mit anderem Rauschen verwechseln, leises Sprechen übersehen und liefert Konfidenzen, keine Gewissheit. Die Schwelle 0,6 ist ein Anfangswert, kein abgestimmter. Die Label-Namen sind ungeprüft und müssen zur Laufzeit gegen die Liste des Klassifikators geprüft werden (U32); fehlt ein Name, wird diese Ereignisart nie erkannt. Ob die Fensterdauer 1,5 s zulässig ist, ist ebenfalls ungeprüft (U34).
- **Bewegung und Unruhe werden nicht erfasst.** Die CoreMotion-Erweiterung ist zurückgestellt. Der Unruhe-Index steht deshalb überall auf „–“. Das Datenmodell hält die Felder für eine spätere Erweiterung bereit.
- **Clip-Dateinamen in UTC.** `FileStore.makeClipRelativePath` benennt Clips nach UTC (`yyyyMMdd-HHmmss-<art>.m4a`), damit der Name nicht von der Zeitzone des Geräts abhängt. Die App selbst zeigt Zeiten in der lokalen Zeit. Beispiel: Ein Schnarch-Clip um 02:30 Uhr Sommerzeit (MESZ, UTC+2) heißt `…-003000-snoring.m4a`.
- **Aufnahme endet, wenn iOS die App beendet.** Trotz Hintergrund-Audio kann iOS die App beenden (z. B. bei Speicherknappheit oder wenn sie nach einer Unterbrechung nicht wieder aufnehmen darf). Dann endet die Aufnahme ohne Meldung. Beim nächsten Start markiert die App die Nacht als „Unerwartet beendet“; als Ende gilt der Zeitpunkt der zuletzt gespeicherten Epoche oder das Ende des letzten Ereignisses, ohne Daten der Start. Die Daten bis dahin bleiben erhalten (gespeichert wird spätestens alle 120 s).
- **Unterbrechungen.** Nach einer Unterbrechung (Anruf, Wecker, Siri, Route-Wechsel, Media-Services-Reset) startet die App automatisch neu und protokolliert eine Lücke („Unterbrechungen“ in der Zusammenfassung). Der Neustart wird sofort versucht und danach nach 1, 2, 5, 10 und 30 s wiederholt. Dass das bei gesperrtem Bildschirm und bei Unterbrechungen, die länger als 30 s dauern, funktioniert, ist **ungeprüft** (U20, U21).
- **Wiedergabe nur außerhalb einer Aufnahme.** Während eine Nacht läuft, sind die Play-Buttons deaktiviert (Audio-Session-Kategorie, Spec B1).
- **Keine automatische Bereinigung.** Clips bleiben, bis du die Nacht oder das Ereignis löschst. Ein Überblick über den Speicherverbrauch und „Alle Daten löschen“ kommen mit Phase 2.
- **Bildschirmsperre.** Die App verhindert die automatische Sperre nicht; ob die Aufnahme bei gesperrtem Bildschirm über Stunden zuverlässig läuft, ist ungeprüft (U20, U21, U45).
- **Kostenlose Apple-ID.** Die installierte App läuft nach 7 Tagen ab (siehe Abschnitt 2).
- **Plattform.** Nur iPhone, nur Hochformat, iOS 17.0 oder neuer.

---

## 6. Projektstruktur

```
.
├── project.yml                     XcodeGen-Definition (Targets, Schema, Build-Einstellungen)
├── README.md                       dieses Dokument
├── docs/
│   ├── spec.md                     verbindliche Spezifikation (Teil A Vorgabe, Teil B Entscheidungen)
│   ├── plan.md                     Umsetzungsplan
│   └── unverified.md               vollständige Liste der ungeprüften Annahmen (englisch)
├── SleepTracker/                   App-Target
│   ├── Info.plist                  von Hand geschrieben: Mikrofon- und Bewegungstext, Hintergrund-Audio
│   ├── App/
│   │   ├── SleepTrackerApp.swift       App-Einstieg, Start-Fehleranzeige
│   │   ├── AppDependencies.swift       baut Store, Repository, Controller und Player einmal auf
│   │   └── RootTabView.swift           Tab-Leiste (Heute Nacht, Nächte)
│   ├── Audio/
│   │   ├── AudioSource.swift           Protokoll für Audioquellen und ihren Delegate, Unterbrechungsgründe
│   │   ├── MicrophoneAudioSource.swift Mikrofon über AVAudioEngine, Neustart nach Unterbrechungen
│   │   ├── AudioSessionManager.swift   AVAudioSession: .record/.measurement und .playback
│   │   ├── MonoDownmix.swift           Puffer-Konvertierung auf Mono Float32
│   │   ├── RingBuffer.swift            Ringpuffer (10 s) für den Pre-Roll
│   │   ├── LevelMeter.swift            RMS in dBFS und Drossel für den Live-Pegel
│   │   ├── LevelEpochAggregator.swift  30-Sekunden-Epochen mit Durchschnitt und Spitze
│   │   ├── ClipRecorder.swift          reine Logik: welche Samples in einen Clip gehören
│   │   ├── ClipWriting.swift           Protokoll für das Schreiben eines Clips
│   │   └── ClipWriter.swift            AAC-Datei (.m4a) schreiben
│   ├── Analysis/
│   │   ├── SoundClassifying.swift      Protokolle für Klassifikator und Delegate
│   │   ├── SoundClassifierService.swift SoundAnalysis mit SNClassifySoundRequest
│   │   ├── ClassificationWindow.swift  Ergebnis eines Analysefensters, Rangliste der Labels
│   │   ├── LabelMapping.swift          zentrale Zuordnung Label → Ereignisart
│   │   ├── EventDetector.swift         Zustandsautomat: Fenster → Ereignisse (Start, Ende, Merge)
│   │   └── ClipPolicy.swift            entscheidet, ob für ein Ereignis ein Clip aufgenommen wird
│   ├── Session/
│   │   ├── AudioPipeline.swift         verbindet Quelle, Klassifikator, Pegel, Ringpuffer, Detektor, Clips
│   │   ├── SleepSessionController.swift orchestriert eine Nacht (Start, Stopp, Live-Zustand, Speichern)
│   │   ├── InterruptionGap.swift       Lücke durch eine Unterbrechung
│   │   ├── NightStatistics.swift       reine Logik: Kennzahlen einer Nacht
│   │   └── SleepSession+Statistics.swift Kennzahlen aus einem SwiftData-Modell
│   ├── Persistence/
│   │   ├── Models.swift                SwiftData: SleepSession, SoundEvent, EpochSample
│   │   ├── SessionRepository.swift     alle Schreib- und Lesezugriffe auf dem Main Actor
│   │   └── FileStore.swift             Ordnerlayout, Clip-Pfade, Dateischutz
│   ├── Features/
│   │   ├── Tonight/                    TonightView, StartHintsSheet, NightScreenView
│   │   ├── Nights/                     NightsListView, NightRowView
│   │   └── NightDetail/                NightDetailView, EventRowView, ClipPlayer
│   └── Shared/
│       ├── AppSettings.swift           alle einstellbaren Werte mit Standardwerten (Codable)
│       ├── SettingsStore.swift         lädt und speichert die Einstellungen in UserDefaults
│       ├── SoundEventType.swift        Ereignisarten mit deutschem Namen und Symbol
│       ├── Formatters.swift            Anzeige- und Export-Formatierung
│       └── Theme.swift                 Farben für die dunkle Oberfläche
└── SleepTrackerTests/              Unit-Test-Target
    ├── Fakes/                      FakeAudioSource, FakeSoundClassifier, FakeClipWriter
    └── *Tests.swift                siehe Abschnitt 7
```

Für Phase 2 sind laut `docs/plan.md` vorgesehen: `Features/Settings/SettingsView.swift`, `Features/Debug/DebugView.swift`, `Features/Debug/TestModeView.swift`, `Features/NightDetail/NightTimelineChart.swift`, `Audio/FileAudioSource.swift` und `.github/workflows/build.yml`.

---

## 7. Tests

Die Tests (`SleepTrackerTests/`, XCTest, 102 Testmethoden in 14 Dateien) decken die reine Logik ab und laufen mit Fakes statt echter Hardware. Auch sie wurden **noch nie ausgeführt**.

| Datei | Geprüft wird |
|---|---|
| `RingBufferTests` | Ringpuffer (Umlauf, Schreiben über die Kapazität hinaus, Leeren, Grenzfälle) |
| `LevelMeterTests`, `LevelEpochAggregatorTests` | RMS in dBFS, Drossel des Live-Pegels, 30-s-Epochen |
| `LabelMappingTests` | Zuordnung nur für Labels, die es wirklich gibt |
| `EventDetectorTests` | Ausreißer, Lücken, Zusammenführen, Ereignis bei Session-Ende, Einschlafverzögerung, Teilen langer Ereignisse |
| `ClipPolicyTests` | Limits pro Nacht, Mindestabstand für Schnarch-Clips |
| `ClipRecorderTests` | Pre-Roll, Post-Roll, Fortsetzen im Post-Roll, Maximaldauer |
| `FileStoreTests` | Ordnerlayout, Clip-Pfade (UTC), Löschen, Größenberechnung |
| `SessionRepositoryTests` | SwiftData im Speicher: Anlegen, Speichern, Löschen mit Clips, „unerwartet beendet“ |
| `AudioPipelineTests` | die ganze Pipeline mit `FakeAudioSource`, `FakeSoundClassifier` und `FakeClipWriter` |
| `NightStatisticsTests` | Dauer, Schnarchzeit und -anteil, Zählungen, Lücken |
| `AppSettingsTests`, `FormattersTests` | Standardwerte, tolerantes Dekodieren, Formatierung |
| `SmokeTests` | Platzhalter-Test, dass das Test-Target mit der App linkt (`@testable import SleepTracker`) |

**Nicht** durch Unit-Tests abgedeckt sind alles mit Hardware oder UI: `MicrophoneAudioSource`, `SoundClassifierService`, `ClipWriter`, `MonoDownmix` (nur mittelbar über die Pipeline-Tests), `SleepSessionController`, `AppDependencies`, `ClipPlayer` und alle Views. Diese Teile lassen sich nur auf dem Gerät prüfen; die Einträge in Abschnitt 4 sagen, wie.

**Ausführen:**

- In Xcode: einen iPhone-Simulator als Run Destination wählen und **Product > Test** (⌘U), mit dem Schema `SleepTracker`.
- Auf der Kommandozeile (Simulator-Name an die eigene Installation anpassen, Liste mit `xcrun simctl list devices available`):
  ```bash
  xcodebuild test -project SleepTracker.xcodeproj -scheme SleepTracker \
    -destination 'platform=iOS Simulator,name=iPhone 15'
  ```
- Phase 2 ergänzt einen CI-Workflow, der das auf einem macOS-Runner ohne Signing ausführt.
