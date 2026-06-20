import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { DEFAULT_MAX_BYTES, DEFAULT_MAX_LINES, formatSize, truncateHead } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { existsSync, readFileSync } from "node:fs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { Type } from "typebox";

const SECRETS_DIR = join(homedir(), ".pi", "agent", "secrets");
const BRAVE_SEARCH_KEY_FILE = join(SECRETS_DIR, "brave-api-key");
const BRAVE_AI_KEY_FILE = join(SECRETS_DIR, "brave-ai-api-key");
const BRAVE_LLM_CONTEXT_KEY_FILE = join(SECRETS_DIR, "brave-llm-context-api-key");
const FIRECRAWL_KEY_FILE = join(SECRETS_DIR, "firecrawl-api-key");
const FIRECRAWL_BASE = "https://api.firecrawl.dev/v2";
const MAX_TOOL_BYTES = DEFAULT_MAX_BYTES;
const MAX_TOOL_LINES = DEFAULT_MAX_LINES;
const BRAVE_MIN_INTERVAL_MS = (() => {
	const configured = Number(process.env.BRAVE_MIN_INTERVAL_MS);
	return Number.isFinite(configured) ? Math.min(Math.max(Math.trunc(configured), 0), 60_000) : 1100;
})(); // Safe default for legacy/free Brave limits; set BRAVE_MIN_INTERVAL_MS lower if your Search plan allows higher QPS.

type SecretSource = { env?: string; file?: string };

const BRAVE_SEARCH_SECRET_SOURCES: SecretSource[] = [
	{ env: "BRAVE_SEARCH_API_KEY" },
	{ env: "BRAVE_FREE_API_KEY" },
	{ env: "BRAVE_API_KEY" },
	{ file: BRAVE_SEARCH_KEY_FILE },
];
const BRAVE_AI_SECRET_SOURCES: SecretSource[] = [
	{ env: "BRAVE_AI_API_KEY" },
	{ env: "BRAVE_DATA_FOR_AI_API_KEY" },
	{ file: BRAVE_AI_KEY_FILE },
];
const BRAVE_LLM_CONTEXT_PRIMARY_SECRET_SOURCES: SecretSource[] = [
	{ env: "BRAVE_LLM_CONTEXT_API_KEY" },
	{ file: BRAVE_LLM_CONTEXT_KEY_FILE },
];
const BRAVE_LLM_CONTEXT_SECRET_SOURCES: SecretSource[] = [
	...BRAVE_LLM_CONTEXT_PRIMARY_SECRET_SOURCES,
	{ env: "BRAVE_SEARCH_API_KEY" },
	{ env: "BRAVE_API_KEY" },
	{ file: BRAVE_SEARCH_KEY_FILE },
];
const FIRECRAWL_SECRET_SOURCES: SecretSource[] = [
	{ env: "FIRECRAWL_API_KEY" },
	{ file: FIRECRAWL_KEY_FILE },
];

const secretCache = new Map<string, string>();
const braveQueues = new Map<string, Promise<void>>();

function cleanSecretValue(raw: string | undefined) {
	return (raw ?? "").replace(/\s+/g, "");
}

function secretSourceLabel(source: SecretSource) {
	return source.env ? `$${source.env}` : source.file ?? "(unknown)";
}

function readSecret(cacheKey: string, sources: SecretSource[]) {
	const cached = secretCache.get(cacheKey);
	if (cached) return cached;

	for (const source of sources) {
		const raw = source.env !== undefined
			? process.env[source.env]
			: source.file && existsSync(source.file)
				? readFileSync(source.file, "utf8")
				: "";
		const cleaned = cleanSecretValue(raw);
		if (!cleaned) continue;
		secretCache.set(cacheKey, cleaned);
		return cleaned;
	}

	throw new Error(`Missing ${cacheKey}; set one of ${sources.map(secretSourceLabel).join(", ")}`);
}

function hasSecretSource(sources: SecretSource[]) {
	return sources.some((source) => {
		const raw = source.env !== undefined
			? process.env[source.env]
			: source.file && existsSync(source.file)
				? readFileSync(source.file, "utf8")
				: "";
		return Boolean(cleanSecretValue(raw));
	});
}

function braveContextEnabled() {
	if (process.env.BRAVE_ENABLE_LLM_CONTEXT === "0") return false;
	if (process.env.BRAVE_ENABLE_LLM_CONTEXT === "1") return true;
	return hasSecretSource(BRAVE_LLM_CONTEXT_PRIMARY_SECRET_SOURCES);
}

function clampNumber(value: unknown, fallback: number, min: number, max: number) {
	const n = typeof value === "number" && Number.isFinite(value) ? value : fallback;
	return Math.min(Math.max(Math.trunc(n), min), max);
}

function cleanObject<T extends Record<string, unknown>>(obj: T) {
	return Object.fromEntries(
		Object.entries(obj).filter(([, value]) => value !== undefined && value !== null && !(Array.isArray(value) && value.length === 0)),
	) as Partial<T>;
}

function normalizeHttpUrl(input: string) {
	const raw = input.trim().replace(/^@/, "");
	const withProtocol = /^[a-zA-Z][a-zA-Z\d+.-]*:/.test(raw) ? raw : `https://${raw}`;
	const parsed = new URL(withProtocol);
	if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("Only http(s) URLs are allowed");
	return parsed.toString();
}

function setSearchParam(url: URL, key: string, value: unknown) {
	if (value === undefined || value === null || value === "") return;
	url.searchParams.set(key, String(value));
}

function retryDelayMs(headers: Headers) {
	const retryAfter = headers.get("retry-after");
	if (!retryAfter) return undefined;
	const seconds = Number(retryAfter);
	if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
	const dateMs = Date.parse(retryAfter);
	return Number.isFinite(dateMs) ? Math.max(0, dateMs - Date.now()) : undefined;
}

function sleep(ms: number, signal?: AbortSignal | null) {
	if (ms <= 0) return Promise.resolve();
	return new Promise<void>((resolve, reject) => {
		const timeout = setTimeout(done, ms);
		function done() {
			signal?.removeEventListener("abort", abort);
			resolve();
		}
		function abort() {
			clearTimeout(timeout);
			reject(new Error("Aborted"));
		}
		signal?.addEventListener("abort", abort, { once: true });
	});
}

