/**
 * TTY-aware prompter for interactive and piped input.
 * Handles both TTY (interactive) and non-TTY (piped) stdin correctly.
 */

import { readFileSync } from "node:fs";
import { createInterface } from "node:readline/promises";
import { Writable } from "node:stream";
import { createLinePrompter, type AskOptions, type Prompter } from "./line-prompter.js";

/**
 * Create a prompter for TTY (interactive) input.
 * Uses readline/promises with proper error handling for EOF.
 *
 * Hidden questions (final review M4): in terminal mode readline switches the TTY to raw mode — so
 * the terminal itself echoes nothing — and echoes each typed character by writing it to its
 * `output`. That output is a switchable pass-through to stderr: for a hidden question the prompt is
 * written to stderr directly, the switch is turned off while the answer is typed (nothing typed
 * reaches the screen, not even as `*`), then turned back on and the line ended.
 */
export function createTtyPrompter(): Prompter {
  let muted = false;
  const output = new Writable({
    write(chunk: Buffer, _encoding, callback) {
      if (!muted) process.stderr.write(chunk);
      callback();
    },
  });
  // `terminal: true` is required: `output` is not a TTY itself, and without terminal mode readline
  // would leave the TTY in cooked mode, where the terminal echoes every keystroke on its own.
  const rl = createInterface({ input: process.stdin, output, terminal: true });
  let rejectPending: ((err: Error) => void) | null = null;

  const unmute = () => {
    if (!muted) return;
    muted = false;
    process.stderr.write("\n"); // readline's own end-of-line went to the muted output
  };

  // Handle readline close event (EOF or Ctrl+C on pending question)
  const onClose = () => {
    unmute();
    if (rejectPending) {
      rejectPending(new Error("stdin ended before an answer was given"));
      rejectPending = null;
    }
  };

  rl.on("close", onClose);

  return {
    async ask(question: string, options: AskOptions = {}): Promise<string> {
      return new Promise<string>((resolve, reject) => {
        rejectPending = reject;
        let prompt = question;
        if (options.hidden) {
          process.stderr.write(question);
          muted = true;
          prompt = "";
        }
        rl.question(prompt)
          .then((answer: string) => {
            rejectPending = null;
            unmute();
            resolve(answer);
          })
          .catch((err: unknown) => {
            rejectPending = null;
            unmute();
            reject(err);
          });
      });
    },
    close(): void {
      rl.removeListener("close", onClose);
      rl.close();
    },
  };
}

/**
 * Create a prompter based on TTY availability.
 * Lazily reads stdin only if prompting is actually needed (never blocks on stdin
 * when no prompt turns out to be required).
 */
export function createPrompter(): Prompter {
  let prompter: Prompter | null = null;

  return {
    async ask(question: string, options?: AskOptions): Promise<string> {
      if (!prompter) {
        if (process.stdin.isTTY) {
          prompter = createTtyPrompter();
        } else {
          const input = readFileSync(0, "utf8");
          prompter = createLinePrompter(input, (s) => process.stderr.write(s));
        }
      }
      return prompter.ask(question, options);
    },
    close(): void {
      if (prompter) {
        prompter.close();
      }
    },
  };
}
