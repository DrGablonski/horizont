# Horizont – iPhone

Native iPhone-App (SwiftUI, iOS 17+) – eigenständiger Zweig neben `apple/` (macOS)
und `ipad/` (iPad). Nur iPhone (`TARGETED_DEVICE_FAMILY: "1"`), inkl. Widgets.

## Bau & Installation

Voraussetzungen: XcodeGen (`brew install xcodegen`), ein iPhone per Kabel,
Apple-ID mit Personal Team in Xcode → Settings → Accounts (Team `2BKRSMQG7C`).

```sh
xcodegen generate                      # erzeugt HorizontiPhone.xcodeproj
xcodebuild -project HorizontiPhone.xcodeproj -scheme HorizontiPhone \
  -destination 'id=<UDID>' -configuration Debug \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=2BKRSMQG7C build
xcrun devicectl device install app --device <UDID> \
  build/DD/Build/Products/Debug-iphoneos/HorizontiPhone.app
```

Erster Start auf dem Gerät: Einstellungen → Allgemein → VPN & Geräteverwaltung →
Entwicklungsteam vertrauen.

## Wichtig

- **Personal Team (kostenlos):** App läuft 7 Tage, danach neu bauen & installieren.
- **Bundle-ID:** `de.hott.horizont.iphone`, App Group `group.de.hott.horizont.iphone`
  (bewusst getrennt von `ipad/` – beide Apps können parallel installiert sein).
- **Code-Sync:** `iphone/Sources` ist eine iPhone-optimierte Kopie von
  `ipad/Sources`. API-Modelle/Client (`Models/APIModels.swift`, `API/APIClient.swift`)
  stammen aus `apple/` und müssen bei Server-API-Änderungen in alle drei Zweige.
- Server erreichbar? App braucht LAN oder NetBird-Tunnel zur Server-URL.
