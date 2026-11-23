# Design-Tokens & UI-Leitlinien (Web)

Stand: November 2026. Die Regeln dieser Liste stammen aus einer Analyse klassischer
UI-Leitsätze; umgesetzt wurden nur die Punkte, die für Horizont einen echten Mehrwert
bringen. Grundlage war das unangetastete shadcn-Standard-Theme (reines Grau, kein
Markenakzent, reines Weiß/Schwarz).

## Farbpalette (src/app.css)

Abgestimmt auf die nativen Apps (`Sources/Support/DesignSystem.swift`): kühles
„Papier“ im Light-Mode, Graphite/Navy im Dark-Mode. **Keine reinen Schwarz- oder
Weißwerte** (weder `#fff` noch `#000` als Flächen-/Textfarbe).

- **60 %** – Hintergrund: `#F4F5F7` (Hell) / `#14151A` (Dunkel)
- **30 %** – Karten-, Sekundär- und Muted-Flächen: `#FCFCFD`, `#E7EAF0`, `#ECEEF3` /
  `#1C1E25`, `#24272F`, `#23262D`
- **10 %** – Markenakzent: das Sonnenamber des App-Icons (`static/favicon.svg`),
  Terrakotta `#B4551D` (Hell) bzw. `#E8975A` (Dunkel). Kontrast zu Vorder-/Hintergrund
  jeweils ≥ 4,5:1. Akzent ausschließlich für Primär-Aktionen, Fortschritt, Fokus-Ring
  und aktive Zustände – Hover-/Akzentflächen (`--accent`) bleiben neutral.

## Umgesetzte Leitsätze

| Leitsatz | Umsetzung |
| --- | --- |
| Nichts soll plötzlich erscheinen; Animationen schnell starten, sanft enden | `Modal` blendet/gleitet ein (150–160 ms Ease-out, aus 100 ms); Timeline-Zeilen und Tag-Blöcke fliegen sanft ein/aus (`DayBlock`, `TimePanel`); Intro beim ersten Seitenmount aus, `prefersReducedMotion` respektiert |
| Skeleton statt Spinner | Initial-Load der Startseite und der Workflow-Liste zeigen vorformatierte Skelett-Karten (`ui/skeleton`); Lade-Indikatoren erscheinen erst nach 250 ms (kein Flackern bei schnellen Loads) |
| Keine `confirm()`-Browserdialoge | `ConfirmDialog.svelte` (basiert auf dem eigenen Modal) für Löschen/Zurücksetzen/Ersetzen in Einstellungen, Workflows und Fokus-Seite |
| Löschen ohne Rückfrage, mit Rückholweg | Events/Tasks auf der Startseite verschwinden sofort; ein „Rückgängig“-Toast (6 s) stellt sie inkl. Server-Wiederherstellung zurück |
| Empty States mit Action | „Workflow anlegen“, „Kalender verbinden“, „Kategorie anlegen“ – Buttons im leeren Zustand fokassieren das jeweilige Eingabefeld |
| Hauptaktionen groß und offensichtlich | „Event“ als Primär-Button in Marken-Amber, „Aufgabe“ als Outline-Partner, „Aktualisieren“ zurückgenommen als Ghost-Button |

## Bewusst NICHT übernommen

- **Konfetti/Erfolgsfeier** – für einen Kalender Overkill; das sofortige Verschwinden
  abgehakter Tasks (optimistic UI, Zeigarnik) ist bereits die Belohnung.
- **„Show before explaining“ / Subheadline streichen** – die Unterzeile unter „Heute“
  bleibt Produkt-Identität.
- Die Gesetze selbst (Tesler, Postel, Parkinson, Hick, Fitts, Jakob, Miller …) sind
  Begründungen, keine Aufgaben; sie sind in den obigen Umsetzungen aufgegangen.

## Bereits vorher erfüllt (nicht ändern)

Nur eine Schrift (Inter Variable), `font-mono` nur für Code/Tokens, kein kursiver
Text, durchgehend Lucide-Icons, eine Komponentenbibliothek (shadcn/bits-ui),
Workflow-Fortschrittsbalken (Goal-Gradient), `active`-Druckfeedback an Buttons.
