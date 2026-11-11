# Horizont

Minimalistischer, selbst hostbarer Kalender für **genau einen Benutzer** — mit
drei zusammenklappbaren Zeiträumen — **Vergangenheit**, **Jetzt** und
**Zukunft** — plus einem **Workflow/Fokus-Modus** für sequenzielle
Aufgabenlisten. Deine Termine kommen aus **CalDAV**-Backends (Radicale, Baïkal,
iCal, Nextcloud, …). Alle CalDAV-Verbindungen gehören dem Benutzer und sind
vollständig verwaltbar (anlegen, bearbeiten, testen, löschen).

Alles lebt in **einem Branch (`main`)**: Server, Web-App und die nativen
Apple-Apps (`apple/` = macOS, `ipad/` = iPadOS + Widgets, jeweils eigener
Code-Ordner). Beim **Docker-Build** entscheidest du, welche Variante du hostest:

| Variante | Start | Was läuft |
| -------- | ----- | --------- |
| **Web-App + API** (Standard) | `docker compose up -d --build` | komplette Web-UI + API |
| **Headless (nur API)** | `docker compose -f docker-compose.headless.yml up -d --build` | nur `/api/*` — für Mac-/iOS-Apps und MCP |

Der Headless-Build entfernt die UI-Dateien *vor* dem Build — das fertige Image
enthält schlicht keine Weboberfläche. Die API (Login, Workflows, CalDAV-
Verwaltung, Token) ist in beiden Varianten identisch; deshalb kann die Mac-App
oder MCP auch mit einer normalen Web-Instanz verbunden werden.

---

## Headless: ersten Benutzer anlegen

Ohne UI legst du den Benutzer per API an (nur möglich, solange noch keiner
existiert), danach Mac-App oder MCP verbinden:

```bash
curl -X POST http://localhost:8917/api/auth/setup \
  -H 'Content-Type: application/json' \
  -d '{"username":"ich", "password":"…"}'
```

CalDAV-Verbindungen danach über `POST /api/settings` (siehe API-Endpunkte unten)
anlegen.

## Native macOS-App (`apple/`)

SwiftUI-Client auf derselben API — egal ob Web- oder Headless-Instanz.
Bauanleitung im [`apple/README.md`](apple/README.md).

## Native iPadOS-App + Widgets (`ipad/`)

Eigenständiges XcodeGen-Projekt (iPad, iOS 17+) mit „Heute“-Widgets (Home-Screen +
Sperrbildschirm) und Gesten (Wischen = Erledigen). Eigener Code-Ordner, getrennt
von `apple/`. Bauanleitung im [`ipad/README.md`](ipad/README.md).

---

## Mehrere Kalender & Zusatz-Server

Neben der **Hauptverbindung** (`primary`) lassen sich beliebige weitere
CalDAV-Server als **Zusatzverbindungen** (`secondary`) anbinden — z. B. ein
zweiter Nextcloud-Account oder ein Familienkalender auf einem eigenen Server:

- **Rollen**: Timeline und Archiv zeigen die Termine *aller* Kalender.
  Workflows schreiben und suchen jedoch **nur** in Kalendern der
  Hauptverbindung; Zusatzkalender sind anzeigbar und optional beschreibbar,
  aber niemals Workflow-Ziel.
- **Kalender verwalten** (Mac-/iPad-App → Einstellungen → Kalender; die
  REST-API steht jedem Client offen, eine Web-UI-Seite fehlt noch): neue
  Kalender per `MKCALENDAR` direkt auf dem Server der Verbindung anlegen,
  umbenennen, Farbe setzen, ausblenden,
  Schreibschutz setzen/entfernen, einen Kalender als **Standard** markieren
  und Kalender löschen — der interne Workflow-Kalender und der letzte
  beschreibbare Kalender der Hauptverbindung sind geschützt (403).
