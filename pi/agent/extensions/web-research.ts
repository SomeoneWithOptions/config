import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const BRAVE_KEY_FILE = join(homedir(), ".pi", "agent", "secrets", "brave-api-key");
const FIRECRAWL_KEY_FILE = join(homedir(), ".pi", "agent", "secrets", "firecrawl-api-key");
const MAX_RESULT_CHARS = 50_000;

function readSecret(envName: string, file: string) {
	const value = process.env[envName] || readFileSync(file, "utf8");
	const cleaned = value.replace(/\s+/g, "");
	if (!cleaned) throw new Error(`Missing ${envName} or ${file}`);
	return cleaned;
}

function truncateText(text: string, max = MAX_RESULT_CHARS) {
	return text.length > max ? `${text.slice(0, max)}\n\n[Truncated to ${max} characters]` : text;
}

function summarizeJson(value: unknown, max = MAX_RESULT_CHARS) {
	return truncateText(JSON.stringify(value, null, 2), max);
}

async function fetchJson(url: string, init: RequestInit, service: string) {
	const response = await fetch(url, init);
	const raw = await response.text();
	let data: unknown = raw;
	try { data = raw ? JSON.parse(raw) : null; } catch { /* keep raw */ }
	if (!response.ok) {
		const body = typeof data === "string" ? data : JSON.stringify(data);
		throw new Error(`${service} ${response.status} ${response.statusText}: ${body.slice(0, 1000)}`);
	}
	return data;
}

function assertHttpUrl(url: string) {
	const parsed = new URL(url);
	if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("Only http(s) URLs are allowed");
	return parsed.toString();
}

export default function webResearchExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description: "Search the live web using Brave Search. Best for current information, documentation discovery, news, pricing, releases, and finding authoritative URLs.",
		promptSnippet: "Search the live web with Brave Search for up-to-date information and source URLs",
		promptGuidelines: [
			"Use web_search when the user asks for current/up-to-date information or when documentation may have changed after model training.",
			"Prefer authoritative sources in web_search results: official docs, vendor blogs, GitHub repos, changelogs, standards bodies.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Search query" }),
			count: Type.Optional(Type.Number({ description: "Number of results, 1-20. Default 10." })),
			country: Type.Optional(Type.String({ description: "2-letter country code, e.g. US. Default US." })),
			freshness: Type.Optional(Type.String({ description: "Optional recency filter supported by Brave, e.g. pd, pw, pm, py, or date range." })),
		}),
		async execute(_id, params, signal) {
			const apiKey = readSecret("BRAVE_API_KEY", BRAVE_KEY_FILE);
			const url = new URL("https://api.search.brave.com/res/v1/web/search");
			url.searchParams.set("q", params.query);
			url.searchParams.set("count", String(Math.min(Math.max(params.count ?? 10, 1), 20)));
			url.searchParams.set("country", params.country ?? "US");
			if (params.freshness) url.searchParams.set("freshness", params.freshness);
			const data: any = await fetchJson(url.toString(), {
				headers: { "X-Subscription-Token": apiKey, Accept: "application/json" },
				signal,
			}, "Brave Search");
			const results = (data.web?.results ?? []).map((r: any) => ({
				title: r.title,
				url: r.url,
				description: r.description,
				age: r.age,
				profile: r.profile?.name,
			}));
			return { content: [{ type: "text", text: summarizeJson({ query: params.query, results }) }], details: { query: params.query, results } };
		},
	});

	pi.registerTool({
		name: "web_fetch",
		label: "Web Fetch",
		description: "Fetch and extract a web page as clean markdown using Firecrawl. Best after web_search finds a URL, or for reading docs/articles/pages.",
		promptSnippet: "Fetch a URL with Firecrawl and return clean markdown/text plus metadata",
		promptGuidelines: ["Use web_fetch after web_search to read authoritative pages before answering with citations or implementation details."],
		parameters: Type.Object({
			url: Type.String({ description: "HTTP(S) URL to fetch" }),
			onlyMainContent: Type.Optional(Type.Boolean({ description: "Extract only main content. Default true." })),
			maxChars: Type.Optional(Type.Number({ description: "Max characters to return. Default 50000." })),
		}),
		async execute(_id, params, signal) {
			const apiKey = readSecret("FIRECRAWL_API_KEY", FIRECRAWL_KEY_FILE);
			const targetUrl = assertHttpUrl(params.url);
			const data: any = await fetchJson("https://api.firecrawl.dev/v1/scrape", {
				method: "POST",
				headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json", Accept: "application/json" },
				body: JSON.stringify({ url: targetUrl, formats: ["markdown"], onlyMainContent: params.onlyMainContent ?? true }),
				signal,
			}, "Firecrawl scrape");
			const page = data.data ?? data;
			const text = page.markdown || page.content || page.text || "";
			const result = { url: targetUrl, title: page.metadata?.title, description: page.metadata?.description, markdown: truncateText(text, params.maxChars ?? MAX_RESULT_CHARS), metadata: page.metadata };
			return { content: [{ type: "text", text: summarizeJson(result, params.maxChars ?? MAX_RESULT_CHARS) }], details: result };
		},
	});

	pi.registerTool({
		name: "web_crawl",
		label: "Web Crawl",
		description: "Start a Firecrawl crawl for a documentation site or section. Returns either pages or a crawl id; use web_crawl_status if an id is returned.",
		promptSnippet: "Start a Firecrawl docs/site crawl with small limits",
		promptGuidelines: ["Use web_crawl for multi-page documentation only when a single web_fetch is insufficient; keep limits small."],
		parameters: Type.Object({
			url: Type.String({ description: "Starting HTTP(S) URL" }),
			limit: Type.Optional(Type.Number({ description: "Maximum pages to crawl. Default 5, max 25." })),
			maxDepth: Type.Optional(Type.Number({ description: "Maximum crawl depth. Default 2." })),
		}),
		async execute(_id, params, signal) {
			const apiKey = readSecret("FIRECRAWL_API_KEY", FIRECRAWL_KEY_FILE);
			const targetUrl = assertHttpUrl(params.url);
			const limit = Math.min(Math.max(params.limit ?? 5, 1), 25);
			const data: any = await fetchJson("https://api.firecrawl.dev/v1/crawl", {
				method: "POST",
				headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json", Accept: "application/json" },
				body: JSON.stringify({ url: targetUrl, limit, maxDepth: params.maxDepth ?? 2, scrapeOptions: { formats: ["markdown"], onlyMainContent: true } }),
				signal,
			}, "Firecrawl crawl");
			return { content: [{ type: "text", text: summarizeJson(data) }], details: data };
		},
	});

	pi.registerTool({
		name: "web_crawl_status",
		label: "Web Crawl Status",
		description: "Check a Firecrawl crawl job by id and return crawl progress/results.",
		promptSnippet: "Check Firecrawl crawl status/results by id",
		parameters: Type.Object({ id: Type.String({ description: "Firecrawl crawl id returned by web_crawl" }) }),
		async execute(_id, params, signal) {
			const apiKey = readSecret("FIRECRAWL_API_KEY", FIRECRAWL_KEY_FILE);
			const data: any = await fetchJson(`https://api.firecrawl.dev/v1/crawl/${encodeURIComponent(params.id)}`, {
				headers: { Authorization: `Bearer ${apiKey}`, Accept: "application/json" },
				signal,
			}, "Firecrawl crawl status");
			return { content: [{ type: "text", text: summarizeJson(data) }], details: data };
		},
	});
}
