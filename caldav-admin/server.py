#!/usr/bin/env python3
"""caldav-admin: kleines Admin-API für Radicale-htpasswd-User + Collection-Verzeichnisse.

Radicale selbst hat keine Admin-API. Dieser Sidecar verwaltet:
  - /etc/radicale/users            (htpasswd, bcrypt – wird von Radicale autodetectiert)
  - /var/lib/radicale/collections/{login}   (Collection-Verzeichnis pro User)

Endpunkte (Token via X-Admin-Token, aus /etc/caldav-admin/admin.env):
  GET    /health                → {"ok": true}
  GET    /api/v1/users          → {"users": [...]}
  POST   /api/v1/users          → {"login": ...}          Body: {"login", "password"}
  DELETE /api/v1/users/{login}  → {"ok": true}            (User + Collections entfernen)
"""

import grp
import hmac
import json
import os
import pwd
import re
import shutil
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from passlib.hash import bcrypt as bcrypt_hash

HOST = "0.0.0.0"
PORT = 5233
USERS_FILE = "/etc/radicale/users"
COLLECTIONS_DIR = "/var/lib/radicale/collections"
ENV_FILE = "/etc/caldav-admin/admin.env"
LOGIN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,31}$")
BCRYPT_ROUNDS = 12

_lock = threading.Lock()
_admin_token: str | None = None


def log(msg: str) -> None:
    print(f"caldav-admin: {msg}", file=sys.stderr, flush=True)


def load_token() -> None:
    global _admin_token
    _admin_token = None
    try:
        with open(ENV_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("ADMIN_TOKEN="):
                    _admin_token = line.split("=", 1)[1].strip() or None
    except OSError as e:
        log(f"kann {ENV_FILE} nicht lesen: {e}")
    if _admin_token is None:
        log(f"FEHLER: ADMIN_TOKEN ist in {ENV_FILE} nicht gesetzt – alle Requests werden abgelehnt.")


class ApiError(Exception):
    def __init__(self, msg: str, status: int) -> None:
        super().__init__(msg)
        self.msg = msg
        self.status = status


def read_users() -> dict[str, str]:
    users: dict[str, str] = {}
    try:
        with open(USERS_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                login, _, hashed = line.partition(":")
                if login and hashed:
                    users[login] = hashed
    except FileNotFoundError:
        pass
    return users


def _radicale_gid() -> int:
    try:
        return grp.getgrnam("radicale").gr_gid
    except KeyError:
        return 0


def write_users(users: dict[str, str]) -> None:
    """Atomares Schreiben des htpasswd-Dateis (chmod 640, chown root:radicale)."""
    tmp = USERS_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for login in sorted(users):
            f.write(f"{login}:{users[login]}\n")
    os.chmod(tmp, 0o640)
    os.chown(tmp, 0, _radicale_gid())
    os.replace(tmp, USERS_FILE)


def collection_dir(login: str) -> str:
    return os.path.join(COLLECTIONS_DIR, login)


def principal_dir(login: str) -> str:
    # CalDAV-Principal (Radicale legt es beim ersten Zugriff an); hier liegen
    # die eigentlichen Kalender + .ics-Dateien.
    return os.path.join(COLLECTIONS_DIR, "collection-root", login)


def _remove_dir(path: str) -> None:
    if os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)
        log(f"Verzeichnis entfernt: {path}")


def ensure_collection_dir(login: str) -> None:
    path = collection_dir(login)
    if os.path.isdir(path):
        return
    os.makedirs(path, exist_ok=True)
    os.chmod(path, 0o750)
    try:
        pw = pwd.getpwnam("radicale")
        os.chown(path, pw.pw_uid, pw.pw_gid)
    except KeyError:
        log(f"keinen User 'radicale' gefunden, chown übersprungen für {path}")


def create_user(login: str, password: str) -> None:
    if not LOGIN_RE.match(login):
        raise ApiError("Ungültiger Login (1-32 Zeichen, Buchstaben/Ziffern/._-, kein - am Anfang).", 400)
    if len(password) < 8:
        raise ApiError("Passwort muss mindestens 8 Zeichen lang sein.", 400)
    with _lock:
        users = read_users()
        if login in users:
            raise ApiError(f"User '{login}' existiert bereits.", 409)
        users[login] = bcrypt_hash.using(rounds=BCRYPT_ROUNDS).hash(password)
        write_users(users)
        ensure_collection_dir(login)
    log(f"User angelegt: {login}")


def delete_user(login: str) -> None:
    with _lock:
        users = read_users()
        if login not in users:
            raise ApiError(f"User '{login}' existiert nicht.", 404)
        del users[login]
        write_users(users)
        _remove_dir(collection_dir(login))
        _remove_dir(principal_dir(login))
    log(f"User entfernt: {login}")


class Handler(BaseHTTPRequestHandler):
    server_version = "caldav-admin/1.0"

    def _send(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _error(self, status: int, msg: str) -> None:
        self._send(status, {"error": msg})

    def _auth_ok(self) -> bool:
        if _admin_token is None:
            self._error(500, "ADMIN_TOKEN ist auf dem Server nicht konfiguriert.")
            return False
        token = self.headers.get("X-Admin-Token", "")
        if not hmac.compare_digest(token, _admin_token):
            self._error(403, "Admin-Token ungültig.")
            return False
        return True

    def _path(self) -> str:
        return self.path.split("?", 1)[0]

    def _safe(self, fn) -> None:
        try:
            fn()
        except ApiError as e:
            self._error(e.status, e.msg)
        except Exception:
            import traceback

            log(traceback.format_exc())
            if not self._headers_sent:
                self._error(500, "Interner Serverfehler.")

    @property
    def _headers_sent(self) -> bool:
        return self.headers_sent

    def _get(self) -> None:
        path = self._path()
        if path == "/health":
            if not self._auth_ok():
                return
            self._send(200, {"ok": True})
            return
        if path == "/api/v1/users":
            if not self._auth_ok():
                return
            with _lock:
                users = read_users()
            self._send(200, {"users": sorted(users)})
            return
        self._error(404, "Pfad unbekannt.")

    def do_GET(self) -> None:
        self._safe(self._get)

    def _post(self) -> None:
        path = self._path()
        if path != "/api/v1/users":
            self._error(404, "Pfad unbekannt.")
            return
        if not self._auth_ok():
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
        except (ValueError, UnicodeDecodeError):
            self._error(400, "Body muss JSON sein.")
            return
        login = str(body.get("login", ""))
        password = str(body.get("password", ""))
        create_user(login, password)
        self._send(201, {"login": login})

    def do_POST(self) -> None:
        self._safe(self._post)

    def _delete(self) -> None:
        path = self._path()
        if not path.startswith("/api/v1/users/"):
            self._error(404, "Pfad unbekannt.")
            return
        if not self._auth_ok():
            return
        login = path[len("/api/v1/users/"):]
        if not LOGIN_RE.match(login):
            self._error(400, "Ungültiger Login.")
            return
        delete_user(login)
        self._send(200, {"ok": True})

    def do_DELETE(self) -> None:
        self._safe(self._delete)

    def log_message(self, fmt: str, *args) -> None:
        log(f"{self.address_string()} {fmt % args}")


def main() -> None:
    load_token()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    log(f"laufe auf {HOST}:{PORT} (Users: {USERS_FILE}, Collections: {COLLECTIONS_DIR})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