async function fetchJson(url: string, init: RequestInit, service: string, retries = 1) {
	let lastMessage = "";
	for (let attempt = 0; attempt <= retries; attempt++) {
		const response = await fetch(url, init);
		const raw = await response.text();
		let data: unknown = raw;
		try { data = raw ? JSON.parse(raw) : null; } catch { /* keep raw */ }

		if (response.ok) return data;

		const body = typeof data === "string" ? data : JSON.stringify(data);
		lastMessage = `${service} ${response.status} ${response.statusText}: ${body.slice(0, 1000)}`;
		if (attempt < retries && (response.status === 429 || response.status >= 500)) {
			const delay = retryDelayMs(response.headers) ?? 800 * 2 ** attempt;
			await sleep(delay, init.signal);
			continue;
		}
		throw new Error(lastMessage);
	}
	throw new Error(lastMessage || `${service} failed`);
}

async function withBraveRateLimit<T>(queueKey: string, fn: () => Promise<T>) {
	const previous = braveQueues.get(queueKey) ?? Promise.resolve();
	let release!: () => void;
	braveQueues.set(queueKey, new Promise<void>((resolve) => { release = resolve; }));
	await previous;
	try {
		return await fn();
	} finally {
		setTimeout(release, BRAVE_MIN_INTERVAL_MS);
	}
}

type BraveKeyKind = "search" | "ai" | "llmContext";

function braveApiKey(kind: BraveKeyKind) {
	if (kind === "ai") return readSecret("BRAVE_AI_API_KEY", BRAVE_AI_SECRET_SOURCES);
	if (kind === "llmContext") return readSecret("BRAVE_LLM_CONTEXT_API_KEY", BRAVE_LLM_CONTEXT_SECRET_SOURCES);
	return readSecret("BRAVE_SEARCH_API_KEY", BRAVE_SEARCH_SECRET_SOURCES);
}

async function braveJson(url: URL, signal: AbortSignal | undefined, service: string, extraHeaders: Record<string, string> = {}, keyKind: BraveKeyKind = "search") {
	const apiKey = braveApiKey(keyKind);
	return withBraveRateLimit(keyKind, () => fetchJson(url.toString(), {
		headers: { "X-Subscription-Token": apiKey, Accept: "application/json", "Accept-Encoding": "gzip", ...extraHeaders },
		signal,
	}, service, 2));
}

