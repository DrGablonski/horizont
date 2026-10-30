# Horizont

Minimalistischer, **multi-user-fähiger**, selbst hostbarer Kalender mit drei
zusammenklappbaren Zeiträumen — **Vergangenheit**, **Jetzt** und **Zukunft** —
plus einem **Workflow/Fokus-Modus** für sequenzielle Aufgabenlisten. Deine
Termine kommen aus **CalDAV**-Backends (Radicale, Baïkal, iCal, Nextcloud, …).
Jeder User hat eine eigene Datenwelt: eine ihm **zugewiesene** CalDAV-Verbindung
(wird vom Admin angelegt, inkl. automatischem CalDAV-Account über den
`caldav-admin`-Sidecar) und beliebig viele **externe** Verbindungen (z. B.
eigene iCloud/Nextcloud-Accounts).

---

## Funktionen

- **Multi-User-Auth**
  - Login/Logout mit Session-Cookie (in-memory — bei Neustart alle Sessions
    beendet), scrypt-gehashte Passwörter.
  - **Erstes-Setup**: solange kein User existiert, ist `/setup` öffentlich und
    legt den Admin an (übernimmt dabei die alte Einzel-User-Konfiguration).
  - **Admin-Bereich** (`/admin`, nur für Admins):
    - User anlegen/löschen/deaktivieren, Rollen verwalten (letzter aktiver
      Admin ist geschützt).
    - Beim User-Anlegen wird **automatisch** ein CalDAV-Account auf dem
      konfigurierten Radicale-Server angelegt (via `caldav-admin`-Sidecar);
      die CalDAV-Zugangsdaten werden **einmalig** zum Übergeben angezeigt.
    - User-Löschung kaskadiert: CalDAV-Account + Collections + alle
      Userdaten.
    - System-CALDAV-Konfiguration (Basis-URL, Admin-API-URL, Admin-Token) mit
      Verbindungstest.
- **Drei Zeiträume, eine Ansicht**
  - *Vergangenheit*: die letzten 14 Tage
  - *Jetzt*: heute + 2 Tage (Heute, Morgen, Übermorgen)
  - *Zukunft*: die nächsten 30 Tage
  - Jeder Abschnitt ist zusammenklappbar und zeigt Tage + Termine.
- **Archiv**: alle Einträge älter als zwei Wochen (bis zu 365 Tage zurück) als
  Monatsgrid (Mo–So, wie Apple/Google Calendar); Tap auf einen Tag zeigt die
  Tagesdetails, per `?monat=YYYY-MM` ist der Monat teilbar.
- **Workflows**: benutzerdefinierte, sequenzielle Aufgaben-Checklisten.
  - Fortschrittsanzeige, Aktiver-Schritt-Betonung, „Als Nächstes"-Vorschau.
  - **Fokus-Modus** (`/fokus/<id>`): ablenkungsfreie Vollansicht mit nur dem
    aktuellen Schritt.
  - Schrittemitfortschritt wird sofort gespeichert.
- **CalDAV-Anbindung pro User**: eine zugewiesene (nur URL änderbar, vom Admin)
  und beliebige externe Verbindungen (vollständig editierbar/löschbar),
  Verbindungstest mit Kalender-Liste, farbcodierte Kalender.
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
- [caldav-admin](#caldav-admin-sidecar) (Python 3, Standardlib + passlib) als
  Sidecar auf dem Radicale-Host

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
  kein User existiert) und legt den Admin an. Bestehende Daten aus einer
  Einzel-User-Installation (`data/settings.json`) werden automatisch als
  zugewiesene Verbindung des Admins übernommen; die Datei wird zu
  `settings.json.legacy` archiviert.
- Port ändern: in [`docker-compose.yml`](docker-compose.yml) unter `ports`
  (z. B. `"8080:3000"`).
- Alle Daten werden im Volume `horizont-data` unter `/app/data` persistiert:
  `users.json` (Accounts), `users/<id>/` (Verbindungen, Workflows),
  `system/caldav.json` (System-CALDAV-Konfiguration).
