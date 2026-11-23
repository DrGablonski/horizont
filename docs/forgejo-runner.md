# Forgejo Actions: Warum die CI „waiting“ blieb – und wie ein Runner sie zum Laufen bringt

## Diagnose (2026-11)

Die Instanz `git.home.gho.mom` ist **Forgejo 15.0.10** (Gitea-Fork). Zwei Dinge waren im Argen:

1. **Falsches Verzeichnis (behoben):** Forgejo erwartet Workflows in
   `.forgejo/workflows/`. Läufe aus `.gitea/workflows/` werden zwar angelegt,
   aber die Job-Erzeugung liest das hartkodierte `.forgejo/workflows`
   (upstream gefixt, in 15.0.10 teils noch wirksam) → Läufe hingen ohne Jobs
   fest. Deshalb liegt `ci.yml` jetzt unter `.forgejo/workflows/`.
2. **Kein Runner (offen):** Kein einziges Repository der Instanz hatte je
   einen abgeschlossenen Actions-Lauf. Forgejo erzeugt Runs und Jobs
   korrekt – aber es meldet sich **kein Runner**, der die Jobs abholt. Solange
   das so ist, bleibt jeder Lauf dauerhaft auf `waiting` stehen.

## Runner einrichten (einmalig)

Am sinnvollsten als **Instanz-Runner** – dann haben alle Repos CI.

### 1. Registrierungstoken holen

Ohne Instanz-Admin-Rechte reicht die **Benutzer-Ebene** – die deckt alle Repos
von Gabriel ab: **`https://git.home.gho.mom/user/settings/actions/runners` →
„Neuen Runner anlegen“**. (Alternativen: `/admin/actions/runners` für die ganze
Instanz, oder nur dieses Repo unter `Gabriel/horizont/settings/actions/runners`.)
Das Token ist einmalig gültig – sofort im nächsten Schritt verwenden.

### 2. Runner-Stack starten (Dockge, wie die anderen Stacks)

Diesen Ordner (`horizont/docs/forgejo-runner/` mit der `docker-compose.yml`)
nach `/opt/stacks/forgejo-runner` kopieren und in Dockge als Stack öffnen.
Das Token in `.env` eintragen:

```bash
FORGEJO_RUNNER_REGISTRATION_TOKEN=<token>
```

Der Container registriert sich beim ersten Start selbst (Labels
`ubuntu-latest` **und** `docker`, Basis `alpine:3.20`) und startet danach als
Daemon. Die Registrierung liegt im Volume `./config` – einmal registriert,
übersteht er Neustarts und Updates.

### 3. Verifizieren

* `https://git.home.gho.mom/user/settings/actions/runners`: Runner
  „horizont-host-runner“ als online gelistet.
* Der zuletzt wartende CI-Lauf von horizont wird aufschnappt (oder beliebigen
  PR öffnen / pushen). Läuft nicht an: `docker logs forgejo-runner` – meist
  hilft, `network_mode: host` zu setzen (siehe Kommentar in der Compose).

## Hinweise

* `ci.yml` nutzt `runs-on: docker`. Der Runner registriert zusätzlich
  `ubuntu-latest`, beides funktioniert also.
* Job-Container (`oven/bun:1`) ziehen beim ersten Lauf ~100 MB vom Docker Hub –
  der erste Lauf dauert dadurch länger, danach cached der Docker-Daemon.
* Der Runner braucht Lese-/Schreibzugriff auf `/var/run/docker.sock`
  (er startet die Job-Container) – das ist bewusst der Docker-Root-Entfernung
  auf diesem Host gleichzusetzen.
* **Sicherheit:** Jobs führen Repo-Code in Containern auf diesem Docker-Daemon
  aus. Da nur eigene, private Repos auf der Kiste laufen, vertretbar; bei
  zukünftigen Fremd-Repos mit Fork-PRs ggf. auf einen separaten Host auslagern.