- **Standard-Ziel**: fehlt bei `POST /api/events` bzw. `/api/tasks` die
  `calendarId`, wählt der Server den Standardkalender (sonst den ersten
  beschreibbaren Kalender der Hauptverbindung).
- **Präferenzen** (Farbe, Sichtbarkeit, Schreibschutz, Standard, lokaler Name)
  liegen serverseitig in `DATA_DIR/users/<id>/calendar-prefs.json` — ein
  reines Horizont-Feld, kein CalDAV-Feld; andere Kalender-Clients sehen es nicht.
- **Cache**: Timeline, Archiv und die Mac-/iPad-Snapshots enthalten die
  Termine aller sichtbaren Kalender; ausgeblendete Kalender tauchen in keiner
  Ansicht auf. Jede Kalender-Änderung verwirft den Panel-Cache neu.

**Anbieter-Vorlagen** (`GET /api/settings/presets`, in Mac- und iPad-App
vorausgefüllt):

| Anbieter | Hinweis |
| -------- | ------- |
| iCloud | Apple-ID + **app-spezifisches Passwort** (appleid.apple.com); Kalender-Anlage ist bei Apple oft untersagt (403) |
| Google Calendar | **kein** CalDAV mit Passwort (nur OAuth2) → nicht direkt verbindbar; die Vorlage zeigt nur den Hinweis |
| Fastmail | App-Passwort statt regulärem Passwort; Kalender-Anlage funktioniert |
| Nextcloud, Radicale, Baïkal | normale CalDAV-Server, Kalender-Anlage funktioniert |

---

## Funktionen

- **Ein Benutzer pro Instanz**
  - Login/Logout mit Session-Cookie (in-memory — bei Neustart alle Sessions
    beendet), scrypt-gehashte Passwörter.
  - **Erstes-Setup**: solange kein Benutzer existiert, legt `POST /api/auth/setup`
    den Benutzer an (headless; in der Web-App zusätzlich die Seite `/setup`).
    Danach ist der Endpunkt geschlossen.
- **Arbeits-Modell: drei Zeiträume** *(Darstellung in Web-UI/Mac-App)*
  - *Vergangenheit*: die letzten 14 Tage
  - *Jetzt*: heute + 2 Tage (Heute, Morgen, Übermorgen)
  - *Zukunft*: die nächsten 30 Tage
  - Jeder Abschnitt ist zusammenklappbar und zeigt Tage + Termine.
- **Archiv**: alle Einträge älter als zwei Wochen (bis zu 365 Tage zurück) —
  API-seitig abrufbar, in der Web-App als Monatsgrid (Mo–So) mit
  Tagesdetails pro Tag (`?monat=YYYY-MM` teilbar).
- **Workflows**: benutzerdefinierte, sequenzielle Aufgaben-Checklisten
  (serverseitig, für alle Clients gleich).
  - Fortschrittsanzeige, Aktiver-Schritt-Betonung, „Als Nächstes"-Vorschau.
  - **Fokus-Modus**: ablenkungsfreie Vollansicht mit nur dem aktuellen Schritt
    (Web-UI: `/fokus/<id>`; Mac-App: eigener View).
  - Schrittfortschritt wird sofort gespeichert.
- **CalDAV-Anbindung**: beliebig viele Verbindungen als Haupt- oder
  Zusatzverbindung (→ *Mehrere Kalender & Zusatz-Server*), vollständig
  editierbar/löschbar, Verbindungstest mit Kalender-Liste, Anbieter-Vorlagen,
  Kalender mit Farbe, Sichtbarkeit und Schreibschutz.
- **Dunkel-/Hellmodus** in der Web-UI (klassenbasiert, folgt dem System).

## Tech-Stack

