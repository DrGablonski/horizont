# Mehrkalender & fremde CalDAV-Server — verbindlicher Design-Kontrakt

Dieser Dokument-Abschnitt ist der **Vertrag** für alle (Sub-)Agenten. Namen, Signaturen und
JSON-Felder sind verbindlich; weiche davon nicht ab. Deutsch im Code-Kommentar, wie im Repo üblich.

## 1. Ziel

1. **Beliebig viele CalDAV-Server** (Haupt-Instanz Radicale/Baïkal/Nextcloud … **und** iCloud,
   Fastmail, Google-Proxy, Mozilla/andere Hosted) parallel. Bestehende Multi-Connection-Basis
   wird ausgebaut, nicht neu erfunden.
2. **Eigene Kalender anlegen/verwalten**: Name, Farbe, Sichtbarkeit, Schreibschutz,
   Standardkalender, Löschen — physisch per `MKCALENDAR` auf dem Ziel-Server.
3. **Rollen**: genau eine Verbindung ist **primary** (Hauptkalender: Workflows, interne
   Workflow-Kalender, Standardziele). Alle anderen sind **secondary** (anzeigbar, optional
   schreibbar, **nie** Workflow-Ziel).
4. Alles muss funktionieren: **Web-UI, macOS-App, iPad-App, MCP, headless (nur API)**.
5. **Cache**: Panel-Cache (server) und Snapshot-Cache (macOS/iPad) müssen Termine aus *allen*
   eingebundenen Kalendern enthalten — nie nur vom Hauptkalender.

## 2. Typen (`src/lib/types.ts`) — bereits umgesetzt, nur verwenden

- `CalDavProvider = 'generic' | 'icloud' | 'google' | 'nextcloud' | 'radicale' | 'bailkal' | 'fastmail'`
- `ConnectionRole = 'primary' | 'secondary'`
- `CalDavConnection` +`role: ConnectionRole` +`provider: CalDavProvider`
- `ConnectionView` +`role`, +`provider`
- `ConnectionsResponse` +`primaryId: string | null`
- `CalDavCalendar` +`connectionId?`, +`writable?`, +`supportedComponents?`
- `CalendarView` = `CalDavCalendar` + `connectionId`, `role`, `writable`, `writeDisabled`,
  `hidden`, `isDefault`, `order`, `colorOverride`, `supportedComponents`
- `CalendarsResponse` +`errors: string[]`, +`primaryId: string | null`
- `CalendarPref`, `CalendarCreateInput`, `CalendarUpdateInput`, `ProviderPreset`

## 3. Module mit fester Signatur

### 3.1 `src/server/store/calendarPrefs.ts` (NEU)
Persistenz: `DATA_DIR/users/<id>/calendar-prefs.json`, Format `{ version: 1, prefs: Record<kalenderId, CalendarPref> }`,
atomar schreiben (`.tmp` → `renameSync`), defektes JSON → `{}` (Muster wie `store/categories.ts`).
`CalendarPref.name` ist der lokal gemerkte Anzeigename als Fallback für Server, die PROPPATCH auf
`D:displayname` ablehnen (iCal-Server); gelingt der PROPPATCH später, wird das Feld wieder entfernt.

```ts
export function getCalendarPrefs(userId: string): Record<string, CalendarPref>;
export function setCalendarPrefs(userId: string, prefs: Record<string, CalendarPref>): void;
/** patch = null → Eintrag löschen. Leere Objekte werden entfernt. Invalidiert den Panel-Cache. */
export function updateCalendarPref(userId: string, calendarId: string, patch: Partial<CalendarPref> | null): Record<string, CalendarPref>;
/** Setzt (oder löscht bei null) den Standardkalender; entwertet alle anderen isDefault. */
export function setDefaultCalendar(userId: string, calendarId: string | null): Record<string, CalendarPref>;
export function getDefaultCalendarId(userId: string): string | null;
```

### 3.2 `src/server/store/connections.ts`
- Dateiformat: `{ version: 2, connections: CalDavConnection[], primaryId: string | null }`
  (Version 1 ohne `primaryId` muss weiter lesen: `primaryId = connections[0]?.id ?? null`).
- `createConnection(userId, input: ConnectionInput & { provider?: CalDavProvider; role?: ConnectionRole })`
  → erste Verbindung wird automatisch `primary`, jede weitere `secondary`.
- `export function getConnectionById(userId: string, connId: string): CalDavConnection | null`
- `export function setPrimaryConnection(userId: string, connId: string): CalDavConnection`
  → genau diese Verbindung `role='primary'`, alle anderen `'secondary'`; wirft `Error('Verbindung nicht gefunden.')`.
- `listConnectionsView` liefert `role`, `provider`; `ConnectionsResponse.primaryId` = `primaryId`.
- `getPrimaryConnection`: `primaryId`-Treffer, sonst erste Verbindung (Abwärtskompatibilität).

