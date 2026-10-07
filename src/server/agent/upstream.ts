// LLM-Aufrufe (Streaming) für OpenAI-kompatible Endpoints und Ollama.
// Provider-unabhängige AgentMsgs werden an der Grenze in das jeweils
// erwartete Format übersetzt; Tool-Calls werden während des Streams
// akkumuliert und komplett zurückgegeben.

import type { AgentConfig } from '$lib/types';
import type { AgentMsg, ToolCall, ToolDef } from './types';

export interface LLMResult {
	content: string;
	toolCalls: ToolCall[];
}

export interface LLMCallOptions {
	temperature?: number;
	signal?: AbortSignal;
	timeoutMs?: number;
	onDelta?: (text: string) => void;
}

const DEFAULT_TIMEOUT_MS = 120_000;
const DEFAULT_TEMPERATURE = 0.2;

// ── URL-Resolution ────────────────────────────────────────────────────────

function chatCompletionsUrl(config: AgentConfig): string {
	const base = config.baseUrl.replace(/\/+$/, '');
	if (config.provider === 'ollama') return `${base}/api/chat`;
	// OpenAI-kompatibel: Basis-URL mit oder ohne /v1-Suffix akzeptieren.
	if (/\/v\d+$/.test(base)) return `${base}/chat/completions`;
	return `${base}/v1/chat/completions`;
}

// ── Message-Konvertierung ─────────────────────────────────────────────────

function toOpenAIMessages(messages: AgentMsg[]): Record<string, unknown>[] {
	return messages.map((m) => {
		switch (m.role) {
			case 'system':
			case 'user':
				return { role: m.role, content: m.content };
			case 'assistant':
				return {
					role: 'assistant',
					content: m.content,
					...(m.toolCalls && m.toolCalls.length
						? {
								tool_calls: m.toolCalls.map((tc) => ({
									id: tc.id,
									type: 'function',
									function: { name: tc.name, arguments: JSON.stringify(tc.args) }
								}))
							}
						: {})
				};
			case 'tool':
				return { role: 'tool', tool_call_id: m.toolCallId, content: m.content };
		}
	});
}

function toOllamaMessages(messages: AgentMsg[]): Record<string, unknown>[] {
	return messages.map((m) => {
		switch (m.role) {
			case 'system':
			case 'user':
				return { role: m.role, content: m.content };
			case 'assistant':
				return {
					role: 'assistant',
					content: m.content,
					...(m.toolCalls && m.toolCalls.length
						? {
								tool_calls: m.toolCalls.map((tc) => ({
									name: tc.name,
									arguments: tc.args
								}))
							}
						: {})
				};
			case 'tool':
				return { role: 'tool', name: m.name, content: m.content };
		}
	});
}

function toOpenAITools(tools: ToolDef[]): Record<string, unknown>[] {
	return tools.map((t) => ({
		type: 'function',
		function: { name: t.name, description: t.description, parameters: t.parameters }
	}));
}

// ── Tool-Call-Akkumulation (OpenAI-Deltas) ────────────────────────────────

interface PartialCall {
	id?: string;
	name?: string;
	argsJson: string;
}

// ── Hauptschleife ─────────────────────────────────────────────────────────