- Zum Löschen: `docker compose down -v`.

> **Proxmox:** am einfachsten über eine Container-Template-VM mit Docker oder ein
> LXC-Container mit Docker installiert. Dann exakt die drei Befehle von oben.

---

## Auth-Konzept

| Aspect           | Umsetzung                                                        |
| ---------------- | ---------------------------------------------------------------- |
| Passwort-Hashing | scrypt (N=16384, r=8, p=1), 16-Byte-Salt, 64-Byte-Key            |
| Sessions         | in-memory (Prozess), 12 h TTL, httpOnly/sameSite=lax-Cookie      |
| API-Token        | per User, scrypt-gehasht (`DATA_DIR/users/<id>/api-token.json`), `Authorization: Bearer <token>` auf `/api/*` |
| Autorisierung    | `src/hooks.server.ts`: `/api/*` → 401, Seiten → Redirect, `/admin*` → 403/Redirect für Nicht-Admins |
| User-Store       | `DATA_DIR/users.json` (nur bei Bedarf im Prozess, kein DB)       |
| Userdaten        | `DATA_DIR/users/<id>/` (Verbindungen, Workflows, API-Token) — bei Löschung komplett entfernt |

Der letzte aktive Admin kann nicht gelöscht, deaktiviert oder herabgestuft werden.

---

## API für externe Tools (z. B. T3 Code)

Jeder User kann in den **Einstellungen → „API-Token (für T3 Code & Co.)“** einen
persönlichen Token erzeugen. Der Token wird einmalig im Klartext angezeigt und
serverseitig nur scrypt-gehasht gespeichert (SHA-256-Digest als Lookup-Key).
Er gilt für **alle** `/api/*`-Endpunkte und ist per User isoliert — er gibt
Zugriff auf genau die Datenwelt dieses Users (eigene CalDAV-Verbindungen,
Workflows). Ablehnen/Ersetzen jederzeit in derselben Sektion; bei
User-Löschung fällt der Token automatisch weg.

Aufruf:

```bash
curl -H "Authorization: Bearer <token>" http://HOST/api/tasks
```

**Wichtigste Endpunkte** (Vollständiges Verzeichnis: [`/api/openapi.json`](src/routes/api/openapi.json/+server.ts)):

| Endpunkt | Methode | Wirkung |
| --- | --- | --- |
| `/api/calendars` | GET | Alle Kalender des Users (für `calendarId`) |
| `/api/events` | GET | Termine — `?scope=main` (Vergangenheit/Jetzt/Zukunft) oder `?scope=archive&monat=YYYY-MM` |
| `/api/events` | POST | Termin anlegen (`{calendarId, summary, allDay, dayKey/startMs, …}`) |
| `/api/events/{calendarId}/{uid}` | PATCH | Termin bearbeiten (vollständiges Update) |
| `/api/events/{calendarId}/{uid}` | DELETE | Termin löschen |
| `/api/tasks` | GET / POST | Tasks auflisten / anlegen |
| `/api/tasks/{calendarId}/{uid}` | PATCH | Task bearbeiten, z. B. `{"completed": true}` abhaken |
| `/api/tasks/{calendarId}/{uid}` | DELETE | Task löschen |
| `/api/workflows…` | GET/POST/PATCH/DELETE | Workflows (Checklisten) inkl. Schritte |

Beispiel: „Mathe-Klausur am 10.11. vormittags“ anlegen:

```bash
curl -X POST -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"calendarId":"<id>","summary":"Mathe-Klausur","allDay":false,"startMs":1794219000000,"endMs":1794226200000}' \
  http://HOST/api/events
```

So lässt sich z. B. die **Tägliche-Schul-Tasks-Benachrichtigung** (Webhook)
mit T3 Code koppeln: Horizont POSTet um 15:00 die offenen Schul-Tasks an T3,
und T3 kann daraufhin über diese API Tasks abhaken oder Termine anlegen.

---

## System-CALDAV + caldav-admin-Sidecar

