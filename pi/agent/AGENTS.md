# Global pi instructions

- Prefer token-efficient shell output. For bash commands supported by RTK (for example `ls`, `tree`, `read`, `git`, `gh`, `find`, `grep`, `diff`, `test`, `pytest`, `npm`, `pnpm`, `tsc`, `docker`, `kubectl`, `curl`, `json`, logs), use `rtk <command>` instead of the raw command when you need command output in context.
- A global pi extension also auto-rewrites supported bash tool calls through `rtk rewrite`, so ordinary supported commands may be transparently converted to RTK wrappers.

## Web research tools

- Firecrawl is on the Standard plan; use Firecrawl tools (`web_context`, `web_fetch`, `web_deep_search`, `web_map`, `web_crawl`) for content extraction, grounding, and cases where Brave coverage/quota is insufficient. Prefer cache-friendly defaults; force `fresh` only when freshness matters.
- Brave is Free/Free AI only. Use `web_search` for lightweight current URL discovery with precise queries, small `count`, targeted `resultFilter`, `site:`/`filetype:` operators, and pagination only when needed. Set `extraSnippets=true` when snippets may be enough; this uses the Brave Free AI/Data for AI key and can avoid a Firecrawl fetch.
- Use `web_brave_context` sparingly only if explicitly available via a Brave LLM Context-capable key; Free AI/Data for AI is for `web_search` extra snippets. Fall back to `web_search` + Firecrawl on quota/plan errors.
- Prefer authoritative sources: official docs, vendor blogs/changelogs, GitHub repos, standards bodies.
- After URL discovery, use `web_fetch` on the best source URLs before giving implementation details or citations.
- Use `web_map` before `web_crawl` to discover relevant docs cheaply; use `web_crawl` only for multi-page docs when targeted fetches are insufficient, and keep limits small.
- Use `web_crawl_status` when `web_crawl` returns an async crawl id. Use `web_firecrawl_usage` before broad crawls/batches or after Firecrawl 429/402 errors.
- Never expose API keys or secret file contents.
- Summarize sources clearly and mention uncertainty when sources disagree.