export async function callLLM(
	config: AgentConfig,
	messages: AgentMsg[],
	tools: ToolDef[],
	opts: LLMCallOptions
): Promise<LLMResult> {
	const isOllama = config.provider === 'ollama';
	const url = chatCompletionsUrl(config);

	const body = isOllama
		? {
				model: config.model,
				messages: toOllamaMessages(messages),
				tools: tools.length ? toOpenAITools(tools) : undefined,
				stream: true,
				options: { temperature: opts.temperature ?? DEFAULT_TEMPERATURE }
			}
		: {
				model: config.model,
				messages: toOpenAIMessages(messages),
				tools: tools.length ? toOpenAITools(tools) : undefined,
				stream: true,
				temperature: opts.temperature ?? DEFAULT_TEMPERATURE
			};

	const headers: Record<string, string> = { 'content-type': 'application/json' };
	if (config.provider === 'openai' && config.apiKey) headers['authorization'] = `Bearer ${config.apiKey}`;

	const controller = new AbortController();
	const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
	const timer = setTimeout(() => controller.abort(new Error('Timeout')), timeoutMs);
	const onOuterAbort = () => controller.abort(opts.signal?.reason);
	opts.signal?.addEventListener('abort', onOuterAbort, { once: true });

	let response: Response;
	try {
		response = await fetch(url, {
			method: 'POST',
			headers,
			body: JSON.stringify(body),
			signal: controller.signal
		});
	} catch (e) {
		if (opts.signal?.aborted) throw e; // Client weg → weiterreichen
		throw new Error(
			`LLM-Endpoint nicht erreichbar: ${e instanceof Error ? e.message : String(e)}`
		);
	} finally {
		clearTimeout(timer);
		opts.signal?.removeEventListener('abort', onOuterAbort);
	}

	if (!response.ok || !response.body) {
		const text = (await response.text().catch(() => '')).slice(0, 500);
		throw new Error(`LLM-Endpoint ${response.status}: ${text || 'kein Fehlerkörper'}`);
	}

	const reader = response.body.getReader();
	const decoder = new TextDecoder();
	let buffer = '';
	let content = '';

	if (isOllama) {
		let lastToolCalls: { name: string; arguments: Record<string, unknown> }[] = [];
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			buffer += decoder.decode(value, { stream: true });
			const lines = buffer.split('\n');
			buffer = lines.pop() ?? '';
			for (const line of lines) {
				const trimmed = line.trim();
				if (!trimmed) continue;
				let obj: any;
				try {
					obj = JSON.parse(trimmed);
				} catch {
					continue;
				}
				const msg = obj?.message;
				if (msg?.content) {
					content += msg.content;
					opts.onDelta?.(msg.content);
				}
				if (Array.isArray(msg?.tool_calls) && msg.tool_calls.length > 0) {
					lastToolCalls = msg.tool_calls;
				}
			}
		}
		const toolCalls: ToolCall[] = lastToolCalls.map((tc, i) => ({
			id: `ollama_${i + 1}_${tc.name}`,
			name: String(tc.name ?? ''),
			args: typeof tc.arguments === 'object' && tc.arguments != null ? tc.arguments : {}
		}));
		return { content, toolCalls };
	}

	// ── OpenAI-kompatible SSE ──
	const partials = new Map<number, PartialCall>();
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		buffer += decoder.decode(value, { stream: true });
		const lines = buffer.split('\n');
		buffer = lines.pop() ?? '';
		for (const line of lines) {
			const trimmed = line.trim();
			if (!trimmed.startsWith('data:')) continue;
			const data = trimmed.slice(5).trim();
			if (data === '[DONE]') continue;
			let obj: any;
			try {
				obj = JSON.parse(data);
			} catch {
				continue;
			}
			const choice = obj?.choices?.[0];
			const delta = choice?.delta;
			if (!delta) continue;
			if (typeof delta.content === 'string' && delta.content.length > 0) {
				content += delta.content;
				opts.onDelta?.(delta.content);
			}
			const tcs = delta.tool_calls;
			if (Array.isArray(tcs)) {
				for (const tc of tcs) {
					const idx = typeof tc.index === 'number' ? tc.index : partials.size;
					let p = partials.get(idx);
					if (!p) {
						p = { argsJson: '' };
						partials.set(idx, p);
					}
					if (tc.id) p.id = tc.id;
					if (tc.function?.name) p.name = tc.function.name;
					if (typeof tc.function?.arguments === 'string') {
						p.argsJson += tc.function.arguments;
					}
				}
			}
		}
	}

	const toolCalls: ToolCall[] = [];
	let i = 0;
	for (const p of partials.values()) {
		i += 1;
		if (!p.name) continue;
		let args: Record<string, unknown> = {};
		try {
			args = p.argsJson ? (JSON.parse(p.argsJson) as Record<string, unknown>) : {};
		} catch {
			args = {};
		}
		toolCalls.push({ id: p.id ?? `call_${i}`, name: p.name, args });
	}
	return { content, toolCalls };
}

/**
 * Nicht-Streamende Test-Abfrage für die Konfig-Verbindungsprüfung
 * (kürzt den Kontext auf eine einzige User-Nachricht).
 */
export async function testLLM(config: AgentConfig, prompt: string, signal?: AbortSignal): Promise<string> {
	const messages: AgentMsg[] = [
		{ role: 'system', content: 'Du bist ein Verbindungstest. Antworte in einem kurzen Satz.' },
		{ role: 'user', content: prompt }
	];
	const result = await callLLM(config, messages, [], { signal, timeoutMs: 30_000 });
	const text = result.content.trim();
	if (!text) throw new Error('Leere Antwort vom LLM.');
	return text;
}
