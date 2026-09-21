import assert from 'node:assert/strict';
import test from 'node:test';
import { harness } from './helpers/web-research-harness.mjs';

const names = ['EXA_API_KEY', 'FIRECRAWL_API_KEY', 'BRAVE_SEARCH_API_KEY', 'BRAVE_AI_API_KEY'];
const item = () => ({ fields: names.map(label => ({ label, type: 'CONCEALED', value: `test-${label}` })) });
function fixture(env = {}) {
  const calls = [];
  let response = item(), error;
  let now = 1000;
  const timers = [];
  const h = harness({
    process: { env }, Date: { now: () => now },
    setTimeout(fn, ms) { const timer = { fn, ms, unref() {} }; timers.push(timer); return timer; },
    clearTimeout() {},
    execFile(command, args, options, callback) {
      calls.push({ command, args, options });
      queueMicrotask(() => callback(error, typeof response === 'string' ? response : JSON.stringify(response)));
      return { stdin: { end() {} } };
    },
  });
  return { ...h, calls, timers, setResponse(value) { response = value; }, setError(value) { error = value; }, advance(ms) { now += ms; } };
}

test('lazy loading; concurrent requests share one bounded CLI call; cache rotates', async () => {
  const f = fixture();
  assert.equal(f.calls.length, 0);
  assert.equal(f.context.fetchProviderDisplay({}), 'auto (exa preferred)');
  assert.equal(f.calls.length, 0);
  const values = await Promise.all(names.map(name => f.context.secret(name)));
  assert.deepEqual(values, names.map(name => `test-${name}`));
  assert.equal(f.calls.length, 1);
  assert.deepEqual(Array.from(f.calls[0].args), ['item', 'get', '5vdjlcxrhqfegffhp2hxye6cle', '--vault', 'eiimzbiscziwayqhndjwh36tpy', '--format=json', '--reveal', '--account', 'FXKJFB4RCFFPHAHT4SRYTQDKSY']);
  assert.equal(f.calls[0].options.timeout, 30_000);
  assert.equal(f.calls[0].options.killSignal, 'SIGKILL');
  await f.context.secret(names[0]);
  assert.equal(f.calls.length, 1);
  const rotated = item(); rotated.fields[0].value = 'rotated'; f.setResponse(rotated);
  f.advance(300_001);
  assert.equal(await f.context.secret(names[0]), 'rotated');
  assert.equal(f.calls.length, 2);
  f.timers.at(-1).fn();
  await f.context.secret(names[0]);
  assert.equal(f.calls.length, 3);
});

test('service account overrides desktop/Connect; configurable non-secret IDs', async () => {
  const f = fixture({ OP_SERVICE_ACCOUNT_TOKEN: 'fake-token', OP_ACCOUNT: 'wrong', OP_CONNECT_HOST: 'wrong', OP_CONNECT_TOKEN: 'wrong', WEB_RESEARCH_OP_ITEM: 'item', WEB_RESEARCH_OP_VAULT: 'vault' });
  await f.context.secret(names[0]);
  const { args, options } = f.calls[0];
  assert.equal(args.includes('--account'), false);
  assert.equal(args[2], 'item'); assert.equal(args[4], 'vault');
  assert.equal(options.env.OP_ACCOUNT, undefined);
  assert.equal(options.env.OP_CONNECT_HOST, undefined);
  assert.equal(options.env.OP_CONNECT_TOKEN, undefined);
  assert.equal(options.env.OP_SERVICE_ACCOUNT_TOKEN, 'fake-token');
  assert.equal(options.env.OP_BIOMETRIC_UNLOCK_ENABLED, 'false');
});

test('CLI failures stay sanitized, retry after unlock, never use raw env keys', async () => {
  const f = fixture({ EXA_API_KEY: 'old-plaintext-key' });
  f.setError(Object.assign(new Error('secret-from-stderr'), { code: 'ENOENT' }));
  await assert.rejects(f.context.secret(names[0], false), e => /Install 1Password CLI/.test(e.message) && !String(e).includes('secret-from-stderr') && !e.cause);
  f.setError(Object.assign(new Error('secret-from-stderr'), { killed: true }));
  await assert.rejects(f.context.secret(names[0]), /Unlock\/sign in/);
  f.setError(undefined);
  assert.equal(await f.context.secret(names[0]), `test-${names[0]}`);
  assert.equal(f.calls.length, 3);
});

