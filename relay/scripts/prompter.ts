/**
 * TTY-aware prompter for interactive and piped input.
 * Handles both TTY (interactive) and non-TTY (piped) stdin correctly.
 */

import { readFileSync } from "node:fs";
import { createInterface } from "node:readline/promises";
import { createLinePrompter, type Prompter } from "./line-prompter";

/**
 * Create a prompter for TTY (interactive) input.
 * Uses readline/promises with proper error handling for EOF.
 */
export function createTtyPrompter(): Prompter {
  const rl = createInterface({ input: process.stdin, output: process.stderr });
  let rejectPending: ((err: Error) => void) | null = null;

  // Handle readline close event (EOF on pending question)
  const onClose = () => {
    if (rejectPending) {
      rejectPending(new Error("stdin ended before an answer was given"));
      rejectPending = null;
    }
  };

  rl.on("close", onClose);

  return {
    async ask(question: string): Promise<string> {
      return new Promise<string>((resolve, reject) => {
        rejectPending = reject;
        rl.question(question)
          .then((answer: string) => {
            rejectPending = null;
            resolve(answer);
          })
          .catch((err: unknown) => {
            rejectPending = null;
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
    async ask(question: string): Promise<string> {
      if (!prompter) {
        if (process.stdin.isTTY) {
          prompter = createTtyPrompter();
        } else {
          const input = readFileSync(0, "utf8");
          prompter = createLinePrompter(input, (s) => process.stderr.write(s));
        }
      }
      return prompter.ask(question);
    },
    close(): void {
      if (prompter) {
        prompter.close();
      }
    },
  };
}
