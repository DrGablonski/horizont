# Horizont

Minimalistischer, selbst hostbarer Kalender mit drei zusammenklappbaren Zeiträumen —
**Vergangenheit**, **Jetzt** und **Zukunft** — plus einem **Workflow/Fokus-Modus** für
sequenzielle Aufgabenlisten. Deine Termine kommen aus einem **CalDAV**-Backend
(Radicale, Baïkal, iCal, Nextcloud, …). Der CalDAV-Server ist die einzige externe
Abhängigkeit; alle Workflows und Einstellungen werden lokal im Datenverzeichnis
persistiert.

---

## Funktionen

- **Drei Zeiträume, eine Ansicht**
  - *Vergangenheit*: die letzten 14 Tage
  - *Jetzt*: heute + 2 Tage (Heute, Morgen, Übermorgen)
  - *Zukunft*: die nächsten 30 Tage
  - Jeder Abschnitt ist zusammenklappbar und zeigt Tage + Termine.
- **Archiv**: alle Einträge älter als zwei Wochen (bis zu 365 Tage zurück),
  chronologisch mit Pagination (31 Tage pro Seite).
- **Workflows**: benutzerdefinierte, sequenzielle Aufgaben-Checklisten.
  - Fortschrittsanzeige, Aktiver-Schritt-Betonung, „Als Nächstes"-Vorschau.
  - **Fokus-Modus** (`/fokus/<id>`): ablenkungsfreie Vollansicht mit nur dem
    aktuellen Schritt.
  - Schrittemitfortschritt wird sofort gespeichert.
- **CalDAV-Anbindung**: eigene URL + Zugangsdaten, Verbindungstest mit
  Kalender-Liste, farbcodierte Kalender.
- **Dunkel-/Hellmodus** (klassenbasiert, folgt dem System) und dezent, ruhiges UI
  auf Basis von shadcn-svelte + Tailwind.

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

Die App läuft danach unter <http://localhost:3000>.

- Port ändern: in [`docker-compose.yml`](docker-compose.yml) unter `ports`
  (z. B. `"8080:3000"`).
- Alle Daten (Workflows + CalDAV-Einstellungen) werden im Volume
  `horizont-data` unter `/app/data` persistiert und überleben Neustarts.
- Zum Löschen: `docker compose down -v`.

> **Proxmox:** am einfachsten über eine Container-Template-VM mit Docker oder ein
> LXC-Container mit Docker installiert. Dann exakt die drei Befehle von oben.

---

## CalDAV einrichten

1. Öffne <http://localhost:3000/einstellungen>.
2. Trage die **CalDAV-URL**, den **Benutzernamen** und das **Passwort** ein.
   - Die URL muss einen CalDAV-Discovery-/Kalender-Endpunkt sein
     (PROPFIND/REPORT). Das trailing `/` ist optional.
   - Beispiel Radicale: `http://<host>:5232/<benutzer>/`
   - Beispiel Nextcloud: `https://<cloud>/remote/dav/<benutzer>/calendars/`
3. **Verbindung testen** zeigt dir, welche Kalender gefunden werden, **bevor**
   du speicherst.
4. **Speichern**. Das Hauptfenster lädt nun die Termine.

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
- Für ein sauberes Testen: `rm -rf data` löscht Workflows + Einstellungen.

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
Die App ruft sie ausschließlich clientseitig auf.

| Methode | Pfad                                  | Beschreibung                          |
| ------- | ------------------------------------- | ------------------------------------- |
| GET     | `/api/events?scope=main`              | Panels (past/now/future) + Status    |
| GET     | `/api/events?scope=archive&page=N`    | Archiv-Seite (31 Tage) + Pagination   |
| GET     | `/api/settings`                       | aktuelle Einstellungen (ohne PW)      |
| POST    | `/api/settings`                       | Einstellungen speichern               |
| POST    | `/api/settings/test`                  | Verbindung testen (optional mit PW)   |
| GET     | `/api/workflows`                      | alle Workflows                        |
| POST    | `/api/workflows`                      | Workflow anlegen                      |
| GET     | `/api/workflows/:id`                  | Workflow laden                        |
| PATCH   | `/api/workflows/:id`                  | Titel/Notizen ändern                  |
| DELETE  | `/api/workflows/:id`                  | Workflow löschen                      |
| POST    | `/api/workflows/:id/steps`            | Schritt anfügen                       |
| PATCH   | `/api/workflows/:id/steps/:sid`       | Schritt (done/title) ändern          |
| DELETE  | `/api/workflows/:id/steps/:sid`       | Schritt löschen                       |
| POST    | `/api/workflows/:id/reset`            | Workflow zurücksetzen                 |

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
    caldav/                # CalDAV-Client + iCal-Parsing
    store/                 # JSON-Persistenz (Workflows + Einstellungen)
    lib/                   # Konstanten + Panel-Logik
  routes/
    +layout.svelte         # Layout, Navigation, Theme
    +page.svelte           # Hauptansicht
    archiv/+page.svelte    # Archiv (paginiert)
    einstellungen/+page.svelte
    fokus/[id]/+page.svelte
    api/                   # alle Endpunkte
```

---

## Datenschutz

- Es wird **nicht** mit einer eigenen Cloud kommuniziert: nur mit deinem
  CalDAV-Server und lokal.
- Workflows und Einstellungen liegen ausschließlich in `DATA_DIR`.
- Keine Analytics, keine Tracking-Pixel, keine externen Fonts zur Laufzeit
  (Inter wird lokal via `@fontsource-variable/inter` gebündelt).

## Lizenz

MIT