Radicale hat keine Admin-API. Der **`caldav-admin`**-Sidecar (Python 3, nur
Standardlib + `passlib`/`bcrypt`) läuft **auf dem Radicale-Host** und verwaltet:

- `/etc/radicale/users` — htpasswd-Datei (bcrypt, von Radicale per
  `htpasswd_encryption = autodetect` gelesen)
- `/var/lib/radicale/collections/<login>/` — Collection-Verzeichnis pro User

### Endpunkte (Token via `X-Admin-Token`)

| Methode | Pfad               | Wirkung                                  |
| ------- | ------------------ | ---------------------------------------- |
| GET     | `/health`          | `{"ok": true}` (Token-Check)             |
| GET     | `/api/v1/users`    | User-Liste                               |
| POST    | `/api/v1/users`    | User anlegen (Body: `login`, `password`) |
| DELETE  | `/api/v1/users/{login}` | User + Collections entfernen      |

### Einrichtung auf dem Radicale-Host (Beispiel: Debian)

```bash
# 1) Dependencies (passlib + bcrypt) — auf Debian:
apt install -y python3-passlib python3-bcrypt   # oder via pip

# 2) Verzeichnisse + Token:
mkdir -p /opt/caldav-admin /etc/caldav-admin
umask 077
printf 'ADMIN_TOKEN=%s\n' "$(openssl rand -hex 32)" > /etc/caldav-admin/admin.env
chmod 600 /etc/caldav-admin/admin.env

# 3) Server (aus diesem Repo):
cp caldav-admin/server.py /opt/caldav-admin/server.py
chmod 755 /opt/caldav-admin/server.py

# 4) systemd:
cat > /etc/systemd/system/caldav-admin.service <<'EOF'
[Unit]
Description=caldav-admin - Admin-API für Radicale-htpasswd-User
After=network.target radicale.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/caldav-admin/server.py
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now caldav-admin
```

Das Service läuft als `root`, weil es sowohl die htpasswd-Datei
(`root:radicale`, 640) als auch das Collections-Verzeichnis (`radicale:radicale`,
750) schreiben muss; der Port ist nur mit gültigem Admin-Token nutzbar.

### Verdrahtung in Horizont

In **Admin → System-CALDAV** konfiguriertest du:

1. **Basis-URL** des CalDAV-Servers (z. B. `http://<host>:5232`)
2. **Admin-API-URL** des Sidecars (z. B. `http://<host>:5233`)
3. **Admin-Token** (identisch zu `ADMIN_TOKEN` in `/etc/caldav-admin/admin.env`)
4. **Testen** prüft Erreichbarkeit + Token.

Danach bekommt jeder neu angelegte User automatisch einen CalDAV-Account mit
**zufälligem Passwort** (einmalig in der Admin-UI angezeigt) und eine
entsprechende zugewiesene Verbindung.

> **Wichtig:** Der Admin-Token ist ein Geheimnis. Er liegt im App-Data-Verzeichnis
> (`system/caldav.json`) und darf nicht ins Backup-/Git-Leak wandern.

---

## CalDAV einrichten (pro User)

1. Logge dich ein und öffne <`/einstellungen`>.
2. **Zugewiesene Verbindung** (falls vorhanden): URL ist editierbar,
   Zugangsdaten zeigt der Admin; **nicht** löschbar.
3. **Externe Verbindungen**: URL + Benutzername + Passwort frei anlegbar,
   editierbar, löschbar (z. B. eigener iCloud- oder Nextcloud-Account).
4. **Verbindung testen** zeigt die gefundenen Kalender, **bevor** du speicherst.

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
- Für ein sauberes Testen: `rm -rf data` löscht Users, Workflows + Einstellungen.
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
(außer Login/Setup) erfordern eine gültige Session; `/api/admin/*` zusätzlich
die Admin-Rolle.

