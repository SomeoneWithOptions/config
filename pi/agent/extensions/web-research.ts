import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { DEFAULT_MAX_BYTES, DEFAULT_MAX_LINES, formatSize, truncateHead } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { existsSync, readFileSync } from "node:fs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { Type } from "typebox";

const BRAVE_KEY_FILE = join(homedir(), ".pi", "agent", "secrets", "brave-api-key");
const FIRECRAWL_KEY_FILE = join(homedir(), ".pi", "agent", "secrets", "firecrawl-api-key");
const FIRECRAWL_BASE = "https://api.firecrawl.dev/v2";
const MAX_TOOL_BYTES = DEFAULT_MAX_BYTES;
const MAX_TOOL_LINES = DEFAULT_MAX_LINES;
const BRAVE_MIN_INTERVAL_MS = 1100; // Free Brave plans use a 1s sliding rate window.

const secretCache = new Map<string, string>();
let braveQueue: Promise<void> = Promise.resolve();

function readSecret(envName: string, file: string) {
	const cached = secretCache.get(envName);
	if (cached) return cached;

	const raw = process.env[envName] ?? (existsSync(file) ? readFileSync(file, "utf8") : "");
	const cleaned = raw.replace(/\s+/g, "");
	if (!cleaned) throw new Error(`Missing ${envName}; set the env var or create ${file}`);
	secretCache.set(envName, cleaned);
	return cleaned;
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

async function withBraveRateLimit<T>(fn: () => Promise<T>) {
	const previous = braveQueue;
	let release!: () => void;
	braveQueue = new Promise<void>((resolve) => { release = resolve; });
	await previous;
	try {
		return await fn();
	} finally {
		setTimeout(release, BRAVE_MIN_INTERVAL_MS);
	}
}

async function braveJson(url: URL, signal: AbortSignal | undefined, service: string) {
	const apiKey = readSecret("BRAVE_API_KEY", BRAVE_KEY_FILE);
	return withBraveRateLimit(() => fetchJson(url.toString(), {
		headers: { "X-Subscription-Token": apiKey, Accept: "application/json" },
		signal,
	}, service, 2));
}

function firecrawlHeaders() {
	const apiKey = readSecret("FIRECRAWL_API_KEY", FIRECRAWL_KEY_FILE);
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
	if (params.waitForMs !== undefined) options.waitFor = clampNumber(params.waitForMs, 0, 0, 60_000);
	if (params.timeoutMs !== undefined) options.timeout = clampNumber(params.timeoutMs, 60_000, 1000, 300_000);
	if (params.mobile !== undefined) options.mobile = params.mobile;
	if (params.proxy) options.proxy = params.proxy;
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
		description: "Search the live web using Brave Web Search. Returns compact source URLs/snippets only; use web_context or web_fetch for page content.",
		promptSnippet: "Search the live web with Brave Search for up-to-date source URLs",
		promptGuidelines: [
			"Use web_search for cheap/current URL discovery before fetching pages; prefer authoritative sources such as official docs, vendor blogs, GitHub repos, changelogs, and standards bodies.",
			"Use web_context when snippets are enough, and web_fetch when you need full source content from a specific URL.",
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

			const data: any = await braveJson(url, signal, "Brave Search");
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
			return { content: [{ type: "text", text }], details: { query: queryInfo, results } };
		},
	});

	pi.registerTool({
		name: "web_context",
		label: "Web Context",
		description: "Search using Brave LLM Context and return extracted snippets optimized for AI grounding. Best when you need answer-ready context without fetching pages one by one.",
		promptSnippet: "Get Brave LLM Context snippets for quick AI-grounded web research",
		promptGuidelines: [
			"Use web_context for quick web grounding when snippets are enough; it can replace web_search plus several web_fetch calls.",
			"Use web_fetch after web_context only for sources that need verification, exact quotes, or fuller content.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query." }),
			count: Type.Optional(Type.Number({ description: "Search results to consider, 1-50. Default 10." })),
			maxUrls: Type.Optional(Type.Number({ description: "Maximum URLs returned, 1-50. Default 8." })),
			maxTokens: Type.Optional(Type.Number({ description: "Approximate Brave context token budget, 1024-32768. Default 4096." })),
			country: Type.Optional(Type.String({ description: "2-letter country code. Default US." })),
			searchLang: Type.Optional(Type.String({ description: "Search language, e.g. en." })),
			freshness: Type.Optional(Type.String({ description: "Recency filter: pd, pw, pm, py, or YYYY-MM-DDtoYYYY-MM-DD." })),
			threshold: Type.Optional(StringEnum(["strict", "balanced", "lenient", "disabled"] as const, { description: "Relevance threshold. Default balanced." })),
			goggles: Type.Optional(Type.String({ description: "Optional Brave Goggle URL or inline definition for trusted-source ranking." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const url = new URL("https://api.search.brave.com/res/v1/llm/context");
			setSearchParam(url, "q", params.query);
			setSearchParam(url, "count", clampNumber(params.count, 10, 1, 50));
			setSearchParam(url, "maximum_number_of_urls", clampNumber(params.maxUrls, 8, 1, 50));
			setSearchParam(url, "maximum_number_of_tokens", clampNumber(params.maxTokens, 4096, 1024, 32768));
			setSearchParam(url, "country", params.country ?? "US");
			setSearchParam(url, "search_lang", params.searchLang);
			setSearchParam(url, "freshness", params.freshness);
			setSearchParam(url, "context_threshold_mode", params.threshold ?? "balanced");
			setSearchParam(url, "goggles", params.goggles);

			const data: any = await braveJson(url, signal, "Brave LLM Context");
			const generic = Array.isArray(data.grounding?.generic) ? data.grounding.generic : [];
			const map = Array.isArray(data.grounding?.map) ? data.grounding.map : [];
			const poi = data.grounding?.poi ? [data.grounding.poi] : [];
			const all = [...generic, ...poi, ...map];
			const rendered = [`Query: ${params.query}`];
			all.forEach((item: any, index: number) => {
				rendered.push(`\n## ${index + 1}. ${item.title ?? item.name ?? "(untitled)"}`);
				if (item.url) rendered.push(`URL: ${item.url}`);
				for (const snippet of item.snippets ?? []) rendered.push(`- ${snippet}`);
			});
			const truncated = await truncateForTool(rendered.join("\n"), params.maxChars, "brave-context");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: {
					query: params.query,
					urls: all.map((item: any) => item.url).filter(Boolean),
					sourceCount: Object.keys(data.sources ?? {}).length,
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
			output: Type.Optional(StringEnum(["markdown", "summary", "links", "question", "highlights"] as const, { description: "Output type. Default markdown. question/highlights require query." })),
			query: Type.Optional(Type.String({ description: "Question or highlight query when output is question/highlights." })),
			onlyMainContent: Type.Optional(Type.Boolean({ description: "Deterministically remove nav/footer/boilerplate before markdown. Default true." })),
			onlyCleanContent: Type.Optional(Type.Boolean({ description: "Use Firecrawl's beta LLM cleanup pass for residual boilerplate. Costs/latency may be higher." })),
			fresh: Type.Optional(Type.Boolean({ description: "Force a fresh scrape instead of Firecrawl cache (sets maxAge=0). Default false." })),
			maxAgeMs: Type.Optional(Type.Number({ description: "Use cached page if younger than this many ms. Firecrawl default is 2 days." })),
			waitForMs: Type.Optional(Type.Number({ description: "Extra page-load wait in ms, 0-60000." })),
			timeoutMs: Type.Optional(Type.Number({ description: "Request timeout in ms, 1000-300000." })),
			mobile: Type.Optional(Type.Boolean({ description: "Emulate a mobile device. Default false." })),
			proxy: Type.Optional(StringEnum(["basic", "auto", "enhanced"] as const, { description: "Firecrawl proxy mode. auto may retry with enhanced and bill more credits." })),
			maxChars: Type.Optional(Type.Number({ description: `Max output bytes/chars. Hard capped at ${formatSize(MAX_TOOL_BYTES)} / ${MAX_TOOL_LINES} lines.` })),
		}),
		async execute(_id, params, signal) {
			const targetUrl = normalizeHttpUrl(params.url);
			const output = params.output ?? "markdown";
			const formats: any[] = output === "question"
				? [{ type: "question", question: params.query ?? "Summarize the page's answer to the user's task." }]
				: output === "highlights"
					? [{ type: "highlights", query: params.query ?? "relevant passages" }]
					: [output];

			const data: any = await firecrawlPost("/scrape", {
				url: targetUrl,
				formats,
				...firecrawlScrapeOptions(params),
			}, signal, "Firecrawl scrape");

			const page = data.data ?? data;
			const metadata = compactMetadata(page.metadata);
			const bodyText = output === "links"
				? (page.links ?? []).join("\n")
				: output === "summary"
					? (page.summary ?? "")
					: output === "question"
						? `Question: ${params.query ?? "(default)"}\n\nAnswer: ${page.answer ?? page.markdown ?? ""}`
						: output === "highlights"
							? `Highlights for: ${params.query ?? "relevant passages"}\n\n${(page.highlights ?? []).map((h: string) => `- ${h}`).join("\n") || page.markdown || ""}`
							: (page.markdown ?? page.content ?? page.text ?? "");
			const header = cleanObject({
				title: metadata.title,
				url: metadata.url ?? targetUrl,
				sourceURL: metadata.sourceURL,
				statusCode: metadata.statusCode,
				cacheState: metadata.cacheState,
				creditsUsed: metadata.creditsUsed,
			});
			const fullText = `${Object.entries(header).map(([key, value]) => `${key}: ${value}`).join("\n")}\n\n${bodyText}`.trim();
			const truncated = await truncateForTool(fullText, params.maxChars, "firecrawl-fetch");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: { url: targetUrl, output, metadata, truncation: truncated.truncation, fullOutputPath: truncated.fullOutputPath },
			};
		},
	});

	pi.registerTool({
		name: "web_deep_search",
		label: "Web Deep Search",
		description: "Paid Firecrawl search. Can return just results, or search plus scraped summaries/markdown in one call. Use when Brave is rate-limited or you need Firecrawl categories/domain filters/content.",
		promptSnippet: "Search with Firecrawl and optionally scrape result content in one paid call",
		promptGuidelines: [
			"Use web_deep_search when Brave search is rate-limited, when you need GitHub/research/PDF category filters, or when a single paid search+scrape call is more efficient than many fetches.",
			"Prefer web_search for cheap URL discovery and web_context for free snippet grounding before using paid web_deep_search.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query. Supports operators like site:, filetype:, intitle:, inurl:." }),
			limit: Type.Optional(Type.Number({ description: "Maximum results. Default 5, max 20 here to keep context/cost bounded." })),
			country: Type.Optional(Type.String({ description: "ISO country code. Default US." })),
			location: Type.Optional(Type.String({ description: "Geo location string, e.g. San Francisco,California,United States." })),
			tbs: Type.Optional(Type.String({ description: "Time filter, e.g. qdr:d, qdr:w, qdr:m, qdr:y, sbd:1,qdr:w, or cdr:1,cd_min:MM/DD/YYYY,cd_max:MM/DD/YYYY." })),
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
				includeDomains: params.includeDomains,
				excludeDomains: params.excludeDomains,
				ignoreInvalidURLs: true,
				categories: params.categories?.map((type: string) => ({ type })),
				scrapeOptions: scrape === "none" ? undefined : { formats: [scrape], onlyMainContent: true },
			});
			const data: any = await firecrawlPost("/search", body, signal, "Firecrawl search");
			const web = data.data?.web ?? data.web ?? [];
			const news = data.data?.news ?? data.news ?? [];
			const renderFirecrawl = (name: string, items: any[]) => {
				if (!items.length) return "";
				const lines = [`## ${name}`];
				items.forEach((item, index) => {
					lines.push(`${index + 1}. ${item.title ?? "(untitled)"}`);
					if (item.url) lines.push(`   URL: ${item.url}`);
					if (item.description ?? item.snippet) lines.push(`   ${shortSnippet(item.description ?? item.snippet)}`);
					if (item.category) lines.push(`   Category: ${item.category}`);
					const content = item.summary ?? item.markdown;
					if (content) lines.push(`\n${content}\n`);
				});
				return lines.join("\n");
			};
			const fullText = [`Query: ${params.query}`, renderFirecrawl("Web", web), renderFirecrawl("News", news), data.warning ? `Warning: ${data.warning}` : ""].filter(Boolean).join("\n\n");
			const truncated = await truncateForTool(fullText, params.maxChars, "firecrawl-search");
			return {
				content: [{ type: "text", text: truncated.text }],
				details: {
					query: params.query,
					id: data.id,
					creditsUsed: data.creditsUsed,
					warning: data.warning,
					results: [...web, ...news].map((item: any) => cleanObject({ title: item.title, url: item.url, description: item.description ?? item.snippet, category: item.category, metadata: compactMetadata(item.metadata) })),
					truncation: truncated.truncation,
					fullOutputPath: truncated.fullOutputPath,
				},
			};
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
			crawlEntireDomain: Type.Optional(Type.Boolean({ description: "Follow sibling/parent internal links, not only child paths. Default false." })),
			allowExternalLinks: Type.Optional(Type.Boolean({ description: "Allow external links. Default false." })),
			allowSubdomains: Type.Optional(Type.Boolean({ description: "Allow subdomains. Default false." })),
		}),
		async execute(_id, params, signal) {
			const targetUrl = normalizeHttpUrl(params.url);
			const limit = clampNumber(params.limit, 5, 1, 25);
			const data: any = await firecrawlPost("/crawl", cleanObject({
				url: targetUrl,
				prompt: params.prompt,
				limit,
				maxDiscoveryDepth: clampNumber(params.maxDepth, 2, 0, 10),
				includePaths: params.includePaths,
				excludePaths: params.excludePaths,
				sitemap: params.sitemap,
				crawlEntireDomain: params.crawlEntireDomain,
				allowExternalLinks: params.allowExternalLinks,
				allowSubdomains: params.allowSubdomains,
				scrapeOptions: { formats: ["markdown"], onlyMainContent: true },
			}), signal, "Firecrawl crawl");
			const text = [`Started crawl for: ${targetUrl}`, `ID: ${data.id ?? "(none returned)"}`, data.url ? `Status URL: ${data.url}` : "", `Limit: ${limit}`].filter(Boolean).join("\n");
			return { content: [{ type: "text", text }], details: data };
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
