# Horizont – native iPadOS-App

SwiftUI-Client für den selbst gehosteten [Horizont](../README.md)-Kalender — Phase 2
neben der macOS-App (`apple/`). Nutzt dieselbe REST-API (`/api/*`), CalDAV bleibt
serverseitig.

```
ipad/
├── project.yml          ← XcodeGen-Definition (App + Widget-Extension)
├── Support/             ← Info.plist/Entitlements (werden von XcodeGen geschrieben)
├── Resources/           ← Assets (AppIcon iOS, BrandIcon)
└── Sources/
    ├── API/ Models/ State/ Views/ Support/   ← kompletter App-Code (iPadOS)
    ├── HorizontApp.swift    ← iPad-Scene (ohne MenuBarExtra)
    ├── RootView.swift       ← Auth-Gate + PadMainView (NavigationSplitView-Shell)
    └── Widgets/             ← WidgetKit: „Heute“ (mittel/groß) + Sperrbildschirm
```

Eigenständiger Ordner — `apple/` (macOS) und `ipad/` (iPadOS) sind getrennte
Projekte mit jeweils vollem Code. Ausgangspunkt war der Mac-Code; Differences
(DesignSystem-Farben, ThemeStore etc.) sind hier bereits für iPadOS umgesetzt,
ohne `#if os(...)`-Guards.

## Auf dem Mac bauen

Voraussetzung: Xcode 15+ und [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
cd horizont/ipad
xcodegen generate
open HorizontiPad.xcodeproj
```

1. Ziel **HorizontiPad** + Destination z. B. *iPad Pro 13" (iPadOS 17+)* wählen
2. Signing: Team = dein persönliches Apple-ID-Team (für App **und** Widget-Target)
3. **Run** (⌘R) — oder direkt auf ein angeschlossenes iPad (Entwicklermodus an)

Ohne Developer-Account läuft alles auf dem Simulator; auf echtem iPad gilt das
7-Tage-Self-Signing.

## Gesten (iPad)

- **Nach rechts wischen** auf einer Aufgabenzeile → erledigen (grüner Slider)
- **Lange drücken** auf einer Zeile → Kontextmenü (Erledigen/Details/Löschen)
- Pull-to-Refresh in allen Listen

## Widgets

Zwei Widgets, Look 1:1 aus der App (eigene Palette, Ambient-Hintergrund):

| Widget | Größen | Inhalt |
| ------ | ------ | ------ |
| **Heute** | mittel, groß | Heutige Termine/Aufgaben mit Zeit + Kalenderfarbe, „+n weitere“, Zähler offene Aufgaben |
| **Heute (kompakt)** | Sperrbildschirm (rectangular) | Offene Aufgaben + die ersten zwei Einträge |

Technik: Die App schreibt nach jedem Daten-Laden einen JSON-Snapshot in den
App-Group-Container (`group.de.hott.horizont`) und triggert
`WidgetCenter.reloadAllTimelines()`. Widgets brauchen dadurch **kein eigenes
Login** und funktionieren auch offline (mit letztem Stand + Zeitstempel).
Nach Server-Neustart einmal die App öffnen, dann sind die Widgets wieder frisch.

Auch Theme (Akzentfarbe/Hell/Dunkel) wird über die App-Group-Defaults geteilt.

## Hinweise

- HTTP-ATS-Ausnahme wie am Mac (LAN/NetBird). Für unterwegs NetBird nicht
  vergessen — iOS kann keinen permanenten Hintergrundtunnel wie macOS.
- Die App ruft den API-Token (`/api/token`) bewusst nicht auf (MCP-Token bleibt erhalten).
