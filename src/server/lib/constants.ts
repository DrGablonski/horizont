// Zentrale Konstanten für Zeitfenster und CalDAV.

import { resolve } from 'node:path';

// Jetzt: heute + 2 weitere Tage (Heute, Morgen, Übermorgen)
export const NOW_EXTRA_DAYS = 2;
// Zukunft: ab heute+3 bis heute+32 (letzter Tag, inklusive)
export const FUTURE_DAYS = 30;
// Vergangenheit: bis heute−1, zurück 14 Tage
export const PAST_DAYS = 14;
// Archiv: heute−365 bis heute−15, 31 Tage pro Seite
export const ARCHIVE_TOTAL_DAYS = 365;
export const ARCHIVE_PAGE_DAYS = 31;
export const ARCHIVE_GAP_DAYS = 15;

// Hauptansicht: eine CalDAV-Abfrage. Start = today−PAST (inklusive),
// End = exklusiv = (today + NOW_EXTRA + FUTURE) + 1 Tag, damit der letzte
// zukünftige Tag (today+NOW_EXTRA+FUTURE) vollständig mit abgedeckt ist.
export const MAIN_START_DAYS_BACK = PAST_DAYS;
export const MAIN_END_DAYS_AHEAD_EXCL = NOW_EXTRA_DAYS + FUTURE_DAYS + 1;

// Sicherheitsgrenzen
export const MAX_OCCURRENCES = 10_000;
export const DAV_TIMEOUT_MS = 20_000;

// Datenverzeichnis (überwridbar via DATA_DIR)
export const DATA_DIR = process.env.DATA_DIR ?? resolve(process.cwd(), 'data');
