import { mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const WORKTREE_HOME = join(homedir(), "code", "worktrees");

type Worktree = { path: string; branch?: string };

function parseWorktrees(output: string): Worktree[] {
	const worktrees: Worktree[] = [];
	for (const line of output.split("\n")) {
		if (line.startsWith("worktree ")) worktrees.push({ path: line.slice(9) });
		else if (line.startsWith("branch ")) worktrees.at(-1)!.branch = line.slice(7).replace("refs/heads/", "");
	}
	return worktrees;
}

function branchSlug(branch: string): string {
	return branch.replaceAll("/", "-").replace(/[^a-zA-Z0-9._-]/g, "-");
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("worktree", {
		description: "Create a Git worktree (auto-named when omitted) and open a parallel Pi session",
		handler: async (args, ctx) => {
			if (ctx.mode !== "tui") {
				ctx.ui.notify("/worktree requires interactive mode", "error");
				return;
			}

			const [argBranch, ...promptParts] = args.trim().split(/\s+/);
			const branch = argBranch || `pi-${Date.now()}`;

			try {
				const valid = await pi.exec("git", ["check-ref-format", "--branch", branch], { cwd: ctx.cwd });
				if (valid.code !== 0) throw new Error(valid.stderr.trim() || `Invalid branch: ${branch}`);

				const listed = await pi.exec("git", ["worktree", "list", "--porcelain"], { cwd: ctx.cwd });
				if (listed.code !== 0) throw new Error(listed.stderr.trim() || "Not inside a Git repository");

				const worktrees = parseWorktrees(listed.stdout);
				const mainPath = worktrees[0]?.path;
				if (!mainPath) throw new Error("Could not find main Git worktree");

				let worktreePath = worktrees.find((worktree) => worktree.branch === branch)?.path;
				let created = false;

				if (!worktreePath) {
					worktreePath = join(WORKTREE_HOME, basename(mainPath), branchSlug(branch));
					await mkdir(join(WORKTREE_HOME, basename(mainPath)), { recursive: true });

					const localBranch = await pi.exec("git", ["show-ref", "--verify", "--quiet", `refs/heads/${branch}`], {
						cwd: mainPath,
					});
					let baseCommit: string | undefined;
					if (localBranch.code !== 0) {
						const upstream = await pi.exec("git", ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], {
							cwd: ctx.cwd,
						});
						if (upstream.code === 0) {
							const fetched = await pi.exec("git", ["fetch"], { cwd: ctx.cwd });
							if (fetched.code !== 0) throw new Error(fetched.stderr.trim() || "Failed to fetch current branch");

							const pulled = await pi.exec("git", ["pull", "--ff-only"], { cwd: ctx.cwd });
							if (pulled.code !== 0) throw new Error(pulled.stderr.trim() || "Failed to pull current branch");
						}

						const head = await pi.exec("git", ["rev-parse", "HEAD"], { cwd: ctx.cwd });
						if (head.code !== 0) throw new Error(head.stderr.trim() || "Failed to resolve current branch");
						baseCommit = head.stdout.trim();
					}
					const addArgs = localBranch.code === 0
						? ["worktree", "add", worktreePath, branch]
						: ["worktree", "add", "-b", branch, worktreePath, baseCommit!];
					const added = await pi.exec("git", addArgs, { cwd: mainPath });
					if (added.code !== 0) throw new Error(added.stderr.trim() || "Failed to create worktree");
					created = true;
				}

				const piArgs = ["+new-window", `--working-directory=${worktreePath}`, "-e", "pi", "--name", branch];
				if (ctx.model) piArgs.push("--model", `${ctx.model.provider}/${ctx.model.id}`, "--thinking", ctx.thinkingLevel);
				const prompt = promptParts.join(" ");
				if (prompt) piArgs.push(prompt);

				const launched = await pi.exec("ghostty", piArgs, { timeout: 5000 });
				if (launched.code !== 0) {
					throw new Error(launched.stderr.trim() || `Created worktree, but Ghostty failed. Run: cd ${worktreePath} && pi`);
				}
				ctx.ui.notify(`${created ? "Created" : "Opened"} ${worktreePath}`, "info");
			} catch (error) {
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
			}
		},
	});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url) && process.argv.includes("--self-test")) {
	const parsed = parseWorktrees("worktree /repo\nHEAD abc\nbranch refs/heads/main\n\nworktree /wt\nbranch refs/heads/feature/x\n");
	if (parsed[1]?.path !== "/wt" || parsed[1]?.branch !== "feature/x" || branchSlug("feature/x") !== "feature-x") {
		throw new Error("worktree self-test failed");
	}
	console.log("worktree self-test passed");
}