function firecrawlHeaders() {
	const apiKey = readSecret("FIRECRAWL_API_KEY", FIRECRAWL_SECRET_SOURCES);
	return { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json", Accept: "application/json" };
}

async function firecrawlPost(path: string, body: unknown, signal: AbortSignal | undefined, service: string) {
	return fetchJson(`${FIRECRAWL_BASE}${path}`, {
		method: "POST",
		headers: firecrawlHeaders(),
		body: JSON.stringify(body),
		signal,
	}, service, 1);
}

async function firecrawlGet(pathOrUrl: string, signal: AbortSignal | undefined, service: string) {
	const url = pathOrUrl.startsWith("http") ? pathOrUrl : `${FIRECRAWL_BASE}${pathOrUrl}`;
	return fetchJson(url, { headers: firecrawlHeaders(), signal }, service, 1);
}

async function truncateForTool(text: string, maxBytesInput?: number, label = "web-output") {
	const maxBytes = clampNumber(maxBytesInput, MAX_TOOL_BYTES, 1000, MAX_TOOL_BYTES);
	const truncation = truncateHead(text, { maxBytes, maxLines: MAX_TOOL_LINES });
	if (!truncation.truncated) return { text: truncation.content, truncation };

	const dir = await mkdtemp(join(tmpdir(), "pi-web-"));
	const file = join(dir, `${label.replace(/[^a-z0-9._-]+/gi, "-").slice(0, 48)}.txt`);
	await writeFile(file, text, "utf8");

	const omittedLines = truncation.totalLines - truncation.outputLines;
	const omittedBytes = truncation.totalBytes - truncation.outputBytes;
	return {
		text: `${truncation.content}\n\n[Output truncated: showing ${truncation.outputLines} of ${truncation.totalLines} lines (${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)}). ${omittedLines} lines (${formatSize(omittedBytes)}) omitted. Full output saved to: ${file}]`,
		truncation,
		fullOutputPath: file,
	};
}

function compactMetadata(metadata: any = {}) {
	return cleanObject({
		title: metadata.title,
		description: metadata.description,
		sourceURL: metadata.sourceURL,
		url: metadata.url,
		statusCode: metadata.statusCode,
		contentType: metadata.contentType,
		cacheState: metadata.cacheState,
		cachedAt: metadata.cachedAt,
		creditsUsed: metadata.creditsUsed,
		proxyUsed: metadata.proxyUsed,
		error: metadata.error,
	});
}

function shortSnippet(text: unknown, max = 900) {
	if (typeof text !== "string") return undefined;
	const cleaned = text.replace(/\s+/g, " ").trim();
	return cleaned.length > max ? `${cleaned.slice(0, max)}…` : cleaned;
}

function renderSearchSection(name: string, items: Array<Record<string, any>>) {
	if (!items.length) return "";
	const lines = [`## ${name}`];
	items.forEach((item, index) => {
		lines.push(`${index + 1}. ${item.title ?? "(untitled)"}`);
		if (item.url) lines.push(`   URL: ${item.url}`);
		if (item.description) lines.push(`   ${item.description}`);
		if (item.age) lines.push(`   Age: ${item.age}`);
		if (item.extraSnippets?.length) {
			for (const snippet of item.extraSnippets.slice(0, 3)) lines.push(`   - ${snippet}`);
		}
	});
	return lines.join("\n");
}

function stringifyValue(value: unknown): string {
	if (value === undefined || value === null) return "";
	if (typeof value === "string") return value;
	if (Array.isArray(value)) return value.map((item) => stringifyValue(item)).filter(Boolean).join("\n");
	return JSON.stringify(value, null, 2);
}

function errorText(error: unknown) {
	return error instanceof Error ? error.message : String(error);
}

function renderFirecrawlResultSection(name: string, items: any[]) {
	if (!items.length) return "";
	const lines = [`## ${name}`];
	items.forEach((item, index) => {
		lines.push(`${index + 1}. ${item.title ?? item.imageUrl ?? "(untitled)"}`);
		if (item.url) lines.push(`   URL: ${item.url}`);
		if (item.imageUrl) lines.push(`   Image: ${item.imageUrl}`);
		if (item.imageWidth || item.imageHeight) lines.push(`   Size: ${item.imageWidth ?? "?"}x${item.imageHeight ?? "?"}`);
		if (item.date) lines.push(`   Date: ${item.date}`);
		if (item.description ?? item.snippet) lines.push(`   ${shortSnippet(item.description ?? item.snippet)}`);
		if (item.category) lines.push(`   Category: ${item.category}`);
		const content = item.summary ?? item.markdown;
		if (content) lines.push(`\n${content}\n`);
	});
	return lines.join("\n");
}

function firecrawlSearchBuckets(data: any) {
	const root = data.data ?? data;
	return {
		web: root.web ?? [],
		news: root.news ?? [],
		images: root.images ?? [],
	};
}

function braveLocationHeaders(params: any) {
	const headers: Record<string, string> = {};
	if (params.locLat !== undefined) headers["X-Loc-Lat"] = String(params.locLat);
	if (params.locLong !== undefined) headers["X-Loc-Long"] = String(params.locLong);
	if (params.locCity) headers["X-Loc-City"] = String(params.locCity);
	if (params.locState) headers["X-Loc-State"] = String(params.locState);
	if (params.locStateName) headers["X-Loc-State-Name"] = String(params.locStateName);
	if (params.locCountry) headers["X-Loc-Country"] = String(params.locCountry);
	if (params.locPostalCode) headers["X-Loc-Postal-Code"] = String(params.locPostalCode);
	return headers;
}

function isWebOnlyResultFilter(resultFilter: unknown) {
	if (typeof resultFilter !== "string" || !resultFilter.trim()) return true;
	const filters = resultFilter.split(",").map((filter) => filter.trim().toLowerCase()).filter(Boolean);
	return filters.length === 0 || filters.every((filter) => filter === "web");
}

function braveResults(data: any) {
	const mapBasic = (r: any) => cleanObject({
		title: r.title,
		url: r.url,
		description: shortSnippet(r.description ?? r.snippet),
		age: r.age ?? r.page_age,
		profile: r.profile?.name,
		extraSnippets: Array.isArray(r.extra_snippets) ? r.extra_snippets.map((s: string) => shortSnippet(s, 500)).filter(Boolean) : undefined,
	});
	return cleanObject({
		web: (data.web?.results ?? []).map(mapBasic),
		news: (data.news?.results ?? []).map(mapBasic),
		videos: (data.videos?.results ?? []).map(mapBasic),
		discussions: (data.discussions?.results ?? []).map(mapBasic),
		locations: (data.locations?.results ?? []).map((r: any) => cleanObject({ title: r.title, url: r.url, description: shortSnippet(r.description), id: r.id })),
	});
}

function firecrawlScrapeOptions(params: any) {
	const options: Record<string, unknown> = {};
	if (params.onlyMainContent !== undefined) options.onlyMainContent = params.onlyMainContent;
	else options.onlyMainContent = true;
	if (params.onlyCleanContent !== undefined) options.onlyCleanContent = params.onlyCleanContent;
	if (params.fresh) options.maxAge = 0;
	else if (params.maxAgeMs !== undefined) options.maxAge = clampNumber(params.maxAgeMs, 172_800_000, 0, 31_536_000_000);
	if (params.minAgeMs !== undefined) options.minAge = clampNumber(params.minAgeMs, 0, 0, 31_536_000_000);
	if (params.waitForMs !== undefined) options.waitFor = clampNumber(params.waitForMs, 0, 0, 60_000);
	if (params.timeoutMs !== undefined) options.timeout = clampNumber(params.timeoutMs, 60_000, 1000, 300_000);
	if (params.mobile !== undefined) options.mobile = params.mobile;
	if (params.proxy) options.proxy = params.proxy;
	if (params.parsers?.length) options.parsers = params.parsers;
	if (params.locationCountry || params.locationLanguages?.length) options.location = cleanObject({ country: params.locationCountry, languages: params.locationLanguages });
	if (params.removeBase64Images !== undefined) options.removeBase64Images = params.removeBase64Images;
	if (params.blockAds !== undefined) options.blockAds = params.blockAds;
	if (params.storeInCache !== undefined) options.storeInCache = params.storeInCache;
	if (params.lockdown !== undefined) options.lockdown = params.lockdown;
	if (params.redactPII !== undefined) options.redactPII = params.redactPII;
	if (params.zeroDataRetention !== undefined) options.zeroDataRetention = params.zeroDataRetention;
	return options;
}

function crawlPageSummary(page: any) {
	const metadata = compactMetadata(page.metadata);
	return cleanObject({
		url: metadata.url ?? metadata.sourceURL,
		title: metadata.title,
		description: metadata.description,
		statusCode: metadata.statusCode,
		error: metadata.error,
		markdown: page.markdown,
		summary: page.summary,
	});
}

export default function webResearchExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description: "Search the live web using Brave Web Search. Returns compact source URLs/snippets only; use web_context or web_fetch for page content. extraSnippets uses the Brave Free AI/Data for AI key when configured.",
		promptSnippet: "Search the live web with Brave Search for up-to-date source URLs",
		promptGuidelines: [
			"Use web_search (Brave Free) for lightweight/current URL discovery before fetching pages; prefer authoritative sources such as official docs, vendor blogs, GitHub repos, changelogs, and standards bodies.",
			"Keep web_search calls quota-friendly: use precise queries, small count values, resultFilter for only the needed result types, site:/filetype: operators, and pagination only when necessary.",
			"Use extraSnippets=true with resultFilter=web when Brave snippets are enough; this uses the Brave Free AI/Data for AI key when configured and can avoid a Firecrawl fetch.",
			"Use web_context/web_fetch when you need Firecrawl-extracted source content.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query. Supports Brave operators like site:, filetype:, and quoted phrases." }),
			count: Type.Optional(Type.Number({ description: "Number of web results, 1-20. Default 10." })),
			offset: Type.Optional(Type.Number({ description: "Page offset, 0-9. Use only if query.more_results_available is true." })),
			country: Type.Optional(Type.String({ description: "2-letter country code, e.g. US. Default US." })),
			searchLang: Type.Optional(Type.String({ description: "Search language, e.g. en, es, de." })),
			uiLang: Type.Optional(Type.String({ description: "Response UI language, e.g. en-US." })),
			freshness: Type.Optional(Type.String({ description: "Recency filter: pd, pw, pm, py, or YYYY-MM-DDtoYYYY-MM-DD." })),
			safesearch: Type.Optional(StringEnum(["off", "moderate", "strict"] as const, { description: "Adult-content filter. Default moderate." })),
			resultFilter: Type.Optional(Type.String({ description: "Comma-separated result types. Default web. Examples: web,news,videos,discussions,locations." })),
			extraSnippets: Type.Optional(Type.Boolean({ description: "Return up to 5 extra snippets per result for more context. Default false." })),
			goggles: Type.Optional(Type.String({ description: "Optional Brave Goggle URL or inline definition for custom reranking." })),
		}),
		async execute(_id, params, signal) {
			const url = new URL("https://api.search.brave.com/res/v1/web/search");
			setSearchParam(url, "q", params.query);
			setSearchParam(url, "count", clampNumber(params.count, 10, 1, 20));
			setSearchParam(url, "offset", clampNumber(params.offset, 0, 0, 9));
			setSearchParam(url, "country", params.country ?? "US");
			setSearchParam(url, "search_lang", params.searchLang);
			setSearchParam(url, "ui_lang", params.uiLang);
			setSearchParam(url, "freshness", params.freshness);
			setSearchParam(url, "safesearch", params.safesearch);
			setSearchParam(url, "result_filter", params.resultFilter ?? "web");
			setSearchParam(url, "text_decorations", "false");
			setSearchParam(url, "extra_snippets", params.extraSnippets ? "true" : undefined);
			setSearchParam(url, "goggles", params.goggles);

			const keyKind: BraveKeyKind = params.extraSnippets && isWebOnlyResultFilter(params.resultFilter) && hasSecretSource(BRAVE_AI_SECRET_SOURCES) ? "ai" : "search";
			const data: any = await braveJson(url, signal, "Brave Search", {}, keyKind);
			const results = braveResults(data);
			const sections = [
				renderSearchSection("Web", (results as any).web ?? []),
				renderSearchSection("News", (results as any).news ?? []),
				renderSearchSection("Videos", (results as any).videos ?? []),
				renderSearchSection("Discussions", (results as any).discussions ?? []),
				renderSearchSection("Locations", (results as any).locations ?? []),
			].filter(Boolean);
			const queryInfo = cleanObject({
				original: data.query?.original,
				altered: data.query?.altered,
				moreResultsAvailable: data.query?.more_results_available,
			});
			const text = [`Query: ${params.query}`, queryInfo.moreResultsAvailable !== undefined ? `More results available: ${queryInfo.moreResultsAvailable}` : "", ...sections].filter(Boolean).join("\n\n");
			return { content: [{ type: "text", text }], details: { query: queryInfo, results, braveKeyKind: keyKind } };
		},
	});

	if (braveContextEnabled()) pi.registerTool({
		name: "web_brave_context",
		label: "Brave LLM Context",
		description: "Use Brave's LLM Context endpoint for fast answer-ready grounding snippets, tables, code, forum text, and YouTube captions. Requires explicit LLM Context access; Brave Free AI/Data for AI is used by web_search extraSnippets instead.",
		promptSnippet: "Get Brave LLM Context grounding in one search call when enabled",
		promptGuidelines: [
			"Use web_brave_context sparingly because it requires a Brave LLM Context-capable plan/key; prefer Firecrawl web_context/web_fetch for normal paid grounding.",
			"Use web_brave_context when Firecrawl is missing, blocked, noisy, or needs independent Brave corroboration, or when one LLM Context call can replace many searches/fetches.",
			"If web_brave_context returns quota or plan errors, fall back to web_search plus Firecrawl web_fetch/web_context.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query/question for Brave LLM Context." }),
			count: Type.Optional(Type.Number({ description: "Search results to consider, 1-50. Default 20." })),
			country: Type.Optional(Type.String({ description: "2-letter country code. Default US." })),
			searchLang: Type.Optional(Type.String({ description: "Search language. Default en." })),
			freshness: Type.Optional(Type.String({ description: "Recency filter: pd, pw, pm, py, or YYYY-MM-DDtoYYYY-MM-DD." })),
			maxUrls: Type.Optional(Type.Number({ description: "Maximum URLs in context, 1-50. Default 20." })),
			maxTokens: Type.Optional(Type.Number({ description: "Approx token budget, 1024-32768. Default 8192." })),
			maxSnippets: Type.Optional(Type.Number({ description: "Maximum snippets across URLs, 1-256. Default 50." })),
			maxTokensPerUrl: Type.Optional(Type.Number({ description: "Max tokens per URL, 512-8192. Default 4096." })),
			maxSnippetsPerUrl: Type.Optional(Type.Number({ description: "Max snippets per URL, 1-100. Default 50." })),
			thresholdMode: Type.Optional(StringEnum(["strict", "balanced", "lenient", "disabled"] as const, { description: "Relevance threshold. Default balanced." })),
			goggles: Type.Optional(Type.String({ description: "Optional Brave Goggle URL or inline definition for source reranking/filtering." })),
			enableLocal: Type.Optional(Type.Boolean({ description: "Enable local recall. Auto if location headers provided." })),
			enableSourceMetadata: Type.Optional(Type.Boolean({ description: "Include source metadata like favicon/thumbnail. Default false." })),
			locLat: Type.Optional(Type.Number({ description: "Location latitude for local queries." })),
			locLong: Type.Optional(Type.Number({ description: "Location longitude for local queries." })),
			locCity: Type.Optional(Type.String({ description: "Location city for local queries." })),
			locState: Type.Optional(Type.String({ description: "Location state/region code for local queries." })),
			locStateName: Type.Optional(Type.String({ description: "Location state/region name for local queries." })),
			locCountry: Type.Optional(Type.String({ description: "Location country code for local queries." })),
			locPostalCode: Type.Optional(Type.String({ description: "Location postal code for local queries." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const url = new URL("https://api.search.brave.com/res/v1/llm/context");
			setSearchParam(url, "q", params.query);
			setSearchParam(url, "count", clampNumber(params.count, 20, 1, 50));
			setSearchParam(url, "country", params.country ?? "US");
			setSearchParam(url, "search_lang", params.searchLang);
			setSearchParam(url, "freshness", params.freshness);
			setSearchParam(url, "maximum_number_of_urls", params.maxUrls !== undefined ? clampNumber(params.maxUrls, 20, 1, 50) : undefined);
			setSearchParam(url, "maximum_number_of_tokens", params.maxTokens !== undefined ? clampNumber(params.maxTokens, 8192, 1024, 32768) : undefined);
			setSearchParam(url, "maximum_number_of_snippets", params.maxSnippets !== undefined ? clampNumber(params.maxSnippets, 50, 1, 256) : undefined);
			setSearchParam(url, "maximum_number_of_tokens_per_url", params.maxTokensPerUrl !== undefined ? clampNumber(params.maxTokensPerUrl, 4096, 512, 8192) : undefined);
			setSearchParam(url, "maximum_number_of_snippets_per_url", params.maxSnippetsPerUrl !== undefined ? clampNumber(params.maxSnippetsPerUrl, 50, 1, 100) : undefined);
			setSearchParam(url, "context_threshold_mode", params.thresholdMode);
			setSearchParam(url, "goggles", params.goggles);
			setSearchParam(url, "enable_local", params.enableLocal);
			setSearchParam(url, "enable_source_metadata", params.enableSourceMetadata);

			const data: any = await braveJson(url, signal, "Brave LLM Context", braveLocationHeaders(params), "llmContext");
			const grounding = data.grounding ?? {};
			const generic = grounding.generic ?? [];
			const poi = grounding.poi ? [grounding.poi] : [];
			const map = grounding.map ?? [];
			const lines = [`Query: ${params.query}`];
			const renderGrounding = (name: string, items: any[]) => {
				if (!items.length) return;
				lines.push(`\n## ${name}`);
				items.forEach((item, index) => {
					lines.push(`${index + 1}. ${item.title ?? item.name ?? "(untitled)"}`);
					if (item.url) lines.push(`URL: ${item.url}`);
					for (const snippet of (item.snippets ?? []).slice(0, params.maxSnippetsPerUrl ?? 50)) lines.push(`- ${snippet}`);
				});
			};
			renderGrounding("Generic", generic);
			renderGrounding("POI", poi);
			renderGrounding("Map", map);
			const truncated = await truncateForTool(lines.join("\n"), params.maxChars, "brave-llm-context");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: {
					query: params.query,
					urls: [...generic, ...poi, ...map].map((item: any) => item.url).filter(Boolean),
					sourceCount: Object.keys(data.sources ?? {}).length,
					sources: data.sources,
					truncation: truncated.truncation,
					fullOutputPath: truncated.fullOutputPath,
				},
			};
		},
	});

	pi.registerTool({
		name: "web_context",
		label: "Web Context",
		description: "Search and return answer-ready content snippets for AI grounding in one paid Firecrawl call (search + summary scraping). Best when you need answer-ready context without fetching pages one by one.",
		promptSnippet: "Get answer-ready web snippets (Firecrawl search + summary) for quick AI grounding",
		promptGuidelines: [
			"Use web_context for Firecrawl Standard quick grounding when answer-ready snippets are enough; one call can replace web_search plus several web_fetch calls.",
			"Use web_search for lightweight URL discovery, but prefer web_context when you want summarized content inline or Brave quota/coverage is insufficient.",
			"Use web_fetch after web_context only for sources that need verification, exact quotes, or fuller content.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query." }),
			count: Type.Optional(Type.Number({ description: "Number of results to ground on, 1-20. Default 8." })),
			country: Type.Optional(Type.String({ description: "2-letter country code. Default US." })),
			freshness: Type.Optional(Type.String({ description: "Recency filter: pd, pw, pm, py (mapped to Firecrawl qdr:d/w/m/y), or a raw Firecrawl tbs value." })),
			sources: Type.Optional(Type.Array(StringEnum(["web", "news", "images"] as const), { description: "Firecrawl search sources. Default web. Add news/images when needed." })),
			includeDomains: Type.Optional(Type.Array(Type.String(), { description: "Only include these hostnames. Cannot be used with excludeDomains." })),
			excludeDomains: Type.Optional(Type.Array(Type.String(), { description: "Exclude these hostnames. Cannot be used with includeDomains." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const freshnessToTbs: Record<string, string> = { pd: "qdr:d", pw: "qdr:w", pm: "qdr:m", py: "qdr:y" };
			const tbs = params.freshness ? (freshnessToTbs[params.freshness] ?? params.freshness) : undefined;
			const body: Record<string, unknown> = cleanObject({
				query: params.query,
				limit: clampNumber(params.count, 8, 1, 20),
				country: params.country ?? "US",
				tbs,
				sources: params.sources,
				includeDomains: params.includeDomains,
				excludeDomains: params.excludeDomains,
				ignoreInvalidURLs: true,
				scrapeOptions: { formats: ["summary"], onlyMainContent: true },
			});
			const data: any = await firecrawlPost("/search", body, signal, "Firecrawl context");
			const { web, news, images } = firecrawlSearchBuckets(data);
			const all = [...web, ...news, ...images];
			const fullText = [
				`Query: ${params.query}`,
				renderFirecrawlResultSection("Web", web),
				renderFirecrawlResultSection("News", news),
				renderFirecrawlResultSection("Images", images),
				data.warning ? `Warning: ${data.warning}` : "",
			].filter(Boolean).join("\n\n");
			const truncated = await truncateForTool(fullText, params.maxChars, "firecrawl-context");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: {
					query: params.query,
					id: data.id,
					creditsUsed: data.creditsUsed,
					warning: data.warning,
					urls: all.map((item: any) => item.url ?? item.imageUrl).filter(Boolean),
					sourceCount: all.length,
					truncation: truncated.truncation,
					fullOutputPath: truncated.fullOutputPath,
				},
			};
		},
	});

	pi.registerTool({
		name: "web_fetch",
		label: "Web Fetch",
		description: `Fetch/extract a page using Firecrawl v2. Output is truncated to ${formatSize(MAX_TOOL_BYTES)} or ${MAX_TOOL_LINES} lines; full truncated output is saved to a temp file.`,
		promptSnippet: "Fetch a URL with Firecrawl and return clean markdown, summary, links, answer, or highlights",
		promptGuidelines: [
			"Use web_fetch after web_search or web_context to read authoritative pages before answering with citations or implementation details.",
			"Use web_fetch output=summary, question, highlights, or links when full markdown would waste context.",
		],
		parameters: Type.Object({
			url: Type.String({ description: "HTTP(S) URL to fetch. Bare domains are normalized to https://." }),
			output: Type.Optional(StringEnum(["markdown", "summary", "links", "images", "html", "rawHtml", "screenshot", "question", "highlights", "json", "branding", "product"] as const, { description: "Output type. Default markdown. question/highlights/json can use query/jsonPrompt." })),
			query: Type.Optional(Type.String({ description: "Question, highlight query, or JSON extraction prompt." })),
			jsonPrompt: Type.Optional(Type.String({ description: "Prompt for output=json. Defaults to query if provided." })),
			jsonSchema: Type.Optional(Type.Any({ description: "JSON schema object for output=json." })),
			onlyMainContent: Type.Optional(Type.Boolean({ description: "Deterministically remove nav/footer/boilerplate before markdown. Default true." })),
			onlyCleanContent: Type.Optional(Type.Boolean({ description: "Use Firecrawl's beta LLM cleanup pass for residual boilerplate. Costs/latency may be higher." })),
			fresh: Type.Optional(Type.Boolean({ description: "Force a fresh scrape instead of Firecrawl cache (sets maxAge=0). Default false." })),
			maxAgeMs: Type.Optional(Type.Number({ description: "Use cached page if younger than this many ms. Firecrawl default is 2 days." })),
			minAgeMs: Type.Optional(Type.Number({ description: "Cache-only scrape if cached data exists at least this old; avoids fresh scrape." })),
			waitForMs: Type.Optional(Type.Number({ description: "Extra page-load wait in ms, 0-60000." })),
			timeoutMs: Type.Optional(Type.Number({ description: "Request timeout in ms, 1000-300000." })),
			mobile: Type.Optional(Type.Boolean({ description: "Emulate a mobile device. Default false." })),
			proxy: Type.Optional(StringEnum(["basic", "auto", "enhanced"] as const, { description: "Firecrawl proxy mode. auto may retry with enhanced and bill more credits." })),
			parsers: Type.Optional(Type.Array(StringEnum(["pdf"] as const), { description: "Parser types. PDF parser is enabled by default; empty not exposed here." })),
			locationCountry: Type.Optional(Type.String({ description: "Firecrawl location country, e.g. US." })),
			locationLanguages: Type.Optional(Type.Array(Type.String(), { description: "Firecrawl location languages, e.g. en-US." })),
			removeBase64Images: Type.Optional(Type.Boolean({ description: "Remove base64 images from markdown. Firecrawl default true." })),
			blockAds: Type.Optional(Type.Boolean({ description: "Block ads/cookie popups. Firecrawl default true." })),
			storeInCache: Type.Optional(Type.Boolean({ description: "Store result in Firecrawl cache. Default true; false for sensitive pages." })),
			lockdown: Type.Optional(Type.Boolean({ description: "Cache-only mode: no outbound request to target URL; zero retention by default." })),
			redactPII: Type.Optional(Type.Boolean({ description: "Redact PII from returned markdown." })),
			zeroDataRetention: Type.Optional(Type.Boolean({ description: "Request zero data retention if enabled for your Firecrawl team." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const targetUrl = normalizeHttpUrl(params.url);
			const output = params.output ?? "markdown";
			const formats: any[] = output === "question"
				? [{ type: "question", question: params.query ?? "Summarize the page's answer to the user's task." }]
				: output === "highlights"
					? [{ type: "highlights", query: params.query ?? "relevant passages" }]
					: output === "json"
						? [cleanObject({ type: "json", prompt: params.jsonPrompt ?? params.query, schema: params.jsonSchema })]
						: [output];

			const data: any = await firecrawlPost("/scrape", {
				url: targetUrl,
				formats,
				...firecrawlScrapeOptions(params),
			}, signal, "Firecrawl scrape");

			const page = data.data ?? data;
			const metadata = compactMetadata(page.metadata);
			const highlights = Array.isArray(page.highlights) ? page.highlights.map((h: unknown) => `- ${stringifyValue(h)}`).join("\n") : stringifyValue(page.highlights);
			const bodyText = output === "links"
				? stringifyValue(page.links ?? [])
				: output === "question"
					? `Question: ${params.query ?? "(default)"}\n\nAnswer: ${page.answer ?? page.markdown ?? ""}`
					: output === "highlights"
						? `Highlights for: ${params.query ?? "relevant passages"}\n\n${highlights || page.markdown || ""}`
						: output === "json"
							? stringifyValue(page.json ?? page.extract ?? page)
							: stringifyValue(page[output] ?? page.markdown ?? page.content ?? page.text ?? "");
			const header = cleanObject({
				title: metadata.title,
				url: metadata.url ?? targetUrl,
				sourceURL: metadata.sourceURL,
				statusCode: metadata.statusCode,
				cacheState: metadata.cacheState,
				creditsUsed: metadata.creditsUsed,
				warning: data.warning ?? page.warning,
			});
			const fullText = `${Object.entries(header).map(([key, value]) => `${key}: ${value}`).join("\n")}\n\n${bodyText}`.trim();
			const truncated = await truncateForTool(fullText, params.maxChars, "firecrawl-fetch");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: { url: targetUrl, output, metadata, warning: data.warning ?? page.warning, truncation: truncated.truncation, fullOutputPath: truncated.fullOutputPath },
			};
		},
	});

	pi.registerTool({
		name: "web_deep_search",
		label: "Web Deep Search",
		description: "Paid Firecrawl search. Can return just results, or search plus scraped summaries/markdown in one call. Use when Brave is rate-limited or you need Firecrawl categories/domain filters/content.",
		promptSnippet: "Search with Firecrawl and optionally scrape result content in one paid call",
		promptGuidelines: [
			"Use web_deep_search (Firecrawl Standard) when Brave Search is rate-limited, when you need GitHub/research/PDF category filters, or when a single paid search+scrape call is more efficient than many fetches.",
			"Use scrape=none for low-credit discovery; use scrape=summary/markdown when one search+scrape call is more efficient than many web_fetch calls.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query. Supports operators like site:, filetype:, intitle:, inurl:." }),
			limit: Type.Optional(Type.Number({ description: "Maximum results. Default 5, max 20 here to keep context/cost bounded." })),
			country: Type.Optional(Type.String({ description: "ISO country code. Default US." })),
			location: Type.Optional(Type.String({ description: "Geo location string, e.g. San Francisco,California,United States." })),
			tbs: Type.Optional(Type.String({ description: "Time filter, e.g. qdr:d, qdr:w, qdr:m, qdr:y, sbd:1,qdr:w, or cdr:1,cd_min:MM/DD/YYYY,cd_max:MM/DD/YYYY." })),
			sources: Type.Optional(Type.Array(StringEnum(["web", "news", "images"] as const), { description: "Firecrawl search sources. Default web." })),
			categories: Type.Optional(Type.Array(StringEnum(["github", "research", "pdf"] as const), { description: "Optional Firecrawl category filters." })),
			includeDomains: Type.Optional(Type.Array(Type.String(), { description: "Only include these hostnames. Cannot be used with excludeDomains." })),
			excludeDomains: Type.Optional(Type.Array(Type.String(), { description: "Exclude these hostnames. Cannot be used with includeDomains." })),
			scrape: Type.Optional(StringEnum(["none", "summary", "markdown"] as const, { description: "Whether to scrape result content. Default none." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const scrape = params.scrape ?? "none";
			const body: Record<string, unknown> = cleanObject({
				query: params.query,
				limit: clampNumber(params.limit, 5, 1, 20),
				country: params.country ?? "US",
				location: params.location,
				tbs: params.tbs,
				sources: params.sources,
				includeDomains: params.includeDomains,
				excludeDomains: params.excludeDomains,
				ignoreInvalidURLs: true,
				categories: params.categories?.map((type: string) => ({ type })),
				scrapeOptions: scrape === "none" ? undefined : { formats: [scrape], onlyMainContent: true },
			});
			const data: any = await firecrawlPost("/search", body, signal, "Firecrawl search");
			const { web, news, images } = firecrawlSearchBuckets(data);
			const all = [...web, ...news, ...images];
			const fullText = [
				`Query: ${params.query}`,
				renderFirecrawlResultSection("Web", web),
				renderFirecrawlResultSection("News", news),
				renderFirecrawlResultSection("Images", images),
				data.warning ? `Warning: ${data.warning}` : "",
			].filter(Boolean).join("\n\n");
			const truncated = await truncateForTool(fullText, params.maxChars, "firecrawl-search");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: {
					query: params.query,
					id: data.id,
					creditsUsed: data.creditsUsed,
					warning: data.warning,
					results: all.map((item: any) => cleanObject({ title: item.title, url: item.url, imageUrl: item.imageUrl, description: item.description ?? item.snippet, category: item.category, metadata: compactMetadata(item.metadata) })),
					truncation: truncated.truncation,
					fullOutputPath: truncated.fullOutputPath,
				},
			};
		},
	});

	pi.registerTool({
		name: "web_firecrawl_usage",
		label: "Firecrawl Usage",
		description: "Check Firecrawl team credits and scrape queue/concurrency status. Useful before expensive crawls or when Standard-plan limits may be involved.",
		promptSnippet: "Check Firecrawl remaining credits and queue/concurrency status",
		promptGuidelines: [
			"Use web_firecrawl_usage before broad Firecrawl crawls/batches or after Firecrawl 429/402 errors to understand credits and concurrency.",
		],
		parameters: Type.Object({
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const [creditResult, queueResult] = await Promise.allSettled([
				firecrawlGet("/team/credit-usage", signal, "Firecrawl credit usage"),
				firecrawlGet("/team/queue-status", signal, "Firecrawl queue status"),
			]);
			const details: Record<string, unknown> = {};
			const lines: string[] = ["Firecrawl team status"];

			if (creditResult.status === "fulfilled") {
				const credits: any = (creditResult.value as any).data ?? creditResult.value;
				details.credits = credits;
				lines.push("\n## Credits");
				lines.push(`Remaining: ${credits.remainingCredits ?? "unknown"}`);
				lines.push(`Plan credits: ${credits.planCredits ?? "unknown"}`);
				if (credits.billingPeriodStart) lines.push(`Billing period start: ${credits.billingPeriodStart}`);
				if (credits.billingPeriodEnd) lines.push(`Billing period end: ${credits.billingPeriodEnd}`);
			} else {
				const message = errorText(creditResult.reason);
				details.creditError = message;
				lines.push(`\n## Credits\nError: ${message}`);
			}

			if (queueResult.status === "fulfilled") {
				const queue: any = (queueResult.value as any).data ?? queueResult.value;
				details.queue = queue;
				lines.push("\n## Queue");
				lines.push(`Active jobs: ${queue.activeJobsInQueue ?? "unknown"}/${queue.maxConcurrency ?? "unknown"}`);
				lines.push(`Waiting jobs: ${queue.waitingJobsInQueue ?? "unknown"}`);
				lines.push(`Total queued jobs: ${queue.jobsInQueue ?? "unknown"}`);
				if (queue.mostRecentSuccess) lines.push(`Most recent success: ${queue.mostRecentSuccess}`);
			} else {
				const message = errorText(queueResult.reason);
				details.queueError = message;
				lines.push(`\n## Queue\nError: ${message}`);
			}

			const truncated = await truncateForTool(lines.join("\n"), params.maxChars, "firecrawl-usage");
			return { content: [{ type: "text", text: truncated.text }], details: { ...details, truncation: truncated.truncation, fullOutputPath: truncated.fullOutputPath } };
		},
	});

	pi.registerTool({
		name: "web_map",
		label: "Web Map",
		description: "Map a site/section with Firecrawl v2 and return URLs without scraping page content. Best before crawling docs or finding relevant pages cheaply.",
		promptSnippet: "Map a website with Firecrawl to discover URLs before fetching or crawling",
		promptGuidelines: ["Use web_map before web_crawl when you only need to discover relevant documentation URLs; then fetch the few pages that matter."],
		parameters: Type.Object({
			url: Type.String({ description: "Starting HTTP(S) URL. Bare domains are normalized to https://." }),
			search: Type.Optional(Type.String({ description: "Optional relevance query to order/filter URLs, e.g. auth, pricing, api reference." })),
			limit: Type.Optional(Type.Number({ description: "Maximum links. Default 50, max 500." })),
			sitemap: Type.Optional(StringEnum(["skip", "include", "only"] as const, { description: "Sitemap mode. Default include." })),
			includeSubdomains: Type.Optional(Type.Boolean({ description: "Include subdomains. Default true." })),
			ignoreQueryParameters: Type.Optional(Type.Boolean({ description: "Omit URLs with query parameters. Default true." })),
			ignoreCache: Type.Optional(Type.Boolean({ description: "Bypass sitemap cache for fresh mapping. Default false." })),
			timeoutMs: Type.Optional(Type.Number({ description: "Timeout in ms." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const targetUrl = normalizeHttpUrl(params.url);
			const data: any = await firecrawlPost("/map", cleanObject({
				url: targetUrl,
				search: params.search,
				limit: clampNumber(params.limit, 50, 1, 500),
				sitemap: params.sitemap,
				includeSubdomains: params.includeSubdomains,
				ignoreQueryParameters: params.ignoreQueryParameters,
				ignoreCache: params.ignoreCache,
				timeout: params.timeoutMs,
			}), signal, "Firecrawl map");
			const rawLinks = data.links ?? data.data?.links ?? [];
			const links = rawLinks.map((link: any) => typeof link === "string" ? { url: link } : cleanObject({ url: link.url, title: link.title, description: link.description }));
			const fullText = [`Mapped: ${targetUrl}`, `Links: ${links.length}`, ...links.map((link: any, index: number) => `${index + 1}. ${link.title ? `${link.title} — ` : ""}${link.url}${link.description ? `\n   ${link.description}` : ""}`)].join("\n");
			const truncated = await truncateForTool(fullText, params.maxChars, "firecrawl-map");
			return { content: [{ type: "text", text: truncated.text }], details: { url: targetUrl, links, truncation: truncated.truncation, fullOutputPath: truncated.fullOutputPath } };
		},
	});

	pi.registerTool({
		name: "web_crawl",
		label: "Web Crawl",
		description: "Start a paid Firecrawl v2 crawl for a documentation site or section. Keep limits small; prefer web_map plus targeted web_fetch when possible.",
		promptSnippet: "Start a Firecrawl docs/site crawl with small limits",
		promptGuidelines: ["Use web_crawl for multi-page documentation only when web_map plus targeted web_fetch is insufficient; keep limits small to control credits and context."],
		parameters: Type.Object({
			url: Type.String({ description: "Starting HTTP(S) URL. Bare domains are normalized to https://." }),
			limit: Type.Optional(Type.Number({ description: "Maximum pages to crawl. Default 5, max 25." })),
			maxDepth: Type.Optional(Type.Number({ description: "Maximum discovery depth. Default 2." })),
			prompt: Type.Optional(Type.String({ description: "Optional natural-language instruction for Firecrawl to generate crawl options." })),
			includePaths: Type.Optional(Type.Array(Type.String(), { description: "URL pathname regexes to include." })),
			excludePaths: Type.Optional(Type.Array(Type.String(), { description: "URL pathname regexes to exclude." })),
			sitemap: Type.Optional(StringEnum(["skip", "include", "only"] as const, { description: "Sitemap mode. Default include." })),
			ignoreQueryParameters: Type.Optional(Type.Boolean({ description: "Do not re-scrape same path with different query params." })),
			regexOnFullURL: Type.Optional(Type.Boolean({ description: "Match include/exclude regexes against full URL including query params." })),
			crawlEntireDomain: Type.Optional(Type.Boolean({ description: "Follow sibling/parent internal links, not only child paths. Default false." })),
			allowExternalLinks: Type.Optional(Type.Boolean({ description: "Allow external links. Default false." })),
			allowSubdomains: Type.Optional(Type.Boolean({ description: "Allow subdomains. Default false." })),
			delaySeconds: Type.Optional(Type.Number({ description: "Delay between scrapes in seconds; forces concurrency 1." })),
			maxConcurrency: Type.Optional(Type.Number({ description: "Maximum concurrent scrapes for this crawl." })),
			output: Type.Optional(StringEnum(["markdown", "summary", "links"] as const, { description: "Scrape format per page. Default markdown." })),
			onlyCleanContent: Type.Optional(Type.Boolean({ description: "Use Firecrawl LLM cleanup pass for each crawled page." })),
			zeroDataRetention: Type.Optional(Type.Boolean({ description: "Enable zero data retention if enabled for your Firecrawl team." })),
		}),
		async execute(_id, params, signal) {
			const targetUrl = normalizeHttpUrl(params.url);
			const limit = clampNumber(params.limit, 5, 1, 25);
			const scrapeOptions = cleanObject({ formats: [params.output ?? "markdown"], onlyMainContent: true, onlyCleanContent: params.onlyCleanContent });
			const data: any = await firecrawlPost("/crawl", cleanObject({
				url: targetUrl,
				prompt: params.prompt,
				limit,
				maxDiscoveryDepth: clampNumber(params.maxDepth, 2, 0, 10),
				includePaths: params.includePaths,
				excludePaths: params.excludePaths,
				sitemap: params.sitemap,
				ignoreQueryParameters: params.ignoreQueryParameters,
				regexOnFullURL: params.regexOnFullURL,
				crawlEntireDomain: params.crawlEntireDomain,
				allowExternalLinks: params.allowExternalLinks,
				allowSubdomains: params.allowSubdomains,
				delay: params.delaySeconds,
				maxConcurrency: params.maxConcurrency,
				zeroDataRetention: params.zeroDataRetention,
				scrapeOptions,
			}), signal, "Firecrawl crawl");
			const text = [`Started crawl for: ${targetUrl}`, `ID: ${data.id ?? "(none returned)"}`, data.url ? `Status URL: ${data.url}` : "", `Limit: ${limit}`].filter(Boolean).join("\n");
			return { content: [{ type: "text", text }], details: data };
		},
	});

	pi.registerTool({
		name: "web_crawl_preview",
		label: "Web Crawl Preview",
		description: "Preview Firecrawl crawl parameters generated from a natural-language prompt before spending crawl credits.",
		promptSnippet: "Preview Firecrawl smart-crawl params before starting a crawl",
		promptGuidelines: ["Use web_crawl_preview before web_crawl when relying on a natural-language crawl prompt or when crawl scope is unclear."],
		parameters: Type.Object({
			url: Type.String({ description: "URL to crawl. Bare domains are normalized to https://." }),
			prompt: Type.String({ description: "Natural-language prompt describing what to crawl." }),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const targetUrl = normalizeHttpUrl(params.url);
			const data: any = await firecrawlPost("/crawl/params-preview", { url: targetUrl, prompt: params.prompt }, signal, "Firecrawl crawl params preview");
			const text = JSON.stringify(data.data ?? data, null, 2);
			const truncated = await truncateForTool(text, params.maxChars, "firecrawl-crawl-preview");
			return { content: [{ type: "text", text: truncated.text }], details: { url: targetUrl, preview: data.data ?? data, truncation: truncated.truncation, fullOutputPath: truncated.fullOutputPath } };
		},
	});

	pi.registerTool({
		name: "web_crawl_status",
		label: "Web Crawl Status",
		description: "Check a Firecrawl v2 crawl job by id and return compact progress/results. If a next URL is returned, pass it as nextUrl for the next chunk.",
		promptSnippet: "Check Firecrawl crawl status/results by id",
		parameters: Type.Object({
			id: Type.String({ description: "Firecrawl crawl id returned by web_crawl" }),
			nextUrl: Type.Optional(Type.String({ description: "Optional next URL returned by a previous crawl status response." })),
			maxPages: Type.Optional(Type.Number({ description: "Maximum pages to include from this status response. Default 5, max 25." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const data: any = await firecrawlGet(params.nextUrl ? normalizeHttpUrl(params.nextUrl) : `/crawl/${encodeURIComponent(params.id)}`, signal, "Firecrawl crawl status");
			const maxPages = clampNumber(params.maxPages, 5, 1, 25);
			const pages = (data.data ?? []).slice(0, maxPages).map(crawlPageSummary);
			const lines = [
				`Crawl: ${params.id}`,
				`Status: ${data.status ?? "unknown"}`,
				data.total !== undefined ? `Progress: ${data.completed ?? 0}/${data.total}` : undefined,
				data.creditsUsed !== undefined ? `Credits used: ${data.creditsUsed}` : undefined,
				data.expiresAt ? `Expires: ${data.expiresAt}` : undefined,
				data.next ? `Next: ${data.next}` : undefined,
				pages.length ? "\n## Pages" : undefined,
			];
			pages.forEach((page: any, index: number) => {
				lines.push(`\n### ${index + 1}. ${page.title ?? page.url ?? "(untitled)"}`);
				if (page.url) lines.push(`URL: ${page.url}`);
				if (page.statusCode) lines.push(`Status code: ${page.statusCode}`);
				if (page.error) lines.push(`Error: ${page.error}`);
				if (page.description) lines.push(`Description: ${page.description}`);
				if (page.summary) lines.push(`\n${page.summary}`);
				else if (page.markdown) lines.push(`\n${page.markdown}`);
			});
			const truncated = await truncateForTool(lines.filter(Boolean).join("\n"), params.maxChars, "firecrawl-crawl");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: cleanObject({
					status: data.status,
					total: data.total,
					completed: data.completed,
					creditsUsed: data.creditsUsed,
					expiresAt: data.expiresAt,
					next: data.next,
					pages,
					truncation: truncated.truncation,
					fullOutputPath: truncated.fullOutputPath,
				}),
			};
		},
	});
}
