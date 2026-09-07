/**
 * Ask User Tool - interactive question picker for pi.
 *
 * Lets the model ask a blocking question with suggested options plus a custom
 * free-text answer path. Installed globally from ~/.pi/agent/extensions.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Editor, type EditorTheme, Key, matchesKey, Text, truncateToWidth, wrapTextWithAnsi } from "@mariozechner/pi-tui";
import { Type } from "typebox";

interface AskOption {
	label: string;
	description?: string;
}

type DisplayOption = AskOption & { isCustom?: boolean };

interface AskUserDetails {
	question: string;
	options: string[];
	answer: string | null;
	wasCustom?: boolean;
	selectedIndex?: number;
}

const AskOptionSchema = Type.Object({
	label: Type.String({ description: "Short selectable answer label" }),
	description: Type.Optional(Type.String({ description: "Optional one-line explanation shown under the label" })),
});

const AskUserParams = Type.Object({
	question: Type.String({ description: "The exact question to ask the user" }),
	options: Type.Array(AskOptionSchema, {
		description:
			"Likely answers the user can quickly pick from. Include 2-6 concise options whenever possible.",
	}),
	customLabel: Type.Optional(
		Type.String({ description: "Label for the custom answer option. Defaults to 'Type a custom answer'." }),
	),
});

export default function askUserExtension(pi: ExtensionAPI) {
	let promptActive = false;
	const promptWaiters: Array<{
		resolve: (release: () => void) => void;
		reject: (error: Error) => void;
		signal?: AbortSignal;
		onAbort?: () => void;
	}> = [];

	function abortError() {
		return new Error("ask_user was aborted");
	}

	function releaseNextPrompt() {
		while (promptWaiters.length > 0) {
			const next = promptWaiters.shift()!;
			if (next.onAbort) next.signal?.removeEventListener("abort", next.onAbort);
			if (next.signal?.aborted) {
				next.reject(abortError());
				continue;
			}
			next.resolve(releaseNextPrompt);
			return;
		}
		promptActive = false;
	}

	async function acquirePromptSlot(signal?: AbortSignal): Promise<() => void> {
		if (signal?.aborted) throw abortError();
		if (!promptActive) {
			promptActive = true;
			return releaseNextPrompt;
		}

		return new Promise<() => void>((resolve, reject) => {
			const waiter = { resolve, reject, signal } as (typeof promptWaiters)[number];
			waiter.onAbort = () => {
				const index = promptWaiters.indexOf(waiter);
				if (index >= 0) promptWaiters.splice(index, 1);
				reject(abortError());
			};
			if (signal) signal.addEventListener("abort", waiter.onAbort, { once: true });
			promptWaiters.push(waiter);
		});
	}

	pi.registerTool({
		name: "ask_user",
		label: "Ask User",
		description:
			"Ask the user a question with a nice interactive selector. Use this when you need user input to proceed.",
		promptSnippet:
			"Ask the user a blocking question with suggested choices and optional custom text input.",
		promptGuidelines: [
			"Use ask_user whenever you need a decision, preference, missing requirement, approval, credential-independent choice, or clarification before continuing.",
			"When using ask_user, provide concise likely options so the user can usually pick one quickly; include descriptions only when they clarify tradeoffs.",
			"Do not ask clarification questions as plain assistant text when ask_user can present them as selectable options.",
		],
		parameters: AskUserParams,

		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const simpleOptions = params.options.map((option) => option.label);

			if (!ctx.hasUI) {
				return {
					content: [
						{
							type: "text" as const,
							text:
								"Interactive UI is unavailable in this mode. Ask the user directly in text and wait for their answer.",
						},
					],
					details: { question: params.question, options: simpleOptions, answer: null } satisfies AskUserDetails,
				};
			}

			const customLabel = params.customLabel?.trim() || "Type a custom answer";
			const allOptions: DisplayOption[] = [...params.options, { label: customLabel, isCustom: true }];

			let releasePrompt: (() => void) | undefined;
			let abortCleanup: (() => void) | undefined;
			let result: { answer: string; wasCustom: boolean; index?: number } | null;
			try {
				releasePrompt = await acquirePromptSlot(signal);
				result = await ctx.ui.custom<{ answer: string; wasCustom: boolean; index?: number } | null>(
				(tui, theme, _keybindings, done) => {
					let selectedIndex = 0;
					let editMode = false;
					let cachedLines: string[] | undefined;

					const editorTheme: EditorTheme = {
						borderColor: (s) => theme.fg("accent", s),
						selectList: {
							selectedPrefix: (s) => theme.fg("accent", s),
							selectedText: (s) => theme.fg("accent", s),
							description: (s) => theme.fg("muted", s),
							scrollInfo: (s) => theme.fg("dim", s),
							noMatch: (s) => theme.fg("warning", s),
						},
					};
					const editor = new Editor(tui, editorTheme);
					const abortPrompt = () => done(null);
					if (signal) {
						if (signal.aborted) abortPrompt();
						else signal.addEventListener("abort", abortPrompt, { once: true });
						abortCleanup = () => signal.removeEventListener("abort", abortPrompt);
					}

					function refresh() {
						cachedLines = undefined;
						tui.requestRender();
					}

					editor.onSubmit = (value) => {
						const answer = value.trim();
						if (answer.length > 0) {
							done({ answer, wasCustom: true });
							return;
						}
						editMode = false;
						editor.setText("");
						refresh();
					};

					function chooseCurrent() {
						const selected = allOptions[selectedIndex];
						if (selected.isCustom) {
							editMode = true;
							refresh();
							return;
						}
						done({ answer: selected.label, wasCustom: false, index: selectedIndex + 1 });
					}

					function handleInput(data: string) {
						if (editMode) {
							if (matchesKey(data, Key.escape)) {
								editMode = false;
								editor.setText("");
								refresh();
								return;
							}
							editor.handleInput(data);
							refresh();
							return;
						}

						if (matchesKey(data, Key.up)) {
							selectedIndex = Math.max(0, selectedIndex - 1);
							refresh();
							return;
						}
						if (matchesKey(data, Key.down)) {
							selectedIndex = Math.min(allOptions.length - 1, selectedIndex + 1);
							refresh();
							return;
						}
						if (matchesKey(data, Key.enter)) {
							chooseCurrent();
							return;
						}
						if (matchesKey(data, Key.escape)) {
							done(null);
							return;
						}

						// Number shortcuts: 1-9 selects matching option immediately.
						if (/^[1-9]$/.test(data)) {
							const index = Number(data) - 1;
							if (index >= 0 && index < allOptions.length) {
								selectedIndex = index;
								chooseCurrent();
							}
						}
					}

					function render(width: number): string[] {
						if (cachedLines) return cachedLines;

						const lines: string[] = [];
						const rule = theme.fg("accent", "─".repeat(Math.max(0, width)));
						const add = (line = "") => lines.push(truncateToWidth(line, width));

						add(rule);
						for (const line of wrapTextWithAnsi(theme.fg("text", params.question), Math.max(1, width - 2))) {
							add(` ${line}`);
						}
						add("");

						for (let i = 0; i < allOptions.length; i++) {
							const option = allOptions[i];
							const selected = i === selectedIndex;
							const prefix = selected ? theme.fg("accent", "› ") : "  ";
							const marker = option.isCustom && editMode ? " ✎" : "";
							const label = `${i + 1}. ${option.label}${marker}`;
							add(prefix + (selected ? theme.fg("accent", label) : theme.fg("text", label)));

							if (option.description) {
								for (const line of wrapTextWithAnsi(theme.fg("muted", option.description), Math.max(1, width - 6))) {
									add(`     ${line}`);
								}
							}
						}

						if (editMode) {
							add("");
							add(theme.fg("muted", " Custom answer:"));
							for (const line of editor.render(Math.max(1, width - 2))) {
								add(` ${line}`);
							}
						}

						add("");
						add(
							editMode
								? theme.fg("dim", " Enter submit • Esc back")
								: theme.fg("dim", " ↑↓ navigate • 1-9 quick pick • Enter select • Esc cancel"),
						);
						add(rule);

						cachedLines = lines;
						return lines;
					}

					return {
						render,
						invalidate() {
							cachedLines = undefined;
						},
						handleInput,
					};
				},
			);
			} catch (error) {
				return {
					content: [{ type: "text" as const, text: "Question aborted before the user answered." }],
					details: { question: params.question, options: simpleOptions, answer: null } satisfies AskUserDetails,
				};
			} finally {
				abortCleanup?.();
				releasePrompt?.();
			}

			if (!result) {
				return {
					content: [{ type: "text" as const, text: "User cancelled the question." }],
					details: { question: params.question, options: simpleOptions, answer: null } satisfies AskUserDetails,
				};
			}

			const details = {
				question: params.question,
				options: simpleOptions,
				answer: result.answer,
				wasCustom: result.wasCustom,
				selectedIndex: result.index,
			} satisfies AskUserDetails;

			return {
				content: [
					{
						type: "text" as const,
						text: result.wasCustom
							? `User wrote a custom answer: ${result.answer}`
							: `User selected option ${result.index}: ${result.answer}`,
					},
				],
				details,
			};
		},

		renderCall(args, theme) {
			let text = theme.fg("toolTitle", theme.bold("ask_user ")) + theme.fg("text", args.question ?? "");
			const options = Array.isArray(args.options) ? args.options : [];
			if (options.length > 0) {
				const labels = options.map((option: AskOption) => option.label).filter(Boolean);
				labels.push(args.customLabel || "Type a custom answer");
				text += `\n${theme.fg("dim", `  ${labels.map((label, i) => `${i + 1}. ${label}`).join("  •  ")}`)}`;
			}
			return new Text(text, 0, 0);
		},

		renderResult(result, _options, theme) {
			const details = result.details as AskUserDetails | undefined;
			if (!details) {
				const first = result.content[0];
				return new Text(first?.type === "text" ? first.text : "", 0, 0);
			}

			if (details.answer === null) {
				return new Text(theme.fg("warning", "Question cancelled"), 0, 0);
			}

			const prefix = theme.fg("success", "✓ Answer: ");
			const mode = details.wasCustom ? theme.fg("muted", "custom ") : theme.fg("muted", `option ${details.selectedIndex ?? ""} `);
			return new Text(prefix + mode + theme.fg("accent", details.answer), 0, 0);
		},
	});

	pi.registerCommand("ask-user-test", {
		description: "Show a sample ask_user picker",
		handler: async (_args, ctx) => {
			ctx.ui.notify("Ask the model to use ask_user, or try: 'ask me which database to use with options'", "info");
		},
	});
}
