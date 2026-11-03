#!/usr/bin/env node
// MCP-Server für den selbst gehosteten Horizont-Kalender (stdio-Transport).
//
// Spricht die /api-Endpunkte von Horizont mit dem per-User API-Token
// (Horizont → Einstellungen → „API-Token (für externe Zugriffe)“ → Erzeugen).
//
// Konfiguration (Umgebungsvariablen):
//   HORIZONT_URL    Horizont-Instanz, z. B. http://localhost:8917
//                   (Default: http://localhost:8917)
//   HORIZONT_TOKEN  API-Token (hz_…). Falls nicht gesetzt, wird gelesen:
//                   ~/.config/horizont/token  (Datei, eine Zeile)

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const BASE_URL = (process.env.HORIZONT_URL || "http://localhost:8917").replace(/\/+$/, "");
const TOKEN_FILE = process.env.HORIZONT_TOKEN_FILE
  ?? path.join(os.homedir(), ".config", "horizont", "token");

function getToken() {
  const fromEnv = process.env.HORIZONT_TOKEN?.trim();
  if (fromEnv) return fromEnv;
  try {
    const fromFile = fs.readFileSync(TOKEN_FILE, "utf8").trim();
    if (fromFile) return fromFile;
  } catch {
    // Datei nicht vorhanden — Fehlermeldung kommt in api()
  }
  return null;
}

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

