# Global pi instructions

- Prefer token-efficient shell output. For bash commands supported by RTK (for example `ls`, `tree`, `read`, `git`, `gh`, `find`, `grep`, `diff`, `test`, `pytest`, `npm`, `pnpm`, `tsc`, `docker`, `kubectl`, `curl`, `json`, logs), use `rtk <command>` instead of the raw command when you need command output in context.
- A global pi extension also auto-rewrites supported bash tool calls through `rtk rewrite`, so ordinary supported commands may be transparently converted to RTK wrappers.
