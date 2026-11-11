import type { EmailGateway, EmailMessage, EmailSendResult } from "../src/email/resend.js";

/** Records every mail instead of sending it; `result` is what the next sends answer. */
export class FakeEmailGateway implements EmailGateway {
  readonly sent: EmailMessage[] = [];
  result: EmailSendResult = { ok: true };

  async send(message: EmailMessage): Promise<EmailSendResult> {
    this.sent.push(message);
    return this.result;
  }

  /** The six-digit code of the newest mail to `to`, read from its subject. */
  codeFor(to: string): string {
    const mail = this.sent.findLast((m) => m.to === to);
    const code = mail === undefined ? null : /\b([0-9]{6})\b/.exec(mail.subject);
    if (code === null) throw new Error("no code was mailed to that address");
    return code[1]!;
  }
}
