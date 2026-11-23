# Forgejo Actions: Warum die CI „waiting“ blieb – und wie sie jetzt läuft

## Diagnose (2026-11, behoben)

Die Instanz `git.home.gho.mom` ist **Forgejo 15.0.10** auf CT100 (DockerMain).
Drei Dinge waren im Argen:

1. **Falsches Verzeichnis:** Forgejo erwartet Workflows in `.forgejo/workflows/`.
   Läufe aus `.gitea/workflows/` wurden angelegt, aber die Job-Erzeugung las
   das hartkodierte `.forgejo/workflows` → Läufe ohne Jobs (in 15.0.10 teils
   noch wirksam). `ci.yml` liegt jetzt unter `.forgejo/workflows/`.
2. **Kein Runner:** Kein einziges Repository der Instanz hatte je einen
   Actions-Job ausgeführt – es meldete sich nirgends ein Runner, die Jobs
   blieben dauerhaft `waiting`. (Bestätigt über `action_runner` in der
   Forgejo-SQLite: 0 Zeilen.)
3. **Job-Container ohne DNS für die eigene Domain:** Die von act gestarteten
   Job-Container lösten `git.home.gho.mom` nicht auf (Docker-Fallback-DNS
   8.8.8.8, Domain nur intern per AdGuard-Rewrite) → Checkout-Fehler
   `getaddrinfo ENOTFOUND`.

## Was eingerichtet ist (Stand 23.11.2026)

* **Stack `/opt/stacks/forgejo-runner`** (Dockge-kompatibel, Compose im Repo
  unter `docs/forgejo-runner/compose.yaml`): Runner v13 auf
  `code.forgejo.org/forgejo/runner:13`, registriert als **globaler
  Instanz-Runner** `horizont-host-runner` mit den Labels `ubuntu-latest` und
  `docker` (Basis `alpine:3.20`). Registrierung liegt persistent in
  `./config`, der Container startet nach Neustarts nur den Daemon.
* **`/etc/docker/daemon.json`:** `{"dns": ["192.168.1.102", "8.8.8.8"]}` –
  alle Docker-Container (auch die Job-Container) lösen damit `*.home.gho.mom`
  über AdGuard auf. (War vorher auch Brain-To-do Nr. 8 für CT100.)
* Der Runner mountet `/var/run/docker.sock` – Job-Container laufen auf dem
  Docker-Daemon des Hosts.

## Runner-Token neu erzeugen (falls je nötig)

UI/API gibt in 15.0.10 keinen Runner-Bereich her; der Weg ist der CLI-Wrapper
im Forgejo-Container (zwingend **nicht root**, sonst bricht der CLI ab):

```bash
ssh root@192.168.1.104
docker exec -u git forgejo forgejo actions generate-runner-token \
  -c /data/gitea/conf/app.ini > /tmp/tok.out
# Token = einzige Zeile in /tmp/tok.out → in /opt/stacks/forgejo-runner/.env
# als FORGEJO_RUNNER_REGISTRATION_TOKEN=… schreiben, dann:
cd /opt/stacks/forgejo-runner && docker compose up -d --force-recreate
```

Wichtig: `docker restart` liest die `.env` **nicht** neu, immer
`up -d --force-recreate`. Die Registrierung überspringt sich selbst, solange
`config/.runner` existiert. Der Runner-CLI braucht `--no-interactive`,
sonst hängt er in einem Prompt (fatal EOF).

## Hinweise

* `ci.yml` nutzt `runs-on: docker`; `ubuntu-latest` funktioniert ebenfalls.
* **Tests laufen mit `bun test`, nicht Vitest:** Vitest erwischt im CI der
  Bun-Runtime (oven/bun-Image) und stirbt an `child.channel?.unref`
  (Bun fehlen die Node-Child-Process-Kanäle). `bun test` deckt die gleiche
  API ab (describe/it/expect + `bun:test`-Import, Typen über `@types/bun`).
* Job-Container (`oven/bun:1`) ziehen beim ersten Lauf ~100 MB; danach cached.
* Mit dem globalen Runner haben **alle** Repos der Instanz CI – sie brauchen
  nur je eine Datei unter `.forgejo/workflows/`.
* **Sicherheit:** Jobs führen Repo-Code in Containern auf dem Docker-Daemon
  des Hosts aus (socket-Mount ≈ root auf dem Host). Bei zukünftigen
  Fremd-Repos mit Fork-PRs ggf. Runner auslagern.

## Verifikation

```bash
# Runner online?
docker exec forgejo sqlite3 /data/gitea/gitea.db "select name,agent_labels from action_runner;"
# Job-Logs (zstd): /opt/stacks/forgejo/forgejo/gitea/actions_log/Gabriel/horizont/NN/NN.log.zst
#   entpacken:  cat NN.log.zst | zstd -dqc     (z.B. vom Mac über ssh cat)
```