### 3.3 `src/server/caldav/client.ts`
- `listCalendars(settings, home)` fragt zusätzlich `current-user-privilege-set` und
  `supported-calendar-component-set` ab und setzt am zurückgegebenen `CalDavCalendar`:
  `writable` (`write-bind` oder `write-content` vorhanden; **kein** Privilege-Knoten ⇒ `writable = true`),
  `supportedComponents: string[]` (leer ⇒ `['VEVENT','VTODO']`).
- `export async function deleteCollection(settings: CalDavSettings, url: string): Promise<void>` — `DELETE`,
  200/201/204 = ok, sonst `CalDavError`.
- `export async function setCollectionDisplayName(settings: CalDavSettings, url: string, displayName: string): Promise<boolean>`
  — `PROPPATCH` auf `D:displayname`; `true` bei 200/207, `false` bei 400/403/405/501 (Server kann das nicht).
- `mkCalendar(settings, url, displayName, components?: string[])` (existiert) — `components`
  defaultet `['VEVENT','VTODO']` und wird als `C:supported-calendar-component-set` ins MKCALENDAR-XML.

### 3.4 `src/server/caldav/multi.ts`
```ts
export interface ResolvedCalendar { connection: CalDavConnection; calendar: CalendarView } // calendar enthält connectionName + Prefs
export async function resolveAllCalendars(conns: CalDavConnection[]): Promise<ResolvedAll>  // Rohzustand ohne Prefs
/** CalDAV + lokale Prefs verschmelzen. Sortierung: order aufsteigend, dann Name. */
export async function resolveCalendarViews(
  userId: string,
  conns: CalDavConnection[],
  opts?: { includeHidden?: boolean; writableOnly?: boolean }
): Promise<{ calendars: CalendarView[]; errors: string[]; primaryId: string | null }>
/** Kalender über alle Verbindungen, Prefs angewendet; null wenn nicht gefunden. */
export async function findCalendarView(userId: string, conns: CalDavConnection[], calendarId: string): Promise<ResolvedCalendar | null>
/** Zulässiges Ziel für neue Einträge: explizit ? sonst Standardkalender ? sonst erster beschreibbarer Kalender der primary-Verbindung. */
export async function resolveWriteTarget(userId: string, conns: CalDavConnection[], calendarId?: string | null): Promise<ResolvedCalendar>
```
`resolveWriteTarget` wirft `Error('Kein beschreibbarer Kalender gefunden.')`, wenn alles schreibgeschützt ist,
und `Error('Kalender <name> ist schreibgeschützt.')`, wenn ein explizit genanntes Ziel `writeDisabled`/`!writable` ist.
Regeln: `secondary`-Kalender sind als Schreibziel **erlaubt**, solange nicht `writeDisabled`.
`role` wird aus `connection.role` übernommen; `connectionId` immer gesetzt.

### 3.5 `src/server/lib/write.ts`
- Neuer Fehler: `export class ReadOnlyError extends Error` (Nachricht auf Deutsch) → Routen mappen ihn auf **403**.
- Alle Write-Pfade (`createEvent`, `updateEvent`, `deleteEvent`, `createTask`, `updateTask`, `deleteTask`)
  nutzen `findCalendarView`/`resolveWriteTarget` statt `findCalendarAcross` und werfen `ReadOnlyError`,
  wenn `calendar.writeDisabled === true` oder `calendar.writable === false`.
- `EventCreateInput.calendarId` / `TaskCreateInput.calendarId` sind **optional** geworden: fehlend ⇒ `resolveWriteTarget`.
- Nach jeder Schreiboperation wie bisher `invalidatePanelCache()`.

### 3.6 `src/server/lib/panels.ts` + `panelCache.ts`
- Panel-/Archiv-Aufbau arbeitet über `resolveCalendarViews(userId, conns, { includeHidden: false })`,
  d. h. **ausgeblendete Kalender erscheinen in keiner Ansicht** (Timeline wie Archiv), und zwar für
  alle Clients inklusive headless/MCP.
- Es müssen weiterhin Termine aus **allen** Verbindungen eingesammelt werden (Regressionstest:
  Zweitverbindung liefert Termine in der Timeline).
- Panel-Cache-Key: bisher global → **erweitern** um eine Cache-Generation, damit ein Wechsel der
  Kalender-Sichtbarkeit die Panels verwirft. dafür: `invalidatePanelCache()` wird bei allen
  Kalender-Pref-Änderungen aufgerufen (das geschieht bereits über `updateCalendarPref`).

### 3.7 Workflows (`src/server/store/store.ts`, `src/server/store/workflowStore.ts`)
- Workflows bleiben ausschließlich in der **primary**-Verbindung (`requirePrimary` nutzt jetzt `primaryId`).
- Zusätzliche Sperre: kein Workflow-Kalender in einer `secondary`-Verbindung —
  `requirePrimary` wirft `NotConfiguredError`, wenn die primary-Verbindung fehlt.
