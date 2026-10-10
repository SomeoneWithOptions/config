import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import vm from "node:vm";

const require = createRequire(import.meta.url);
const menu = require("../system/omarchy/plugins/andres.menu/MenuModel.js");
const notifications = require("../system/omarchy/plugins/andres.notifications/NotificationLogic.js");
const source = (plugin, file) => readFileSync(new URL(`../system/omarchy/plugins/${plugin}/${file}`, import.meta.url), "utf8");

// The installed menu now uses disabled guards for already-installed apps.
const installed = menu.normalizeItem("install.example", { label: "Example", disabled: "true" });
const disabled = { "install.example": true };
assert.equal(menu.isDisabled(disabled, installed), true);
assert.equal(menu.isDisabled({}, installed), false);
assert.equal(menu.labelFor(installed, {}, disabled), "Example ✓");
assert.equal(menu.displayRow({ [installed.id]: installed }, [installed.id], {}, disabled, installed).disabled, true);
assert.match(menu.guardScript({ [installed.id]: installed }), /install\.example:d:1/);
assert.deepEqual(menu.summonAction("omarchy-shell shell summon omarchy.speedtest"), { id: "omarchy.speedtest", payload: "{}" });
assert.equal(menu.summonAction("omarchy-shell shell summon omarchy.speedtest && echo done"), null);

// Identical live toasts collapse; distinct click targets and recording cards
// must survive even when app, summary, and body match.
const toast = { originalId: 1, app: "Calendar", summary: "Reminder", body: "Meeting" };
assert.equal(notifications.isDuplicatePopup(toast, { ...toast, originalId: 2 }), true);
assert.equal(notifications.isDuplicatePopup(toast, toast), false);
for (const role of ["app", "summary", "body", "image", "execArgv", "loomRecording"]) {
  assert.equal(notifications.isDuplicatePopup(toast, { ...toast, originalId: 2, [role]: "different" }), false, role);
}

// Exercise the actual QML shortcut dispatcher without connecting to the live
// notification server. Upstream invokes this method directly for Super+comma.
const service = source("andres.notifications", "Service.qml");
const shortcut = service.match(/  function runShortcut\(method\) \{[\s\S]*?\n  \}/)?.[0];
assert.ok(shortcut, "notification clone must support upstream global shortcuts");
let dismissals = 0;
const context = vm.createContext({ ipcHandler: { dismissOne() { dismissals++; } } });
vm.runInContext(shortcut, context);
assert.equal(context.runShortcut("dismissOne"), true);
assert.equal(dismissals, 1);
assert.equal(context.runShortcut("unknown"), false);

// Resolve the integration points that model-only assertions cannot cover.
assert.match(service, /IpcHandler\s*\{\s*id: ipcHandler/);
assert.match(service, /removeDuplicatePopups\(service\.currentContent\(notification, snapshot\)\)/);
const menuQml = source("andres.menu", "Menu.qml");
assert.match(menuQml, /visible: root\.mounted && root\.rowsLoaded/);
assert.match(menuQml, /opacity: entranceProgress \* \(row\.disabled \? 0\.4 : 1\)/);
assert.match(menuQml, /if \(!root\.rowSelectable\(index\)\) return/);

console.log("Omarchy plugin compatibility tests passed");
