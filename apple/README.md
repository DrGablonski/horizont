# Horizont – native Apple-App

SwiftUI-Client für den selbst gehosteten [Horizont](../README.md)-Kalender.
Er nutzt ausschließlich die REST-API (`/api/*`) des Horizont-Servers — CalDAV
bleibt komplett serverseitig.

**Phase 1:** natives **macOS**-Ziel (Sonoma, Apple Silicon). iPhone/iPad
kommen als nächste Phase (Ziele dann in `project.yml` erweitern).

## Aufbau

```
apple/
├── project.yml          ← XcodeGen-Definition (einzige Projektquelle)
├── Support/Info.plist
└── Sources/
    ├── HorizontApp.swift
    ├── API/APIClient.swift      ← URLSession + Session-Cookie-Auth
    ├── Models/APIModels.swift   ← spiegelt src/lib/types.ts
    ├── State/                   ← AuthStore (Login/Keychain), AppStore (Daten)
    ├── Support/                 ← Keychain, Theme/Helfer
    └── Views/                   ← Login, Horizonte, Archiv, Workflows, Einstellungen
```

Die `.xcodeproj` ist **nicht** eingecheckt — sie wird lokal generiert.

## Auf dem Mac bauen

Voraussetzung: Xcode 15+ (Sonoma) und [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd horizont/apple
xcodegen generate
open Horizont.xcodeproj
```

Dann in Xcode:
1. Ziel **Horizont** + Destination **My Mac** wählen
2. Target → Signing & Capabilities: Team = dein persönliches Apple-ID-Team
3. **Run** (⌘R)

Ohne Developer-Account läuft die App lokal (persönliches Signing, 7 Tage gültig).

## Auth

Login wie im Web (Session-Cookie). Benutzername/Passwort liegen in der
**Keychain**; die App loggt sich nach Server-Neustart automatisch neu ein.
Der API-Token (`/api/token`, Bearer) wird von der App bewusst **nicht**
angerührt — ein POST darauf würde den bestehenden MCP-Token ersetzen.

## Server-Erreichbarkeit

Die App akzeptiert HTTP (ATS-Ausnahme in `Info.plist`) — praktisch fürs LAN.
Sobald der Server hinter Reverse Proxy mit gültigem TLS hängt, kann die
Ausnahme wieder raus. Unterwegs: NetBird-Tunnel zum Hausnetz nutzen.