- Sekundäre Kalender sind nie Workflow-Ziel (kein UI, kein API-Pfad).

## 4. HTTP-API (alle unter `/api`, Fehler immer `{ error: string }`)

| Methode + Pfad | Zweck | Antwort |
| --- | --- | --- |
| `GET /api/calendars` | alle Kalender inkl. Prefs (`?sichtbar=1` nur sichtbare) | `CalendarsResponse` |
| `POST /api/calendars` | Kalender anlegen (`CalendarCreateInput`) | 201 + `CalendarView` |
| `PATCH /api/calendars/[id]` | Prefs/Name ändern (`CalendarUpdateInput`, `connectionId` = Zielverbindung) | `CalendarView` |
| `DELETE /api/calendars/[id]` | Collection löschen (Body `{ name: string }` = Bestätigung, muss exakt passen) | `{ ok: true }` |
| `GET /api/settings/presets` | Anbieter-Vorlagen | `{ presets: ProviderPreset[] }` |
| `GET/POST/PATCH/DELETE /api/settings` | wie bisher + `provider`, `role`; `role:'primary'` ⇒ `setPrimaryConnection` | wie bisher |
| `POST /api/settings/test` | Test + Kalenderliste jetzt mit `writable`/`supportedComponents` | `TestResult` |

Statuscodes: 400 Validierung, 401 ohne Session (settings/calendars-Prefs), 403 `ReadOnlyError`
bzw. Löschbestätigung, 404 unbekannter Kalender, 409 Konflikt, 502 `CalDavError`, sonst 500.
Nach jeder Kalender-/Verbindungs-Mutation: `invalidatePanelCache()`.

Anlegen: Ziel-URL = `<home><slug>-<6 hex>.ics` (`slug` = ASCII-normalisierter Name, sonst `kalender`),
danach `mkCalendar` + optionale Farbe als lokaler `CalendarPref.color`.

Verbote: Löschen des internen Workflow-Kalenders (`WORKFLOWS_CALENDAR` aus
`src/server/lib/constants.ts`), Löschen des letzten beschreibbaren Kalenders der primary-Verbindung.

Anbieter-Vorlagen (statisch, ohne Secrets):

| id | url | Hinweis |
| --- | --- | --- |
| `icloud` | `https://caldav.icloud.com` | Apple-ID + **app-spezifisches Passwort** (appleid.apple.com); Kalender-Anlage von Apple oft untersagt (403 → Meldung zeigen) |
| `google` | `https://www.googleapis.com/calfuzzer` → **nicht** verwenden; real: Google unterstützt kein CalDAV mit Passwort. Hinweis: „Google braucht OAuth2 — bitte CalDAV-tauglichen Anbieter verbinden“ | `supportsCalendarCreation: false` |
| `fastmail` | `https://caldav.fastmail.com/dav/` | App-Passwort |
| `nextcloud` | `https://<host>/remote.php/dav/` | Benutzer + (App-)Passwort |
| `radicale` | `https://<host>:5232/` | eigener Server |
| `bailkal` | `https://<host>/dav.php` | eigener Server |
| `generic` | frei | „Eigene CalDAV-URL“ |

## 5. Clients

- **Web** (`src/lib/api.ts`, `src/routes/einstellungen/+page.svelte`): neuer Abschnitt **Kalender**
  (nach „CalDAV-Verbindungen“): Gruppe pro Verbindung, pro Kalender Sichtbarkeit (Auge),
  Schreibschutz, Farbe, „Standard“-Radio, Umbenennen, Löschen (Bestätigung = Name), plus
  „Neuer Kalender“ (Verbindung + Name + Farbe). „Neue Verbindung“ mit Anbieter-Chips aus `/api/settings/presets`.
- **macOS** (`apple/`): `APIModels.swift` + `APIClient.swift` (Vertrag oben), neuer
  Einstellungen-Bereich **Kalender** (`enum Area` + `SettingsView.swift`), Kalender-Chips in der
  Timeline (Umschalten = `PATCH /api/calendars/[id] { hidden }`), Snapshot-Cache über alle Kalender.
- **iPad** (`ipad/`): wie macOS (Modelle, `SettingsView`, Standardkalender im `EditItemView`).
- **MCP** (`mcp-server/index.mjs`): `calendars` liefert `role/writable/hidden/isDefault/connectionName`;
  neue Tools `create_calendar`, `update_calendar`, `delete_calendar`, `set_primary_connection`;
  `create_event`/`create_task` ohne `calendarId` = Standardkalender.
- **Doku**: `README.md` (neue Funktionen, Anbieter-Hinweise inkl. iCloud/Google-Einschränkungen,
  neue Endpunkte + MCP-Tools).

## 6. Stilregeln

- Kommentare und UI-Texte auf Deutsch, Svelte 5 Runes, keine neuen Abhängigkeiten,
  `bun run check` muss grün bleiben. Keine TODO-Kommentare, kein toter Code.
