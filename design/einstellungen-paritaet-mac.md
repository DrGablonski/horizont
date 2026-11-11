# Mac-App: volle Parität der Einstellungen mit der Headless-Server-API

**Status: umgesetzt (2026-11-10).** Alle vier Phasen sind implementiert und bauen
(macOS-Ziel, `xcodebuild … build` → Erfolg): Notify-Parität (Token, URL-Aufteilen,
„Jetzt senden", echte Testergebnisse), CalDAV-CRUD, Kategorien-Seite, API-Token-Seite.
**Nachfolger (umgesetzt):** Phase 5 „Kalender & Anbieter-Vorlagen" aus
[`mehrkalender-und-fremde-caldav.md`](mehrkalender-und-fremde-caldav.md) —
Kalender-Seite, Rollen/Umbenennung, Anbieter-Chips und Kalender-Chips sind in
der Mac-App (und parallel in der iPad-App) gelandet.

**Stand-Analyse (Deep Dive) + Umsetzungsplan**

Referenz, was der Server alles kann: `src/routes/einstellungen/+page.svelte` (Web-UI)
und die API-Routen unter `src/routes/api/`. Mac-Gegenstück:
`apple/Sources/Views/SettingsView.swift` + `apple/Sources/API/APIClient.swift`
+ `apple/Sources/State/AppStore.swift`.

---

## 1. Gap-Analyse: Was die Server-API bietet vs. was die Mac-App steuert

### CalDAV-Verbindungen — `api/settings/+server.ts` (GET/POST/PATCH/DELETE) + `api/settings/test/+server.ts`

| Funktion | Web | Mac-App |
| --- | --- | --- |
| Verbindungen anzeigen | ✅ | ✅ (`ConnectionsSection`) |
| Verbindung testen (gespeicherte `id`) | ✅ | ✅ (`APIClient.testConnection(id:)`) |
| **Verbindung anlegen (POST)** | ✅ | ❌ |
| **Verbindung bearbeiten (PATCH)** | ✅ | ❌ |
| **Verbindung löschen (DELETE)** | ✅ | ❌ |
| **Testen mit Formularwerten (url/username/password, ohne Speichern)** | ✅ | ❌ (nur `id`) |

Die Mac-App ist aktuell bewusst read-only („CRUD bleibt in der Web-App“,
Kommentar in `SettingsView.swift` Zeile 5) — genau das soll entfallen.
Auf Serverseite passiert bei jedem CRUD bereits `invalidatePanelCache()`,
die App muss danach nur `connections` + `calendars` neu laden.

### Aufgaben-Kategorien — `api/categories/+server.ts`

| Funktion | Web | Mac-App |
| --- | --- | --- |
| Laden | ✅ | ✅ (nur für Chips in Editor/Notify) |
| **Komplette CRUD-UI (anlegen, umbenennen, Farbe, löschen, Standard wiederherstellen)** | ✅ | ❌ |

Wichtig: `APIClient.saveCategories(_:)` existiert bereits (Zeile 251),
es fehlt **nur die Einstellungs-UI**. Validierungsregeln (1–40 Zeichen,
kein Komma/Semikolon, Duplikat-Prüfung case-insensitive) liegen in
`src/lib/categories.ts` (`normalizeCategoryName`) und müssen in Swift
nachgebaut werden.

### Benachrichtigungen (Webhook) — `api/notify/+server.ts`, `api/notify/test/`, `api/notify/send/`

| Funktion | Web | Mac-App |
| --- | --- | --- |
| Frequenz/Zeit/Wochentag/Intervall + Kategorien + Prompt | ✅ | ✅ |
| Testversand | ✅ | ⚠️ teilweise |
| **Feld „Zugriffsschlüssel (Token)"** | ✅ | ❌ |
| **„Komplette Webhook-URL einfügen" + Aufteilen** | ✅ | ❌ |
| **„Jetzt senden" (`POST /api/notify/send`)** | ✅ | ❌ (Client-Methode fehlt komplett) |
| Testergebnis mit HTTP-Status / `x-t3-hook-outcome` | ✅ (`NotifyTestResult`) | ❌ (decodiert nur `OKResponse`) |

Folge: **Ohne Web-App kann die Mac-App die Notify-Konfiguration nie
vollständig einrichten** — ein (neuer) Token kann nicht gesetzt werden,
und ohne Token lehnen `/api/notify/test` und `/api/notify/send` ab
(`Bitte Webhook-URL und Token angeben.`).

### API-Token (MCP/externe Zugriffe) — `api/token/+server.ts` (GET/POST/DELETE)

| Funktion | Web | Mac-App |
| --- | --- | --- |
| Status (hat Token, erstellt am, zuletzt genutzt) | ✅ | ❌ |
| Neuen Token erzeugen (Klartext nur einmal, kopieren) | ✅ | ❌ |
| Token ablehnen | ✅ | ❌ |

Komplett fehlende Feature-Seite. Kuriose Randnotiz: `ApiTokenGenerated`
existiert bereits in `APIModels.swift` (Zeile 28), wird aber nirgends
verwendet — Restbestand, kann wiederverwendet werden.

### Abgedeckt (kein Handlungsbedarf)

- Auth (login/logout/me): komplett da; einen Passwort-Wechsel-Endpunkt
  gibt es auf dem Server gar nicht → nichts fehlendes.
- Kalender anzeigen (`/api/calendars`): da — inzwischen volle
  Kalender-Verwaltungsseite (siehe Phase 5).
- Workflows, Tasks, Events (CRUD): in der App ohnehin schon voll.
- „Darstellung" und „Konto" sind reine App-lokale Seiten ohne Server-Gegenstück.

---

## 2. Umsetzungsplan

Reihenfolge nach Nutzen/Aufwand; jeder Schritt ist unabhängig liefer- und testbar.

### Phase 1 — Notify-Parität (kleinster Gap, höchste Wirkung)

1. **`APIClient.swift`**
   - `sendNotifyTest(url:token:prompt:)` um `token` erweitern und
     `NotifyTestResult { ok, status?, outcome?, error? }` decodieren
     (neues Modell in `APIModels.swift`).
   - Neue Methode `sendNotifyNow() -> NotifySendResult` für `POST /api/notify/send`
     (`ok/skipped/outcome/error`).
2. **`AppStore.swift`**
   - `saveNotify(…)` um Parameter `token: String = ""` (leer → Feld im Body
     weglassen, damit gespeicherter Token erhalten bleibt — Serververhalten:
     `token === undefined` ⇒ behalten).
   - `sendNotifyTest` gibt Ergebnis-String/Typ zurück statt nur Fehlertext;
     `sendNotifyNow()` + danach `loadNotify()` (Lauf-Status aktualisieren).
3. **`SettingsView.swift` → `NotifySection`**
   - SecureField „Zugriffsschlüssel (Token)" mit Platzhalter je nach
     `notify.hasToken` („gespeichert — leer lassen zum Behalten").
   - Abschnitt „Komplette Webhook-URL einfügen" + Button „Aufteilen"
     (splitzt am letzten `/` in URL + Token wie die Web-App).
   - Button „Jetzt senden" (disabled ohne `url`+`hasToken`), Ergebnis als
     Flash/Fehler-Banner; „Testversand" zeigt zusätzlich HTTP-Status/Outcome an.
   - Pflichtfeld-Check: mindestens 1 Kategorie beim Speichern (wie Web).

### Phase 2 — CalDAV-CRUD

1. **`APIClient.swift`**
   - `createConnection(name:url:username:password:)`,
     `updateConnection(id:…)` (password optional → Feld weglassen =
     beibehalten), `deleteConnection(id:)` — alle geben
     `ConnectionsResponse` zurück.
   - `testConnection(url:username:password:)` -Overload für ungespeicherte
     Formularwerte.
2. **`AppStore.swift`**: Wrapper, die nach jeder Mutation `connections`
   ersetzen und `loadCalendars()` nachziehen (Cache ist serverseitig schon invalidiert).
3. **`SettingsView.swift` → `ConnectionsSection`**
   - Pro Verbindungskarte Buttons „Bearbeiten" (inline-Formular wie Web:
     Name/URL/Benutzer/Passwort-mit-Platzhalter) und „Löschen"
     (`.confirmationDialog` statt `confirm()`).
   - Aufklappbares Formular „CalDAV-Quelle anlegen" inkl. „Erst testen".
   - Hinweis-Text zur URL (nur Server-Adresse, Automatik-Erkennung) übernehmen.
   - Kommentar in Zeile 5 der Datei anpassen (read-only-Fallout ist Geschichte).

### Phase 3 — Kategorien-Seite

1. **`SettingsView.swift`**: neuer `Area.kategorien` („Kategorien", Icon `tag`)
   mit neuer `CategoriesSection`:
   - Zeile pro Kategorie: Color-Picker (`ColorPicker`, Farb-Hex ↔ `#RRGGBB`),
     TextField (Umbenennen bei `onSubmit`/Focus-Verlust), Delete-Button mit Dialog.
   - Neue Kategorie: Color-Picker + TextField + „Hinzufügen".
   - „Standard herstellen"-Button → `DEFAULT_TASK_CATEGORIES` aus
     `src/lib/categories.ts` als Swift-Konstante nachbauen.
2. **Validierung in Swift**: `normalizeCategoryName` portieren
   (trim, 1–40 Zeichen, keine `,`/`;`, Duplikat-Check case-insensitive).
3. Nach jeder Änderung `store.loadCategories()` — Editor-Chips und
   Notify-Auswahl leben von derselben Liste.
   (`saveCategories` im Client gibt die bereinigte Liste zurück; direkt setzen.)

### Phase 4 — API-Token-Seite

1. **`APIModels.swift`**: `ApiTokenView { hasToken, createdAt?, lastUsedAt? }`
   (an `src/lib/types.ts` orientieren); `ApiTokenGenerated` ist schon vorhanden.
2. **`APIClient.swift`**: `apiToken() -> ApiTokenView` (GET),
   `generateApiToken() -> ApiTokenGenerated` (POST), `revokeApiToken()` (DELETE).
3. **`SettingsView.swift`**: neuer `Area.token` („API-Zugang", Icon `key`) mit:
   - Status („Token erstellt am … · zuletzt genutzt …" / „Noch kein Token").
   - „Token erzeugen" (mit Ersetzen-Bestätigung), Klartext **einmalig** in
     Ergebnis-Box + „Kopieren" (`NSPasteboard`), „Token ablehnen" mit Dialog.

### Phase 5 — Kalender & Anbieter-Vorlagen (Nachfolger, umgesetzt)

Aus dem Kontrakt [`mehrkalender-und-fremde-caldav.md`](mehrkalender-und-fremde-caldav.md):

1. **`SettingsView.swift` → neuer `Area.kalender`** („Kalender",
   „Sichtbarkeit, Farben & Standardkalender"): Kalender pro Verbindung
   gruppiert, Rollen-Badge „Hauptkalender"/„Zusatzkalender"; pro Kalender
   Color-Picker, Schalter „Sichtbar" + „Beschreibbar" (→ `PATCH
   /api/calendars/<id>` mit `hidden`/`writeDisabled`), „Als Standard"
   (`isDefault`), Umbenennen und Löschen (Bestätigung = exakter Name);
   Sheet „Neuer Kalender" (`POST /api/calendars`, `MKCALENDAR`).
2. **Verbindungsformulare**: `ProviderChips` aus `GET /api/settings/presets`
   (iCloud, Google, Fastmail, Nextcloud, Radicale, Baïkal) füllen URL/
   Benutzernamen voraus; Rollen-Picker („Primär (Hauptkalender)") in
   Anlage- und Bearbeitungsformular — eine andere Verbindung hochzustufen
   ersetzt die Hauptverbindung (`PATCH /api/settings` mit `role:'primary'`);
   ein Downgrade der aktuellen ist nicht vorgesehen und wird in der App
   gesperrt.
3. **`HomeView.swift`**: Kalender-Chips über der Timeline (ab zwei Kalendern),
   Tap = aus-/einblenden (`hidden`), abgeblendet + durchgestrichen.
4. **`AppStore.swift`**: `providerPresets`-Load, `updateCalendar(…)`-patches,
   `createCalendar`/`deleteCalendar`; nach jeder Mutation Kalender + Panels
   neu laden (serverseitiger Cache ist bereits invalidiert).

**Offene Restarbeit:** `APIClient.swift`/`APIModels.swift` (macOS wie iPad)
müssen die passenden Typen (`CalendarView` mit `role`/`hidden`/`isDefault`,
`ProviderPreset`, `primaryId`) und Methoden (`createCalendar`,
`updateCalendar`, `deleteCalendar`, `providerPresets`) noch vollständig
führen — Views/Store rufen sie bereits auf.

### Querschnitt / Randnotizen

- **Snapshot-QA**: neue Areas erscheinen automatisch im `Area`-Enum;
  `SnapshotQA.swift`-Fixtures um Screenshots der neuen Seiten erweitern.
- **iPad-App (`ipad/`)**: dieselben Gaps; Phasen 1–4 sind dort teils offen,
   Phase 5 wurde parallel mit umgesetzt (Views + Store bereits auf
   Kalender-Verwaltung/Chips umgestellt, Modelle/Client folgen).
- **Keine Server-Änderungen nötig** — alle Endpunkte existieren und sind
  session-authentifiziert; die Mac-App nutzt bereits dasselbe Cookie-Login.

## 3. Geschätzter Umfang

| Phase | Dateien | Aufwand |
| --- | --- | --- |
| 1 Notify-Parität | APIClient, APIModels, AppStore, SettingsView | S |
| 2 CalDAV-CRUD | dito | M |
| 3 Kategorien | SettingsView, AppStore, (neue kleine CategoryEditor-View) | M |
| 4 API-Token | +2 Areas, Models, Client | S |
| 5 Kalender & Vorlagen | SettingsView, HomeView, AppStore, (APIModels/APIClient) | M |
