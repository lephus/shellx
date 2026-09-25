/**
 * The prompter interface and its pure, non-TTY implementation. Deliberately free of Node imports:
 * `test/reset-password.test.ts` imports it from the Worker project (tsconfig.json), which must not
 * carry Node types — otherwise `src/` could use `Buffer`/`process` and only crash at runtime.
 * The Node-backed prompters live in `prompter.ts` (checked by scripts/tsconfig.json only).
 */

export interface Prompter {
  ask(question: string): Promise<string>;
  close(): void;
}

/**
 * Create a prompter for non-TTY (piped) input.
 * Splits input on newlines and returns each line on demand.
 * Rejects with "stdin ended" error when input is exhausted.
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
