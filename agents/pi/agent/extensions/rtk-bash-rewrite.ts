import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const execFileAsync = promisify(execFile);
const RTK_BIN = process.env.RTK_BIN || "rtk";

async function rewriteWithRtk(command: string): Promise<string | undefined> {
	try {
		const { stdout } = await execFileAsync(RTK_BIN, ["rewrite", command], {
			timeout: 1500,
			maxBuffer: 128 * 1024,
		});
		const rewritten = stdout.trim();
		if (!rewritten || rewritten === command) return undefined;
		return rewritten;
	} catch (error: any) {
		// Some rtk versions print a rewrite but exit non-zero, so still use stdout.
		const rewritten = typeof error?.stdout === "string" ? error.stdout.trim() : "";
		if (!rewritten || rewritten === command) return undefined;
		return rewritten;
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event) => {
		if (event.toolName !== "bash") return undefined;

		const input = event.input as { command?: string };
		const command = input.command?.trim();
		if (!command) return undefined;

		// Avoid recursively rewriting explicit rtk commands.
		if (/^rtk\b|\srtk\b/.test(command)) return undefined;

		const rewritten = await rewriteWithRtk(command);
		if (rewritten) input.command = rewritten;

		return undefined;
	});
}
