# config

Dotfiles and machine setup for **Omarchy** (Arch) and **macOS**.

```sh
curl -fsSL https://go.sanetomore.com/config | sh
```

Pi web-research keys live in separate 1Password `development` items: `Exa API`
(`EXA_API_KEY`), `Firecrawl API` (`FIRECRAWL_API_KEY`), and `Brave API`
(`BRAVE_SEARCH_API_KEY`, optional `BRAVE_AI_API_KEY`). Each service loads/caches its
own item for five minutes. Item IDs survive renames. Override account/vault with
`WEB_RESEARCH_OP_ACCOUNT` / `WEB_RESEARCH_OP_VAULT`; override individual item IDs
with `WEB_RESEARCH_OP_EXA_ITEM`, `WEB_RESEARCH_OP_FIRECRAWL_ITEM`, or
`WEB_RESEARCH_OP_BRAVE_ITEM` (replaces shared `WEB_RESEARCH_OP_ITEM`).
