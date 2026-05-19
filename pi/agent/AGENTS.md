# Global pi instructions

- Prefer token-efficient shell output. For bash commands supported by RTK (for example `ls`, `tree`, `read`, `git`, `gh`, `find`, `grep`, `diff`, `test`, `pytest`, `npm`, `pnpm`, `tsc`, `docker`, `kubectl`, `curl`, `json`, logs), use `rtk <command>` instead of the raw command when you need command output in context.
- A global pi extension also auto-rewrites supported bash tool calls through `rtk rewrite`, so ordinary supported commands may be transparently converted to RTK wrappers.

## Web research tools

- Use `web_search` for current/up-to-date info, docs discovery, pricing, releases, errors, APIs, and anything likely changed after model training.
- Prefer authoritative sources: official docs, vendor blogs/changelogs, GitHub repos, standards bodies.
- After `web_search`, use `web_fetch` on the best source URLs before giving implementation details or citations.
- Use `web_crawl` only for multi-page docs when one `web_fetch` is insufficient; keep limits small.
- Use `web_crawl_status` when `web_crawl` returns an async crawl id.
- Never expose API keys or secret file contents.
- Summarize sources clearly and mention uncertainty when sources disagree.
