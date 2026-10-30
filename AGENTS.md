# AGENTS.md — Hinweise für AI-Agents (OpenCode, T3 Code, …)

Dieses Repo ist die selbst gehostete Kalender-/Task-App **Horizont**.
Diese Datei dient als ständiger Kontext — keine Project-Beschreibung
pro Konversation mehr nötig.

## Projekt & Tech-Stack

- SvelteKit + Svelte 5 (Runes), adapter-node, Bun
- **Alle User-facing Texte (UI, Fehler, Toasts, API-Meldungen) auf Deutsch**
- Self-Hosting via Docker/Dockge, Container-Port 3000 → Host-Port 8917

## Codebase-Konventionen

- Server-Code: `src/server/`, Alias `$server/...` (niemals im Client-Bundle)
- Client/Logik: `src/lib/`, Alias `$lib/...`; gemeinsame Types: `src/lib/types.ts`
- Auth:
  - Browser: Session-Cookie (in-memory, 12 h) — `src/server/auth/sessionStore.ts`
  - Maschinen: Pro-User-API-Token (`hz_…`, scrypt-Hash + SHA-256-Digest-Lookup),
    Bearer auf `/api/*` — `src/server/auth/apiToken.ts`, Gate in `src/hooks.server.ts`
- Daten: JSON-Dateien unter `DATA_DIR` (Container: `/app/data`, Volume):
  `users.json`, `users/<id>/…`, `system/…`. Schreibzugriffe atomar (tmp + rename).
- Passwörter: **scrypt** (Hash-Scheme nicht austauschen, bestehende Hashes sind danach)
- API-Fehler: JSON `{"error": "<deutsche Meldung>"}`
- Admin-Routen prüfen IMMER `locals.user?.role !== 'admin'` (403)
- T3 Code (externer Agent) nutzt den API-Token; öffentliche Spezifikation:
  `GET /api/openapi.json` (bewusst ohne Auth)
- Täglicher Webhook-Job (Schul-Tasks an T3): `src/server/jobs/notify.ts`

## Server & Deployment (LESEN vor jedem Deploy!)

- Server: **192.168.1.104** (Hostname `DockerMain`), Docker-Host, Homelab
- Repo auf dem Server: `/root/horizont` (Gitea: `http://192.168.1.104:3000/Gabriel/horizont.git`)
- Dockge: Stack-Symlink `/opt/stacks/horizont -> /root/horizont`, Compose-Projekt `horizont`
- Deploy-Ablauf:
  ```bash
  cd /root/horizont
  git pull --ff-only
  docker build -t horizont .
  docker compose up -d
  ```
  (Das ist exakt das, was Dockge bei „Deploy“ macht — per CLI ist kein
  Dockge-Klick nötig.)
- ⚠️ **DATEN-VOLUME NICHT ANFASSEN:** `horizont_horizont-data` ist ein externes
  Named Volume, im `docker-compose.yml` hart per `name:` + `external: true`
  referenziert. Weder Volume-Name noch Compose-Projekt-Name ändern — ein
  neues/anderes Volume ersetzt die Live-Daten durch ein leeres
  (Incident 2026-10-08: genau das passiert ist).
- Vor dem Deploy: Daten-Backup
  `tar czf /root/hz-backups/horizont-data-$(date +%Y%m%d-%H%M).tar.gz -C /var/lib/docker/volumes/horizont_horizont-data _data`
  und Rollback-Tag des laufenden Images: `docker tag <aktuelle-ImageID> horizont-rollback-<Datum>`
- Rollback: `docker tag horizont-rollback-<Datum> horizont && docker compose up -d`
- Nach dem Deploy verifizieren: Container läuft, `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8917/login` → 200,
  `users.json`-MD5 im Volume unverändert, Logs sauber.

## SSH-Zugriff auf den Server

- Das SSH-Passwort **nie** in den Chat abfragen oder dort stehen lassen.
  T3 Code: `request_secret` (private Card, `delivery: "file"`) + `sshpass -f`,
  danach die Temp-Datei sicher löschen (`shred -u`).
- Öffentlicher Key des T3-Hosts (wenn freigegeben, genügt `ssh root@192.168.1.104`):
  in `~/.ssh/id_ed25519.pub` auf dem T3-Host.

## Security-Regeln (stehen schon im Code — nicht rückentwickeln!)

1. **Keine echten IPs/Hostnamen** in Placeholdern, Kommentaren oder irgendwas,
   das an Clients ausgeliefert wird. Die Setup-Seite (`/setup`) ist öffentlich,
   solange kein User existiert; JS-Bundles sind für jeden abrufbar.
   Generische Platzhalter: `http://RADICALE:5232`, `http://T3-CODE-HOST:PORT/…`
2. **SSRF-Schutz** für alle serverseitigen Fetches (CalDAV, Webhook):
   `src/server/lib/urlGuard.ts` (`assertSafeUrl`/`guardedFetch`).
   Blockiert: nicht-http(s), Loopback, `0.x`, Link-Local/Cloud-Metadaten
   (inkl. IPv6-Varianten), DNS-Auflösung wird geprüft, jede Redirect-Hop
   ebenfalls. Private LAN-Bereiche sind **bewusst erlaubt** (Self-Hosting).
   Neue serverseitige Fetches immer über `guardedFetch` routen.
3. Rate-Limit-Key = **letzter** `X-Forwarded-For`-Wert (Proxy-gesetzt),
   nie der erste (Client-fälschbar) — `src/server/auth/apiHelpers.ts`.
4. Body-Limits: global 1 MiB (413) im `hooks.server.ts`, Login/Setup
   streamend 64 KB (Drain bis 8 MB) — nicht entfernen.
5. Keine `@html`/Roh-HTML-Rendering; keine hartkodierten Secrets im Repo.
6. `data/` bleibt in `.gitignore` und `.dockerignore`.

## Verifikation (vor Commit)

```bash
bun run check    # svelte-check: 0 errors
bun run build    # vite/adapter-node build
```

Optional Smoke-Test gegen den Production-Build:
`DATA_DIR=/tmp/opencode/hz-test PORT=3999 node build/index.js`
(Setup via `POST /api/auth/setup`, dann Endpunkte mit Bearer-Token prüfen;
danach Temp-`DATA_DIR` löschen.)
