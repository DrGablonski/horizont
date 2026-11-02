// Smoke-Test: Mock-Horizont-API + echter MCP-Server (stdio).
// Prüft: initialize, tools/list, tools/call (Lesen + Schreiben), Fehlerfall (401).

import http from "node:http";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── Mock-API ───────────────────────────────────────────────────────────────

const requests = [];

const mock = http.createServer((req, res) => {
  const body = [];
  req.on("data", (c) => body.push(c));
  req.on("end", () => {
    const parsed = body.length ? JSON.parse(Buffer.concat(body).toString()) : null;
    requests.push({ method: req.method, url: req.url, token: req.headers.authorization ?? null, body: parsed });
    res.setHeader("Content-Type", "application/json");

    if (req.headers.authorization !== "Bearer hz_test") {
      res.statusCode = 401;
      return res.end(JSON.stringify({ error: "Kein oder ungültiges API-Token." }));
    }

    const u = new URL(req.url, "http://x");
    const p = u.pathname;

    if (req.method === "GET" && p === "/api/auth/me") {
      return res.end(JSON.stringify({ user: { id: "u1", username: "test", role: "admin", createdAt: 0, lastLoginAt: null } }));
    }
    if (req.method === "GET" && p === "/api/calendars") {
      return res.end(JSON.stringify({
        configured: true,
        calendars: [
          { id: "cal-personal", name: "Persönlich", color: "#4f46e5", url: "http://dav/cals/personal" },
          { id: "cal-schule", name: "Schule", color: "#dc2626", url: "http://dav/cals/schule" },
        ],
      }));
    }
    if (req.method === "GET" && p === "/api/events") {
      if (u.searchParams.get("scope") === "archive") {
        return res.end(JSON.stringify({
          monthKey: "2026-09", eventCount: 1, canPrev: false, canNext: true,
          rangeStart: "2026-09-10", rangeEnd: "2026-09-25",
          days: [{ dayKey: "2026-09-15", label: "15.09.", isToday: false, events: [event("uid-old", "Alt-Termin")] }],
        }));
      }
      return res.end(JSON.stringify({
        todayKey: "2026-10-30", generatedAt: Date.now(), configured: true,
        panels: [
          { id: "past", title: "Vergangenheit", subtitle: "x", eventCount: 0, defaultOpen: false, days: [] },
          { id: "now", title: "Jetzt", subtitle: "x", eventCount: 1, defaultOpen: true, days: [
            { dayKey: "2026-10-30", label: "Heute", isToday: true, events: [event("uid-1", "Standup", true)] },
          ] },
          { id: "future", title: "Zukunft", subtitle: "x", eventCount: 1, defaultOpen: true, days: [
            { dayKey: "2026-11-10", label: "10.11.", isToday: false, events: [event("uid-2", "Mathe-Klausur", true)] },
          ] },
        ],
      }));
    }
    if (req.method === "GET" && p === "/api/categories") {
      return res.end(JSON.stringify({
        categories: [
          { name: "Schule", color: "#2563eb" },
          { name: "Hoch", color: "#dc2626" },
        ],
      }));
    }
    if (req.method === "GET" && p === "/api/tasks") {
      return res.end(JSON.stringify({
        configured: true,
        tasks: [
          { id: "t1", uid: "task-1", calendarId: "cal-schule", calendarName: "Schule", calendarColor: "#dc2626", summary: "Mathe lernen", completed: false, dueKey: "2026-11-10", category: "Schule" },
          { id: "t2", uid: "task-2", calendarId: "cal-schule", calendarName: "Schule", calendarColor: "#dc2626", summary: "Erledigt", completed: true },
        ],
      }));
    }
    if (req.method === "POST" && p === "/api/events") {
      res.statusCode = 201;
      return res.end(JSON.stringify({ ...event("uid-new", parsed.summary), calendarId: parsed.calendarId, startMs: parsed.startMs ?? 0, endMs: parsed.endMs ?? 0, allDay: parsed.allDay }));
    }
    if (req.method === "POST" && p === "/api/tasks") {
      res.statusCode = 201;
      return res.end(JSON.stringify({ id: "t3", uid: "task-3", calendarId: parsed.calendarId, calendarName: "Schule", summary: parsed.summary, completed: false, dueKey: parsed.due?.key, category: parsed.category }));
    }
    const stepMatch = p.match(/^\/api\/workflows\/([^/]+)\/steps$/);
    if (req.method === "POST" && stepMatch) {
      res.statusCode = 201;
      return res.end(JSON.stringify(workflow("w1", "Tägliche Routine", [
        { id: "s1", title: "Frühstück", done: true },
        { id: "s2", title: parsed.title, done: false },
      ])));
    }
    const wfMatch = p.match(/^\/api\/workflows(?:\/([^/]+))?$/);
    if (wfMatch && req.method === "GET" && p === "/api/workflows") {
      return res.end(JSON.stringify([workflow("w1", "Tägliche Routine", [
        { id: "s1", title: "Frühstück", done: true },
        { id: "s2", title: "Einschlagen", done: false },
      ])]));
    }
    if (wfMatch && req.method === "GET") {
      return res.end(JSON.stringify(workflow("w1", "Tägliche Routine", [
        { id: "s1", title: "Frühstück", done: true },
        { id: "s2", title: "Einschlagen", done: false },
      ])));
    }
    if (wfMatch && req.method === "POST") {
      res.statusCode = 201;
      return res.end(JSON.stringify(workflow("w-new", parsed.title, parsed.steps.map((t, i) => ({ id: `sn${i}`, title: t, done: false })))));
    }
    res.statusCode = 404;
    res.end(JSON.stringify({ error: `Mock kennt ${req.method} ${p} nicht` }));
  });
});

