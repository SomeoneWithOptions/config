import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

// Exercise the complete extension without installing Pi's bundled UI dependencies.
const source = readFileSync(new URL('../../agents/pi/agent/extensions/web-research.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source.replace(/^import .*;\n/gm, '').replace('export default ', ''));
export function harness(overrides = {}) {
  const registered = new Map();
  const context = vm.createContext({
    process: { env: {} }, Date, URL, Headers, AbortController,
    setTimeout, clearTimeout,
    DEFAULT_MAX_BYTES: 50_000, DEFAULT_MAX_LINES: 2000,
    Type: new Proxy({}, { get: () => (...args) => args }),
    StringEnum: (...args) => args,
    Text: class { constructor(text) { this.text = text; } },
    formatSize: String,
    truncateHead: text => ({ content: text, truncated: false }),
    ...overrides,
  });
  vm.runInContext(code, context);
  context.webResearchExtension({ registerTool: tool => registered.set(tool.name, tool) });
  return { context, registered };
}