- [SvelteKit](https://kit.svelte.dev/) + [Svelte 5](https://svelte.dev/) (Runes)
- [shadcn-svelte](https://shadcn-svelte.com/) + [Tailwind CSS v4](https://tailwindcss.com/)
- [Bun](https://bun.sh) für Build & Dev
- [ical.js](https://github.com/nextcloud-libs/ical.js) für iCalendar-Parsing,
  [fast-xml-parser](https://github.com/NaturalIntelligence/fast-xml-parser) für CalDAV-XML
- [adapter-node](https://kit.svelte.dev/adapter-node) für den produktiven Build
- [Docker](https://www.docker.com/) für den Betrieb (Proxmox / beliebiger Host)

---

## Zeitfenster (Konfiguration)

Die Zeiträume sind in [`src/server/lib/constants.ts`](src/server/lib/constants.ts)
zentral konfigurierbar:

| Konstante             | Default | Bedeutung                          |
| --------------------- | ------- | ---------------------------------- |
| `PAST_DAYS`           | 14      | Vergangenheit (Tage zurück)         |
| `NOW_EXTRA_DAYS`      | 2       | Jetzt: heute + N weitere Tage      |
| `FUTURE_DAYS`         | 30      | Zukunft: Tage ab heute+3           |
| `ARCHIVE_TOTAL_DAYS`  | 365     | Archiv: max. Tage zurück            |
| `ARCHIVE_PAGE_DAYS`   | 31      | Archiv: Tage pro Seite             |

---

## Schnellstart (Docker)

Voraussetzungen: Docker + Docker Compose.

```bash
# Im Repo-Verzeichnis:
docker compose up -d --build
```

Die App läuft danach unter <http://localhost:8917>.

### Deployment mit Dockge (Self-Hosted-Server)

Auf dem Server liegt das Repo als Git-Clone in `/root/horizont`. Dockge
verwaltet den Stack über einen Symlink: `/opt/stacks/horizont -> /root/horizont`
(Dockge folgt Symlinks beim Scannen des Stack-Verzeichnisses).

**Update nach Code-Änderungen** (Dockge selbst hat keinen Build-Button):

```bash
cd /root/horizont
git pull
docker build -t horizont .
```

Danach in Dockge für den Stack `horizont` auf **Deploy** klicken – das
erzeugt den Container mit dem neuen Image neu.

- **Erstes Starten**: <http://localhost:3000/setup> ist öffentlich (nur solange
  kein Benutzer existiert) und legt den Benutzer an. Bestehende Daten aus einer
  alten Installation (`data/settings.json`) werden automatisch als Verbindung
  übernommen; die Datei wird zu `settings.json.legacy` archiviert.
- Port ändern: in [`docker-compose.yml`](docker-compose.yml) unter `ports`
  (z. B. `"8080:3000"`).
- Alle Daten werden im Volume `horizont-data` unter `/app/data` persistiert:
  `users.json` (der Account), `users/<id>/` (Verbindungen, Workflows).
- Zum Löschen: `docker compose down -v`.

> **Proxmox:** am einfachsten über eine Container-Template-VM mit Docker oder ein
> LXC-Container mit Docker installiert. Dann exakt die drei Befehle von oben.

---

## Auth-Konzept

| Aspect           | Umsetzung                                                        |
| ---------------- | ---------------------------------------------------------------- |
| Passwort-Hashing | scrypt (N=16384, r=8, p=1), 16-Byte-Salt, 64-Byte-Key            |
| Sessions         | in-memory (Prozess), 12 h TTL, httpOnly/sameSite=lax-Cookie      |
| API-Token        | scrypt-gehasht (`DATA_DIR/users/<id>/api-token.json`), `Authorization: Bearer <token>` auf `/api/*` |
| Autorisierung    | `src/hooks.server.ts`: `/api/*` → 401, Seiten → Redirect          |
| User-Store       | `DATA_DIR/users.json` (genau ein Eintrag, kein DB)               |
| Userdaten        | `DATA_DIR/users/<id>/` (Verbindungen, Workflows, API-Token)      |

Der Login bleibt auch nach dem Setup erhalten (Session-Cookie); `/setup` ist nur
für die Ersteinrichtung offen.

---

## API-Token (Basis der externen Integration)

Externe Tools greifen **nur über den MCP-Server** (nächste Sektion) auf
Horizont zu. Dafür erzeugt der Benutzer in
**Einstellungen → „API-Token (für externe Zugriffe)“** einen persönlichen Token.
Der Token wird einmalig im Klartext angezeigt und serverseitig nur
scrypt-gehasht gespeichert (SHA-256-Digest als Lookup-Key). Ablehnen/Ersetzen
jederzeit in derselben Sektion.

Interner Aufruf des MCP-Servers: `Authorization: Bearer <token>` gegen die
`/api`-Endpunkte — die Endpunkte selbst sind internes Implementierungsdetail,
kein öffentliches Interface.

---

## MCP-Server (für OpenCode & Co.)

[`mcp-server/`](mcp-server/) ist ein kleiner MCP-Server (Node.js, stdio), der die
`/api`-Endpunkte mit dem API-Token adressiert und als Tools exponiert — z. B.
für OpenCode (→ `horizont_*`-Tools):

| Tool | Wirkung |
| --- | --- |
| `check_connection` | URL + Token prüfen (zeigt User, CalDAV-Status) |
| `calendars` | Kalender auflisten (`calendarId`-Quelle) |
| `events` | Termine lesen (`main` oder `archive&monat=YYYY-MM`) |
| `create_event` / `update_event` / `delete_event` | Termine anlegen / ändern (Voll-Update) / löschen |
| `tasks` / `create_task` / `update_task` / `complete_task` / `delete_task` | Aufgaben lesen / anlegen / ändern / abhaken / löschen |
| `workflows` … `reset_workflow` | Checklisten-Workflows (inkl. Einzelschritte) |

> Noch nicht als MCP-Tools umgesetzt: die Kalender-Verwaltung (anlegen,
> Rolle/Standard setzen, löschen) und Schreibzugriffe ohne Zielangabe —
> `create_event`/`create_task` verlangen die `calendarId` weiterhin (Quelle:
> `calendars`). Die passenden REST-Endpunkte (`/api/calendars*`) existieren
> bereits.

### Einbindung in OpenCode

```sh
cd mcp-server && bun install        # einmalig
opencode mcp add horizont --global \
  --env HORIZONT_URL=http://HOST:8917 \
  -- node /pfad/zu/horizont/mcp-server/index.mjs
```

Danach tauchen die Tools als `horizont_calendars`, `horizont_create_event` usw. auf.

**Token** — der Server liest in dieser Reihenfolge:
1. Umgebungsvariable `HORIZONT_TOKEN`
2. Datei `~/.config/horizont/token` (eine Zeile, `chmod 600`)

Token erzeugen: Horizont → **Einstellungen → „API-Token (für externe Zugriffe)“ → Erzeugen**
(einmalig im Klartext angezeigt). Bei Token-Ersetzung einfach die Datei neu befüllen.

`HORIZONT_TOKEN_FILE` kann den Dateipfad überschreiben; `HORIZONT_URL`
defaultet auf `http://localhost:8917`. Test: `bun run smoke` in `mcp-server/`
(läuft gegen eine Mock-API).

Daneben lässt sich die **Tasks-Benachrichtigung** (Webhook, Einstellungen)
koppeln: Horizont POSTet die offenen Aufgaben mit den gewählten **Kategorien**
(verwaltbar in den Einstellungen, Name + Farbe; gespeichert im CalDAV-Feld
`CATEGORIES`; Standard: „Schule") an eine frei wählbare Webhook-Adresse —
z. B. an einen Chat-Bot, einen Benachrichtigungsdienst oder einen
Assistenz-Server, der daraufhin über den MCP-Server Tasks abhaken oder
Termine anlegen kann.

Die **Automatisierung** ist konfigurierbar:

| Modus | Verhalten |
| --- | --- |
| Nur manuell | keine Automatik — Senden nur über den Button „Jetzt senden" (`POST /api/notify/send`) |
| Täglich | einmal täglich um die eingestellte Uhrzeit |
| Wöchentlich | einmal pro Woche am gewählten Wochentag um die eingestellte Uhrzeit |
| Alle N Stunden | alle 1–23 Stunden (Abstand ab dem letzten Versand) |

„Jetzt senden" funktioniert immer — unabhängig vom Modus — und verschickt
die aktuellen offenen Tasks mit derselben Nachrichtenkomposition wie der
automatische Job.

---

## CalDAV einrichten

1. Logge dich ein und öffne <`/einstellungen`>.
2. **CalDAV-Quelle anlegen**: URL + Benutzername + Passwort frei anlegbar,
   editierbar, löschbar (z. B. eigener iCloud- oder Nextcloud-Account).
   **Rolle** (Hauptverbindung = Workflows + Standardziele, sonst
   Zusatzverbindung) und **Anbieter-Vorlagen** (`/api/settings/presets`)
   sind über die API und in der Mac-/iPad-App wählbar/vorausgefüllt — die
   Web-UI bildet beides noch nicht ab.
3. **Verbindung testen** zeigt die gefundenen Kalender, **bevor** du speicherst.

> Passwörter bleiben gespeichert: ein leeres Passwort-Feld beim Speichern
> bedeutet „beibehalten", sofern bereits eines hinterlegt ist.

---

## Lokale Entwicklung

```bash
bun install        # dependencies
bun run dev        # Dev-Server (http://localhost:5173)
bun run check      # svelte-check (Typen + Lint)
bun run build      # produktiver Build nach ./build
```

- Daten werden lokal in `./data` abgelegt (überschreibbar via `DATA_DIR`).
- Für ein sauberes Testen: `rm -rf data` löscht Account, Workflows + Einstellungen.
- Ohne `data/users.json` ist `/setup` öffentlich (First-Run).

### Umgebungsvariablen

| Variable   | Default        | Bedeutung                          |
| ---------- | -------------- | ---------------------------------- |
| `DATA_DIR` | `./data`       | Verzeichnis für persistierte Daten |
| `PORT`     | `3000`         | Port des produktiven Servers       |
| `HOST`     | `0.0.0.0`      | Bind-Adresse                       |
| `TZ`       | (System)       | Timezone (Docker: `Europe/Berlin`) |

---

## API (Übersicht)

Alle Endpunkte liegen unter `/api` und sind serverseitig (Node-Adapter).
Die App ruft sie ausschließlich clientseitig auf. **Alle** Endpunkte
(außer Login/Setup und den statischen Anbieter-Vorlagen `/api/settings/presets`)
erfordern eine gültige Session oder einen gültigen
API-Token (`Authorization: Bearer`).

| Methode | Pfad                                      | Beschreibung                              |
| ------- | ----------------------------------------- | ----------------------------------------- |
| POST    | `/api/auth/login`                         | Login (Session-Cookie)                    |
| POST    | `/api/auth/logout`                        | Logout                                    |
| GET     | `/api/auth/me`                            | Aktuellen User                            |
| POST    | `/api/auth/setup`                         | First-Run: Benutzer anlegen (nur ohne User) |
| GET     | `/api/events?scope=main`                  | Panels (past/now/future) + Status        |
| GET     | `/api/events?scope=archive&page=N`        | Archiv-Seite (31 Tage) + Pagination       |
| POST    | `/api/events`                             | Termin anlegen (`calendarId` optional ⇒ Standardkalender) |
| PATCH   | `/api/events/[calendarId]/[uid]`          | Termin ändern                             |
| DELETE  | `/api/events/[calendarId]/[uid]`          | Termin löschen                            |
| GET     | `/api/tasks`                              | Aufgaben (VTODO)                          |
| POST    | `/api/tasks`                              | Aufgabe anlegen (`calendarId` optional ⇒ Standardkalender) |
| PATCH   | `/api/tasks/[calendarId]/[uid]`           | Aufgabe ändern                            |
| DELETE  | `/api/tasks/[calendarId]/[uid]`           | Aufgabe löschen                           |
| GET     | `/api/calendars`                          | Kalenderübersicht aller Verbindungen (`?sichtbar=1` nur sichtbare) |
| POST    | `/api/calendars`                          | Kalender anlegen (`MKCALENDAR`; Body: `connectionId`, `name`, `color`) |
| PATCH   | `/api/calendars/[id]`                     | Kalender: Name/Farbe/Sichtbarkeit/Schreibschutz/Standard |
| DELETE  | `/api/calendars/[id]`                     | Kalender löschen (Body `{name}` muss exakt passen; sonst 403) |
| GET     | `/api/settings`                           | Verbindungen (ohne PW) + `primaryId` + Anbieter-Vorlagen |
| GET     | `/api/settings/presets`                   | Anbieter-Vorlagen (ohne Session)          |
| POST    | `/api/settings`                           | Verbindung anlegen/ändern (`provider`, `role`; `role:'primary'` = Hauptverbindung setzen) |
| PATCH   | `/api/settings`                           | Verbindung ändern (gleiche Felder wie POST) |
| DELETE  | `/api/settings`                           | Verbindung löschen (Body `{id}`)          |
| POST    | `/api/settings/test`                      | Verbindung testen                         |
| GET     | `/api/workflows`                          | alle Workflows                            |
| POST    | `/api/workflows`                          | Workflow anlegen                          |
| GET     | `/api/workflows/:id`                      | Workflow laden                            |
| PATCH   | `/api/workflows/:id`                      | Titel/Notizen ändern                      |
| DELETE  | `/api/workflows/:id`                      | Workflow löschen                          |
| POST    | `/api/workflows/:id/steps`                | Schritt anfügen                           |
| PATCH   | `/api/workflows/:id/steps/:sid`           | Schritt (done/title) ändern              |
| DELETE  | `/api/workflows/:id/steps/:sid`           | Schritt löschen                           |
| POST    | `/api/workflows/:id/reset`                | Workflow zurücksetzen                     |

---

## Projektstruktur (Auszug)

```
src/
  lib/
    api.ts                 # clientseitiger API-Wrapper
    types.ts               # geteilte Typen
    dates.ts, theme.ts     # isomorphe Helfer
    components/            # App-Komponenten (TimePanel, DayBlock, WorkflowCard, …)
  server/
    auth/                  # userStore (scrypt), sessionStore (in-memory), apiHelpers
    caldav/                # CalDAV-Client (multi-Connection) + iCal-Parsing
    store/
      connections.ts       # CalDAV-Verbindungen + Legacy-Migration
      store.ts, workflowStore.ts
    lib/                   # Konstanten + Panel-Logik
  hooks.server.ts          # zentrales Auth-Gate
  routes/
    +layout.svelte         # Layout, Navigation (auth-aware), Theme
    +page.svelte           # Hauptansicht
    archiv/+page.svelte    # Archiv (paginiert)
    einstellungen/+page.svelte   # CalDAV-Verbindungen
    fokus/[id]/+page.svelte
    login/+page.svelte
    setup/+page.svelte     # First-Run
    api/                   # alle Endpunkte
```

---

## Datenschutz

- Es wird **nicht** mit einer eigenen Cloud kommuniziert: nur mit deinen
  CalDAV-Servern und lokal.
- Benutzer- und Verbindungsdaten liegen ausschließlich in `DATA_DIR`.
- Keine Analytics, keine Tracking-Pixel, keine externen Fonts zur Laufzeit
  (Inter wird lokal via `@fontsource-variable/inter` gebündelt).

## Lizenz

MIT