function event(uid, summary, timed = false) {
  const start = new Date("2026-10-30T09:00:00").getTime();
  return {
    id: "e" + uid, uid, calendarId: "cal-personal", calendarName: "Persönlich", calendarColor: "#4f46e5",
    summary, allDay: !timed, startMs: start, endMs: start + 3600000,
  };
}
function workflow(id, title, steps) {
  const done = steps.filter((s) => s.done).length;
  return {
    id, title, notes: "", createdAt: 0, updatedAt: 0, completedAt: null,
    activeStepId: steps.find((s) => !s.done)?.id ?? null,
    steps: steps.map((s) => ({ ...s, completedAt: s.done ? 1 : null })),
    progress: steps.length ? done / steps.length : 0,
  };
}

// ── MCP-Client (stdio, JSON-RPC) ───────────────────────────────────────────

function startMcpServer(env) {
  const child = spawn(process.execPath, [path.join(__dirname, "..", "index.mjs")], {
    env: { ...process.env, ...env },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let buf = "";
  const pending = new Map();
  const childErr = [];
  child.stderr.on("data", (d) => childErr.push(d.toString()));
  child.stdout.on("data", (d) => {
    buf += d.toString();
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      const msg = JSON.parse(line);
      if (msg.id !== undefined && pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    }
  });
  let nextId = 1;
  return {
    child,
    childErr,
    request(method, params) {
      const id = nextId++;
      const line = JSON.stringify({ jsonrpc: "2.0", id, method, params });
      child.stdin.write(line + "\n");
      return new Promise((resolve, reject) => {
        pending.set(id, resolve);
        setTimeout(() => {
          if (pending.has(id)) {
            pending.delete(id);
            reject(new Error(`Timeout auf ${method}. stderr: ${childErr.join("")}`));
          }
        }, 10000);
      });
    },
    notify(method, params) {
      child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
    },
  };
}

// ── Testlauf ───────────────────────────────────────────────────────────────

let failures = 0;
function check(name, cond, extra = "") {
  if (cond) console.log(`  ok  ${name}`);
  else {
    failures++;
    console.log(`FAIL  ${name} ${extra}`);
  }
}
function toolText(result) {
  if (result.isError) return null;
  return JSON.parse(result.content[0].text);
}

await new Promise((r) => mock.listen(18917, "127.0.0.1", r));

const env = { HORIZONT_URL: "http://127.0.0.1:18917", HORIZONT_TOKEN: "hz_test" };
const mcp = startMcpServer(env);

try {
  const init = await mcp.request("initialize", {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "smoke", version: "0.0.1" },
  });
  check("initialize", init.result?.serverInfo?.name === "horizont", JSON.stringify(init));
  mcp.notify("notifications/initialized");

  const tools = await mcp.request("tools/list", {});
  const names = tools.result.tools.map((t) => t.name).sort();
  console.log(`  tools (${names.length}): ${names.join(", ")}`);
  for (const expected of [
    "calendars", "check_connection", "events", "create_event", "update_event", "delete_event",
    "tasks", "create_task", "update_task", "complete_task", "delete_task",
    "workflows", "get_workflow", "create_workflow", "update_workflow", "delete_workflow",
    "add_workflow_step", "update_workflow_step", "delete_workflow_step", "reset_workflow",
  ]) {
    check(`tool ${expected}`, names.includes(expected));
  }

  const me = toolText((await mcp.request("tools/call", { name: "check_connection", arguments: {} })).result);
  check("check_connection", me?.user === "test" && me?.configured === true, JSON.stringify(me));

  const cals = toolText((await mcp.request("tools/call", { name: "calendars", arguments: {} })).result);
  check("calendars", cals?.calendars?.length === 2 && cals.calendars[0].calendarId === "cal-personal");

  const ev = toolText((await mcp.request("tools/call", { name: "events", arguments: { scope: "main" } })).result);
  const evs = ev?.days?.flatMap((d) => d.events) ?? [];
  check("events main", ev?.todayKey === "2026-10-30" && evs.length === 2 && evs.some((e) => e.summary === "Mathe-Klausur"), JSON.stringify(ev));

  const arch = toolText((await mcp.request("tools/call", { name: "events", arguments: { scope: "archive", monat: "2026-09" } })).result);
  check("events archive", arch?.monthKey === "2026-09" && arch?.days?.length === 1);

  const created = toolText((await mcp.request("tools/call", {
    name: "create_event",
    arguments: { calendarId: "cal-personal", summary: "Klausur", allDay: false, startMs: 1794219000000, endMs: 1794226200000 },
  })).result);
  check("create_event", created?.uid === "uid-new" && created?.summary === "Klausur");
  const evReq = requests.find((r) => r.url === "/api/events" && r.method === "POST");
  check("create_event body", evReq?.body?.calendarId === "cal-personal" && evReq?.body?.startMs === 1794219000000);

  const ts = toolText((await mcp.request("tools/call", { name: "tasks", arguments: {} })).result);
  check("tasks (nur offen)", ts?.count === 1 && ts?.tasks?.[0]?.summary === "Mathe lernen");

  const ct = toolText((await mcp.request("tools/call", {
    name: "create_task",
    arguments: { calendarId: "cal-schule", summary: "Übung", dueDate: "2026-11-10", category: "Schule" },
  })).result);
  check("create_task", ct?.uid === "task-3" && ct?.dueKey === "2026-11-10");
  const taskReq = requests.find((r) => r.url === "/api/tasks" && r.method === "POST");
  check("create_task due-Mapping", taskReq?.body?.due?.kind === "date" && taskReq.body.due.key === "2026-11-10" && taskReq.body.category === "Schule", JSON.stringify(taskReq?.body));

  const catRes = toolText((await mcp.request("tools/call", { name: "categories", arguments: {} })).result);
  check("categories", Array.isArray(catRes?.categories) && catRes.categories.some((c) => c.name === "Schule"), JSON.stringify(catRes));

  const wfs = toolText((await mcp.request("tools/call", { name: "workflows", arguments: {} })).result);
  check("workflows", Array.isArray(wfs) && wfs[0].progress === 0.5 && wfs[0].nextStep?.title === "Einschlagen", JSON.stringify(wfs));

  const step = toolText((await mcp.request("tools/call", {
    name: "add_workflow_step",
    arguments: { id: "w1", title: "Abendessen" },
  })).result);
  check("add_workflow_step", step?.steps?.some((s) => s.title === "Abendessen"));

  // Fehlerfall: falscher Token → isError mit Nachricht, kein Crash
  const bad = startMcpServer({ HORIZONT_URL: "http://127.0.0.1:18917", HORIZONT_TOKEN: "hz_falsch" });
  await bad.request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke2", version: "0" } });
  bad.notify("notifications/initialized");
  const err = await bad.request("tools/call", { name: "tasks", arguments: {} });
  check("401 → isError", err.result?.isError === true && /Token/.test(err.result.content[0].text), JSON.stringify(err.result));
  bad.child.kill();

  // Fehlerfall: Token-Datei-Reader
  const noTok = startMcpServer({ HORIZONT_URL: "http://127.0.0.1:18917", HORIZONT_TOKEN_FILE: "/tmp/opencode/horizont-test-token" });
  await noTok.request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke3", version: "0" } });
  noTok.notify("notifications/initialized");
  const err2 = await noTok.request("tools/call", { name: "tasks", arguments: {} });
  check("fehlender Token → Hinweis", err2.result?.isError === true && /API-Token/.test(err2.result.content[0].text));
  noTok.child.kill();
} finally {
  mcp.child.kill();
  mock.close();
}

console.log(failures === 0 ? "\nAlle Tests bestanden." : `\n${failures} Test(s) fehlgeschlagen.`);
process.exit(failures === 0 ? 0 : 1);
