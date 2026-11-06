import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import vm from "node:vm";

const require = createRequire(import.meta.url);
const menu = require("../system/omarchy/plugins/andres.menu/MenuModel.js");
const source = (plugin, file) => readFileSync(new URL(`../system/omarchy/plugins/${plugin}/${file}`, import.meta.url), "utf8");

// Run QML JS libraries with their imports, without a live notification daemon.
const libraries = new Map();
function library(name) {
  if (libraries.has(name)) return libraries.get(name);
  let text = source("andres.notifications", name);
  const scope = vm.createContext({ console });
  libraries.set(name, scope);
  text = text.replace(/^\.pragma library\s*$/gm, "").replace(/^\.import "([^"]+)" as (\w+)\s*$/gm, (_, file, alias) => {
    scope[alias] = library(file);
    return "";
  });
  vm.runInContext(text, scope, { filename: name });
  return scope;
}
const loom = library("Loom.js"), store = library("Store.js");

const installed = menu.normalizeItem("install.example", { label: "Example", disabled: "true" });
const disabled = { "install.example": true };
assert.equal(menu.isDisabled(disabled, installed), true);
assert.equal(menu.labelFor(installed, {}, disabled), "Example ✓");
assert.equal(menu.displayRow({ [installed.id]: installed }, [installed.id], {}, disabled, installed).disabled, true);
assert.match(menu.guardScript({ [installed.id]: installed }), /install.example:d:1/);
assert.deepEqual(menu.summonAction("omarchy-shell shell summon omarchy.speedtest"), { id: "omarchy.speedtest", payload: "{}" });
assert.equal(menu.summonAction("omarchy-shell shell summon omarchy.speedtest && echo done"), null);

const recording = { version: 1, videoPath: "/home/test/Videos/a 'quoted' recording.mp4", accent: "#aabbcc" };
const snapshot = store.snapshot({ id: 7, appName: "Loom", summary: "Recording", hints: { "x-loom-recording": JSON.stringify(recording) } }, "a", { Normal: 1 });
assert.equal(loom.parseLoomRecording(snapshot.loomRecording).videoPath, recording.videoPath);
const saved = store.persistable(snapshot);
assert.equal(loom.parseLoomRecording(store.restored(saved).loomRecording).videoPath, recording.videoPath);
assert.equal(store.restored(saved).duration, 0);
assert.equal(store.normalise({ loomRecording: '{"version":1,"videoPath":"relative","accent":"#aabbcc"}' }).loomRecording, "");
assert.equal(loom.parseLoomRecording({ ...recording, videoPath: "/a\0b" }), null);
assert.equal(loom.parseLoomRecording({ ...recording, accent: "javascript:alert(1)" }), null);

const toast = { key: "a", app: "Calendar", summary: "Reminder", body: "Meeting" };
assert.equal(loom.sameToast(toast, { ...toast, key: "b" }), true);
assert.equal(loom.sameToast(toast, toast), false);
for (const role of ["app", "summary", "body", "image", "execArgv", "execActions", "loomRecording"])
  assert.equal(loom.sameToast(toast, { ...toast, key: "b", [role]: "different" }), false, role);

const service = source("andres.notifications", "Service.qml");
const shortcut = service.match(/  function runShortcut\(method\) \{[\s\S]*?\n  \}/)?.[0];
assert.ok(shortcut);
let acts = 0, keyboards = 0;
const context = vm.createContext({ ipcHandler: { act() { acts++; }, keyboard() { keyboards++; } } });
vm.runInContext(shortcut, context);
assert.equal(context.runShortcut("act"), true);
assert.equal(context.runShortcut("keyboard"), true);
assert.equal(context.runShortcut("unknown"), false);
assert.equal(acts, 1); assert.equal(keyboards, 1);
assert.match(service, /function act\(\): string/);
assert.match(service, /function keyboard\(\): string/);
assert.match(service, /ShellIpc\s*\{\s*id: ipcHandler/);
assert.match(service, /videoPath,\s*action,\s*uploadBin/);
assert.match(source("andres.workspaces", "Workspaces.qml"), /o.workspaces.focus/);
assert.match(source("andres.menu", "Menu.qml"), /shown: root.mounted && root.rowsLoaded/);

console.log("Omarchy 4.5 plugin compatibility tests passed");