/** GET/POST/PATCH/DELETE gegen die Horizont-API; wirft ApiError bei Fehlantwort. */
async function api(method, urlPath, body) {
  const token = getToken();
  if (!token) {
    throw new ApiError(
      0,
      `Kein API-Token konfiguriert. Token erzeugen in Horizont → Einstellungen → „API-Token (für externe Zugriffe)“, ` +
        `und entweder die Umgebungsvariable HORIZONT_TOKEN setzen oder in ${TOKEN_FILE} schreiben (Datei: 600).`
    );
  }
  let res;
  try {
    res = await fetch(BASE_URL + urlPath, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    throw new ApiError(0, `Horizont unter ${BASE_URL} nicht erreichbar: ${e.message}`);
  }
  const text = await res.text();
  let data = null;
  try {
    data = JSON.parse(text);
  } catch {
    // nicht-JSON-Antwort
  }
  if (!res.ok) {
    const msg =
      data?.error || data?.message || `HTTP ${res.status} ${res.statusText}`.trim();
    throw new ApiError(res.status, msg);
  }
  return data;
}

// ── Formatierung (kompakt, token-sparend für LLM-Context) ──────────────────

function localISO(ms) {
  if (!ms) return undefined;
  const d = new Date(ms);
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

function compactEvent(e) {
  const o = {
    uid: e.uid,
    calendarId: e.calendarId,
    calendarName: e.calendarName,
    summary: e.summary,
    allDay: e.allDay,
    start: localISO(e.startMs),
    end: localISO(e.endMs),
    startMs: e.startMs,
    endMs: e.endMs,
  };
  if (e.location) o.location = e.location;
  if (e.description) o.description = e.description;
  return o;
}

function compactDay(day) {
  return {
    day: day.dayKey,
    isToday: day.isToday,
    events: day.events.map(compactEvent),
  };
}

function compactTask(t) {
  const o = {
    uid: t.uid,
    calendarId: t.calendarId,
    calendarName: t.calendarName,
    summary: t.summary,
    completed: t.completed,
  };
  if (t.description) o.description = t.description;
  if (t.dueKey) o.due = t.dueKey;
  if (t.dueMs) o.due = localISO(t.dueMs);
  if (t.category) o.category = t.category;
  else if (t.priority != null) o.priority = t.priority; // Altbestand (Kategorie-Fallback)
  return o;
}

function compactWorkflow(w) {
  const steps = (w.steps ?? []).map((s) => ({
    id: s.id,
    title: s.title,
    done: s.done,
  }));
  const done = steps.filter((s) => s.done).length;
  return {
    id: w.id,
    title: w.title,
    progress: w.progress,
    done,
    total: steps.length,
    activeStep: steps.find((s) => s.id === w.activeStepId) ?? null,
    nextStep: steps.find((s) => !s.done) ?? null,
    completedAt: w.completedAt ?? undefined,
  };
}

function compactWorkflowDetail(w) {
  return {
    ...compactWorkflow(w),
    notes: w.notes || undefined,
    steps: (w.steps ?? []).map((s) => ({ id: s.id, title: s.title, done: s.done })),
  };
}

// ── Server + Tool-Registrierung ────────────────────────────────────────────

const server = new McpServer(
  { name: "horizont", version: "0.1.0" },
  {
    instructions:
      "MCP-Tools für den selbst gehosteten Horizont-Kalender (CalDAV-Backend). " +
      "Termine/Tasks brauchen eine calendarId → zuerst das Tool calendars aufrufen. " +
      "Termin mit Uhrzeit: allDay=false + startMs/endMs (Unix epoch ms). " +
      "Ganztägiger Termin: allDay=true + dayKey (YYYY-MM-DD), bei mehr-tägigen Terminen zusätzlich endDateKey (inklusive). " +
      "update_event ist ein Voll-Update: alle Felder des Termins mitsenden (z. B. aus events übernehmen). " +
      "Workflows sind sequenzielle Aufgaben-Checklisten (Fokus-Modus), unabhängig vom CalDAV-Backend.",
  }
);

/** Tool registrieren und Handler-Ergebnis/Fehler einheitlich verpacken. */
function makeTool(name, def, handler) {
  server.registerTool(name, def, async (args) => {
    try {
      const data = await handler(args);
      const text = typeof data === "string" ? data : JSON.stringify(data);
      return { content: [{ type: "text", text }] };
    } catch (e) {
      const text =
        e instanceof ApiError ? `Horizont-Fehler: ${e.message}` : `Unerwarteter Fehler: ${e.message}`;
      return { content: [{ type: "text", text }], isError: true };
    }
  });
}

// ── Status ─────────────────────────────────────────────────────────────────

makeTool(
  "check_connection",
  {
    title: "Verbindung prüfen",
    description:
      "Prüft HORIZONT_URL + API-Token (GET /api/auth/me) und zeigt den User, ob CalDAV konfiguriert ist und welche Kalender vorhanden sind.",
  },
  async () => {
    const { user } = await api("GET", "/api/auth/me");
    const cal = await api("GET", "/api/calendars");
    return {
      url: BASE_URL,
      user: user?.username,
      role: user?.role,
      configured: cal?.configured,
      calendars: (cal?.calendars ?? []).map((c) => c.name),
    };
  }
);

// ── Kalender ───────────────────────────────────────────────────────────────

makeTool(
  "calendars",
  {
    title: "Kalender auflisten",
    description:
      "Alle CalDAV-Kalender des Users auflisten (id, name, connectionName). Die id ist die calendarId für Termine und Tasks.",
  },
  async (args) => {
    const data = await api("GET", "/api/calendars");
    if (data.error) throw new ApiError(502, data.error);
    if (!data.configured) {
      return { configured: false, calendars: [], hint: "Keine CalDAV-Verbindung konfiguriert (Horizont → Einstellungen)." };
    }
    return {
      configured: true,
      calendars: (data.calendars ?? []).map((c) => ({
        calendarId: c.id,
        name: c.name,
        connection: c.connectionName,
      })),
    };
  }
);

// ── Termine ────────────────────────────────────────────────────────────────

makeTool(
  "events",
  {
    title: "Termine lesen",
    description:
      'Termine lesen. scope="main" = Hauptansicht: Vergangenheit (14 Tage), Jetzt (heute + 2), Zukunft (30 Tage). ' +
      'scope="archive" = Monatsansicht bis 365 Tage zurück (monat=YYYY-MM; fehlt = neuester Archiv-Monat, canPrev/canNext zum Blättern).',
    inputSchema: {
      scope: z.enum(["main", "archive"]).default("main"),
      monat: z.string().optional().describe("YYYY-MM, nur bei scope=archive."),
    },
  },
  async ({ scope, monat }) => {
    const qs =
      scope === "archive"
        ? `?scope=archive${monat ? `&monat=${encodeURIComponent(monat)}` : ""}`
        : "?scope=main";
    const data = await api("GET", "/api/events" + qs);
    if (data.error) throw new ApiError(502, data.error);
    if (scope === "archive") {
      return {
        monthKey: data.monthKey,
        eventCount: data.eventCount,
        rangeStart: data.rangeStart,
        rangeEnd: data.rangeEnd,
        canPrev: data.canPrev,
        canNext: data.canNext,
        days: (data.days ?? []).filter((d) => d.events?.length).map(compactDay),
      };
    }
    const days = [];
    for (const panel of data.panels ?? []) {
      for (const day of panel.days ?? []) {
        if (!day.events?.length) continue;
        const c = compactDay(day);
        c.panel = panel.id;
        days.push(c);
      }
    }
    return { todayKey: data.todayKey, days };
  }
);

makeTool(
  "create_event",
  {
    title: "Termin anlegen",
    description:
      "Neuen Termin in einem CalDAV-Kalender anlegen. calendarId vorher über das Tool calendars holen. " +
      "Termin mit Uhrzeit: allDay=false + startMs/endMs (Unix epoch ms). Ganztägig: allDay=true + dayKey (YYYY-MM-DD), " +
      "bei mehr-tägigen Terminen zusätzlich endDateKey (letzter Tag, inklusive).",
    inputSchema: {
      calendarId: z.string().describe("Kalender-ID (aus calendars)."),
      summary: z.string().describe("Titel des Termins."),
      allDay: z.boolean().describe("true = ganztägig, false = Termin mit Uhrzeit."),
      dayKey: z.string().optional().describe("Erster Tag, YYYY-MM-DD (allDay=true)."),
      endDateKey: z.string().optional().describe("Letzter Tag, YYYY-MM-DD, inklusive (allDay=true, mehr-tägig)."),
      startMs: z.number().optional().describe("Unix epoch ms (allDay=false)."),
      endMs: z.number().optional().describe("Unix epoch ms (allDay=false)."),
      location: z.string().optional().describe("Ort."),
      description: z.string().optional().describe("Beschreibung/Notizen."),
    },
  },
  async (a) => {
    const body = { calendarId: a.calendarId, summary: a.summary, allDay: a.allDay };
    for (const k of ["dayKey", "endDateKey", "startMs", "endMs", "location", "description"]) {
      if (a[k] !== undefined) body[k] = a[k];
    }
    return api("POST", "/api/events", body);
  }
);

makeTool(
  "update_event",
  {
    title: "Termin bearbeiten",
    description:
      "Bestehenden Termin ändern (Voll-Update — alle Felder mitsenden, z. B. aus dem Tool events übernehmen). " +
      "calendarId + uid des Termins (aus events).",
    inputSchema: {
      calendarId: z.string(),
      uid: z.string().describe("iCal-UID des Termins (aus events)."),
      summary: z.string(),
      allDay: z.boolean(),
      dayKey: z.string().optional(),
      endDateKey: z.string().optional(),
      startMs: z.number().optional(),
      endMs: z.number().optional(),
      location: z.string().optional(),
      description: z.string().optional(),
    },
  },
  async (a) => {
    const body = {
      summary: a.summary,
      allDay: a.allDay,
    };
    for (const k of ["dayKey", "endDateKey", "startMs", "endMs", "location", "description"]) {
      if (a[k] !== undefined) body[k] = a[k];
    }
    return api(
      "PATCH",
      `/api/events/${encodeURIComponent(a.calendarId)}/${encodeURIComponent(a.uid)}`,
      body
    );
  }
);

makeTool(
  "delete_event",
  {
    title: "Termin löschen",
    description: "Bestehenden Termin löschen (calendarId + uid aus dem Tool events).",
    inputSchema: {
      calendarId: z.string(),
      uid: z.string(),
    },
  },
  async (a) =>
    api("DELETE", `/api/events/${encodeURIComponent(a.calendarId)}/${encodeURIComponent(a.uid)}`)
);

// ── Tasks ──────────────────────────────────────────────────────────────────

makeTool(
  "categories",
  {
    title: "Task-Kategorien auflisten",
    description:
      "Vom User verwaltete Aufgaben-Kategorien (Name + Farbe) auflisten — Namen für create_task/update_task.",
    inputSchema: {},
  },
  async () => {
    const data = await api("GET", "/api/categories");
    if (data.error) throw new ApiError(502, data.error);
    return { categories: data.categories ?? [] };
  }
);

makeTool(
  "tasks",
  {
    title: "Tasks auflisten",
    description:
      "VTODO-Tasks auflisten. Standardmäßig nur offene Tasks; includeCompleted=true zeigt auch erledigte.",
    inputSchema: {
      includeCompleted: z.boolean().default(false).describe("Erledigte Tasks mit anzeigen."),
    },
  },
  async ({ includeCompleted }) => {
    const data = await api("GET", "/api/tasks");
    if (data.error) throw new ApiError(502, data.error);
    const tasks = (data.tasks ?? []).filter((t) => includeCompleted || !t.completed).map(compactTask);
    return { configured: data.configured, count: tasks.length, tasks };
  }
);

makeTool(
  "create_task",
  {
    title: "Task anlegen",
    description:
      "Neue Aufgabe (VTODO) in einem CalDAV-Kalender anlegen. calendarId vorher über das Tool calendars holen.",
    inputSchema: {
      calendarId: z.string().describe("Kalender-ID (aus calendars)."),
      summary: z.string().describe("Titel der Aufgabe."),
      description: z.string().optional(),
      dueDate: z.string().optional().describe("Fälligkeitsdatum ohne Uhrzeit, YYYY-MM-DD."),
      dueMs: z.number().optional().describe("Fälligkeit mit Uhrzeit, Unix epoch ms."),
      category: z.string().optional()
        .describe("Kategoriename (vorher über das Tool categories holen), z. B. \"Schule\"."),
    },
  },
  async (a) => {
    const body = { calendarId: a.calendarId, summary: a.summary };
    if (a.description !== undefined) body.description = a.description;
    if (a.dueDate) body.due = { kind: "date", key: a.dueDate };
    else if (a.dueMs) body.due = { kind: "time", ms: a.dueMs };
    if (a.category !== undefined) body.category = a.category;
    return api("POST", "/api/tasks", body);
  }
);

makeTool(
  "update_task",
  {
    title: "Task bearbeiten",
    description:
      "Aufgabe ändern: Titel/Beschreibung, abhaken (completed), Fälligkeit (dueDate/dueMs oder removeDue=true entfernen), Kategorie (clearCategory=true entfernen).",
    inputSchema: {
      calendarId: z.string(),
      uid: z.string().describe("iCal-UID des Tasks (aus tasks)."),
      summary: z.string().optional(),
      description: z.string().optional(),
      completed: z.boolean().optional().describe("true = abhaken, false = wieder öffnen."),
      dueDate: z.string().optional().describe("Neues Fälligkeitsdatum ohne Uhrzeit, YYYY-MM-DD."),
      dueMs: z.number().optional().describe("Neue Fälligkeit mit Uhrzeit, Unix epoch ms."),
      removeDue: z.boolean().optional().describe("true = Fälligkeitsdatum entfernen."),
      category: z.string().optional().describe("Neue Kategorie (Namen aus categories)."),
      clearCategory: z.boolean().optional().describe("true = Kategorie entfernen."),
    },
  },
  async (a) => {
    const body = {};
    if (a.summary !== undefined) body.summary = a.summary;
    if (a.description !== undefined) body.description = a.description;
    if (a.completed !== undefined) body.completed = a.completed;
    if (a.removeDue) body.due = { kind: "none" };
    else if (a.dueDate) body.due = { kind: "date", key: a.dueDate };
    else if (a.dueMs) body.due = { kind: "time", ms: a.dueMs };
    if (a.clearCategory) body.category = null;
    else if (a.category !== undefined) body.category = a.category;
    return api(
      "PATCH",
      `/api/tasks/${encodeURIComponent(a.calendarId)}/${encodeURIComponent(a.uid)}`,
      body
    );
  }
);

makeTool(
  "complete_task",
  {
    title: "Task abhaken",
    description: "Aufgabe abhaken (oder mit completed=false wieder öffnen).",
    inputSchema: {
      calendarId: z.string(),
      uid: z.string(),
      completed: z.boolean().default(true).describe("true = abhaken (Default), false = wieder öffnen."),
    },
  },
  async (a) =>
    api(
      "PATCH",
      `/api/tasks/${encodeURIComponent(a.calendarId)}/${encodeURIComponent(a.uid)}`,
      { completed: a.completed }
    )
);

makeTool(
  "delete_task",
  {
    title: "Task löschen",
    description: "Aufgabe endgültig löschen (calendarId + uid aus dem Tool tasks).",
    inputSchema: {
      calendarId: z.string(),
      uid: z.string(),
    },
  },
  async (a) =>
    api("DELETE", `/api/tasks/${encodeURIComponent(a.calendarId)}/${encodeURIComponent(a.uid)}`)
);

// ── Workflows ──────────────────────────────────────────────────────────────

makeTool(
  "workflows",
  {
    title: "Workflows auflisten",
    description:
      "Alle Workflows (sequenzielle Aufgaben-Checklisten) mit Fortschritt, aktivem und nächstem Schritt auflisten.",
  },
  async () => {
    const data = await api("GET", "/api/workflows");
    return (data ?? []).map(compactWorkflow);
  }
);

makeTool(
  "get_workflow",
  {
    title: "Workflow laden",
    description: "Einen Workflow inkl. aller Schritte (mit Done-Status) laden.",
    inputSchema: { id: z.string() },
  },
  async ({ id }) => compactWorkflowDetail(await api("GET", `/api/workflows/${encodeURIComponent(id)}`))
);

makeTool(
  "create_workflow",
  {
    title: "Workflow anlegen",
    description:
      "Neuen Workflow (sequenzielle Checkliste) anlegen. steps = Schritt-Titel in der gewünschten Reihenfolge.",
    inputSchema: {
      title: z.string(),
      steps: z.array(z.string()).min(1).describe("Schritt-Titel in Reihenfolge."),
    },
  },
  async (a) => compactWorkflowDetail(await api("POST", "/api/workflows", a))
);

makeTool(
  "update_workflow",
  {
    title: "Workflow bearbeiten",
    description: "Workflow-Titel und/oder Notizen ändern.",
    inputSchema: {
      id: z.string(),
      title: z.string().optional(),
      notes: z.string().optional(),
    },
  },
  async (a) => {
    const body = {};
    if (a.title !== undefined) body.title = a.title;
    if (a.notes !== undefined) body.notes = a.notes;
    return compactWorkflowDetail(
      await api("PATCH", `/api/workflows/${encodeURIComponent(a.id)}`, body)
    );
  }
);

makeTool(
  "delete_workflow",
  {
    title: "Workflow löschen",
    description: "Workflow inkl. aller Schritte löschen.",
    inputSchema: { id: z.string() },
  },
  async ({ id }) => api("DELETE", `/api/workflows/${encodeURIComponent(id)}`)
);

makeTool(
  "add_workflow_step",
  {
    title: "Schritt anfügen",
    description: "Neuen Schritt am Ende eines Workflows anhängen.",
    inputSchema: {
      id: z.string(),
      title: z.string().describe("Titel des neuen Schritts."),
    },
  },
  async (a) =>
    compactWorkflowDetail(
      await api("POST", `/api/workflows/${encodeURIComponent(a.id)}/steps`, { title: a.title })
    )
);

makeTool(
  "update_workflow_step",
  {
    title: "Schritt bearbeiten",
    description:
      "Schritt eines Workflows ändern: Titel und/oder erledigen (done=true — der Workflow springt weiter).",
    inputSchema: {
      id: z.string(),
      stepId: z.string().describe("Schritt-ID (aus get_workflow)."),
      title: z.string().optional(),
      done: z.boolean().optional().describe("true = Schritt als erledigt markieren."),
    },
  },
  async (a) => {
    const body = {};
    if (a.title !== undefined) body.title = a.title;
    if (a.done !== undefined) body.done = a.done;
    return compactWorkflowDetail(
      await api(
        "PATCH",
        `/api/workflows/${encodeURIComponent(a.id)}/steps/${encodeURIComponent(a.stepId)}`,
        body
      )
    );
  }
);

makeTool(
  "delete_workflow_step",
  {
    title: "Schritt löschen",
    description: "Einen Schritt aus einem Workflow entfernen.",
    inputSchema: {
      id: z.string(),
      stepId: z.string(),
    },
  },
  async (a) =>
    api(
      "DELETE",
      `/api/workflows/${encodeURIComponent(a.id)}/steps/${encodeURIComponent(a.stepId)}`
    )
);

makeTool(
  "reset_workflow",
  {
    title: "Workflow zurücksetzen",
    description: "Alle Schritte eines Workflows auf offen zurücksetzen.",
    inputSchema: { id: z.string() },
  },
  async ({ id }) =>
    compactWorkflowDetail(await api("POST", `/api/workflows/${encodeURIComponent(id)}/reset`))
);

// ── Start ──────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(`Horizont MCP-Server bereit (Horizont: ${BASE_URL})`);
