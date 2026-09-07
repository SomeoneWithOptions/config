/** Syncs pi's light/dark theme with Omarchy's generated colors.toml. */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const home = process.env.HOME ?? "";
const colorsPath = join(home, ".local/state/omarchy/current/theme/colors.toml");

export function themeMode(colors: string): "light" | "dark" {
	return /^\s*mode\s*=\s*"light"/m.test(colors) ? "light" : "dark";
}

function omarchyPiTheme(): "light" | "dark" {
	try {
		return themeMode(readFileSync(colorsPath, "utf8"));
	} catch {
		return "dark";
	}
}

export default function (pi: ExtensionAPI) {
	let intervalId: ReturnType<typeof setInterval> | null = null;

	pi.on("session_start", (_event, ctx) => {
		let currentTheme = omarchyPiTheme();
		ctx.ui.setTheme(currentTheme);

		intervalId = setInterval(() => {
			const nextTheme = omarchyPiTheme();
			if (nextTheme !== currentTheme) {
				currentTheme = nextTheme;
				ctx.ui.setTheme(currentTheme);
			}
		}, 2000);
	});

	pi.on("session_shutdown", () => {
		if (intervalId) {
			clearInterval(intervalId);
			intervalId = null;
		}
	});
}