| Methode | Pfad                                      | Beschreibung                              |
| ------- | ----------------------------------------- | ----------------------------------------- |
| POST    | `/api/auth/login`                         | Login (Session-Cookie)                    |
| POST    | `/api/auth/logout`                        | Logout                                    |
| GET     | `/api/auth/me`                            | Aktuellen User                            |
| POST    | `/api/auth/setup`                         | First-Run: Admin anlegen (nur ohne Users) |
| GET     | `/api/events?scope=main`                  | Panels (past/now/future) + Status        |
| GET     | `/api/events?scope=archive&page=N`        | Archiv-Seite (31 Tage) + Pagination       |
| GET     | `/api/events?scope=calendars`             | Kalender-Liste (alle Verbindungen)        |
| POST    | `/api/events`                             | Termin anlegen                            |
| PATCH   | `/api/events/[calendarId]/[uid]`          | Termin ändern                             |
| DELETE  | `/api/events/[calendarId]/[uid]`          | Termin löschen                            |
| GET     | `/api/tasks`                              | Aufgaben (VTODO)                          |
| POST    | `/api/tasks`                              | Aufgabe anlegen                           |
| PATCH   | `/api/tasks/[calendarId]/[uid]`           | Aufgabe ändern                            |
| DELETE  | `/api/tasks/[calendarId]/[uid]`           | Aufgabe löschen                           |
| GET     | `/api/calendars`                          | Verbindungs- + Kalender-Übersicht         |
| GET     | `/api/settings`                           | Verbindungen (ohne PW)                    |
| POST    | `/api/settings`                           | Externe Verbindung anlegen/ändern         |
| DELETE  | `/api/settings/[id]`                      | Externe Verbindung löschen                |
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
| GET     | `/api/admin/users`                        | User-Liste + System-CALDAV-Status        |
| POST    | `/api/admin/users`                        | User anlegen (+ CalDAV via Sidecar)      |
| PATCH   | `/api/admin/users/:id`                    | Rolle/Status/Passwort/Verbindung ändern   |
| DELETE  | `/api/admin/users/:id`                    | User löschen (Kaskade)                   |
| GET     | `/api/admin/caldav`                       | System-CALDAV-Konfiguration (ohne PW)    |
| POST    | `/api/admin/caldav`                       | System-CALDAV-Konfiguration speichern     |
| POST    | `/api/admin/caldav/test`                  | Sidecar-Erreichbarkeit + Token prüfen     |

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
    admin/
      caldavAdmin.ts       # Client für den caldav-admin-Sidecar
    caldav/                # CalDAV-Client (multi-Connection) + iCal-Parsing
    store/
      connections.ts       # pro-User-Verbindungen (assigned/external) + Legacy-Migration
      system.ts            # System-CALDAV-Konfiguration (DATA_DIR/system/)
      store.ts, workflowStore.ts
    lib/                   # Konstanten + Panel-Logik
  hooks.server.ts          # zentrales Auth-Gate
  routes/
    +layout.svelte         # Layout, Navigation (auth-aware), Theme
    +page.svelte           # Hauptansicht
    archiv/+page.svelte    # Archiv (paginiert)
    einstellungen/+page.svelte   # Connections (assigned + external)
    fokus/[id]/+page.svelte
    login/+page.svelte
    setup/+page.svelte     # First-Run
    admin/+page.svelte     # User-Verwaltung + System-CALDAV
    api/                   # alle Endpunkte
caldav-admin/
  server.py                # caldav-admin-Sidecar (für den Radicale-Host)
```

---

## Datenschutz

- Es wird **nicht** mit einer eigenen Cloud kommuniziert: nur mit deinen
  CalDAV-Servern und lokal.
- User- und Verbindungsdaten liegen ausschließlich in `DATA_DIR`.
- Keine Analytics, keine Tracking-Pixel, keine externen Fonts zur Laufzeit
  (Inter wird lokal via `@fontsource-variable/inter` gebündelt).
- Der Admin-Token des caldav-admin-Sidecars ist ein Geheimnis und gehört nicht
  in Backups, die andere Nutzer lesen können.

## Lizenz

MIT
