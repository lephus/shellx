/**
 * The prompter interface and its pure, non-TTY implementation (unit-tested in
 * `test/reset-password.test.ts`). The TTY-backed prompters live in `prompter.ts`.
 */

export interface AskOptions {
  /** The answer is a secret (a password): an interactive terminal must not echo what is typed. */
  hidden?: boolean;
}

export interface Prompter {
  ask(question: string, options?: AskOptions): Promise<string>;
  close(): void;
}

/**
 * Create a prompter for non-TTY (piped) input.
 * Splits input on newlines and returns each line on demand.
 * Rejects with "stdin ended" error when input is exhausted.
 * `hidden` needs nothing here: piped input is never echoed by a terminal, and only the question
 * (never the answer) is written.
 */
export function createLinePrompter(input: string, write: (s: string) => void): Prompter {
  // Split on newlines and filter out the trailing empty line if input ends with newline
  let lines = input.split(/\r?\n/);
  if (lines.length > 0 && lines[lines.length - 1] === "") {
    lines = lines.slice(0, -1);
  }
  let index = 0;

  return {
    async ask(question: string): Promise<string> {
      write(question);
      if (index >= lines.length) {
        throw new Error("stdin ended before an answer was given");
      }
      const answer = lines[index++];
      return answer ?? "";
    },
    close(): void {
      // No-op for line prompter
    },
  };
}
