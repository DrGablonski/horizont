// GET /api/health — öffentlicher Lese-Prüf-Endpunkt (Docker-Healthcheck).
// Bewusst ohne Auth und ohne Seiteneffekte: antwortet immer mit 200, solange
// der Prozess lebt.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from '@sveltejs/kit';

export const GET: RequestHandler = async () => json({ ok: true });