test('rejects malformed, duplicate, plaintext, and whitespace values without leaking output', async () => {
  for (const bad of ['secret-invalid-json', {}, { fields: [null] }, { fields: [item().fields[0], item().fields[0]] }, { fields: [{ label: names[0], type: 'STRING', value: 'secret' }] }, { fields: [{ label: names[0], type: 'CONCEALED', value: 'secret with whitespace' }] }]) {
    const f = fixture(); f.setResponse(bad);
    await assert.rejects(f.context.secret(names[0]), e => e.message.startsWith('Invalid 1Password web research item:') && !e.message.includes('secret'));
  }
});

test('missing optional key stays optional; required key reports field name', async () => {
  const f = fixture(); f.setResponse({ fields: [] });
  assert.equal(await f.context.secret(names[0], false), undefined);
  await assert.rejects(f.context.secret(names[0]), /Missing EXA_API_KEY/);
});

test('provider requests receive resolved headers for all four fields', async () => {
  const f = fixture(); const requests = [];
  f.context.fetch = async (url, init) => { requests.push({ url, init }); return { ok: true, text: async () => '{}' }; };
  await f.context.exa('/search', {}, undefined, 'Exa');
  await f.context.firecrawl('POST', '/search', {}, undefined, 'Firecrawl');
  await f.context.braveRequestWithLocation(new URL('https://api.search.brave.com/res/v1/web/search'), undefined, false, {});
  await f.context.braveRequestWithLocation(new URL('https://api.search.brave.com/res/v1/web/search'), undefined, true, {});
  assert.equal(requests[0].init.headers['x-api-key'], 'test-EXA_API_KEY');
  assert.equal(requests[1].init.headers.Authorization, 'Bearer test-FIRECRAWL_API_KEY');
  assert.equal(requests[2].init.headers['X-Subscription-Token'], 'test-BRAVE_SEARCH_API_KEY');
  assert.equal(requests[3].init.headers['X-Subscription-Token'], 'test-BRAVE_AI_API_KEY');
  assert.equal(f.calls.length, 1);
});

test('auto search awaits availability and routes missing Exa to Firecrawl', async () => {
  const f = fixture(); f.setResponse({ fields: item().fields.filter(field => field.label !== 'EXA_API_KEY') });
  const requests = [];
  f.context.fetch = async (url, init) => { requests.push({ url, init }); return { ok: true, text: async () => JSON.stringify({ success: true, data: { web: [{ title: 'Example', url: 'https://example.com', description: 'Example' }] } }) }; };
  await f.registered.get('web_search').execute('test', { query: 'example', limit: 1 }, undefined);
  assert.equal(requests.length, 1);
  assert.equal(new URL(requests[0].url).hostname, 'api.firecrawl.dev');
});

test('expired cache fails closed when 1Password becomes unavailable', async () => {
  const f = fixture();
  await f.context.secret(names[0]);
  f.advance(300_001);
  f.setError(new Error('locked'));
  await assert.rejects(f.context.secret(names[0], false), /could not read 1Password/);
});

test('missing Brave AI field falls back to the shared Search field', async () => {
  const f = fixture(); f.setResponse({ fields: item().fields.filter(field => field.label !== 'BRAVE_AI_API_KEY') });
  let headers;
  f.context.fetch = async (_url, init) => { headers = init.headers; return { ok: true, text: async () => '{}' }; };
  await f.context.braveRequestWithLocation(new URL('https://api.search.brave.com/res/v1/web/search'), undefined, true, {});
  assert.equal(headers['X-Subscription-Token'], 'test-BRAVE_SEARCH_API_KEY');
});

test('auto fetch awaits missing Exa before choosing Firecrawl', async () => {
  const f = fixture(); f.setResponse({ fields: item().fields.filter(field => field.label !== 'EXA_API_KEY') });
  const requests = [];
  f.context.fetch = async (url, init) => { requests.push({ url, init }); return { ok: true, text: async () => JSON.stringify({ success: true, data: { markdown: 'Example', metadata: { title: 'Example' } } }) }; };
  await f.registered.get('web_fetch').execute('test', { url: 'https://example.com' }, undefined);
  assert.equal(requests.length, 1);
  assert.equal(new URL(requests[0].url).hostname, 'api.firecrawl.dev');
});
