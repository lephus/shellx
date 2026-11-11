export type EmailLocale = "en" | "vi";

const COPY: Record<EmailLocale, { lead: string; enter: string; ignore: string }> = {
  en: {
    lead: "Your ShellX sign-in code is",
    enter: "Enter this code in ShellX within 10 minutes.",
    ignore: "If you did not ask for it, ignore this email: nobody can sign in without the code. ShellX will never ask you for this code by email, phone or chat.",
  },
  vi: {
    lead: "Mã đăng nhập ShellX của bạn là",
    enter: "Nhập mã này vào ShellX trong vòng 10 phút.",
    ignore: "Nếu bạn không yêu cầu mã, hãy bỏ qua email này: không ai đăng nhập được nếu không có mã. ShellX không bao giờ hỏi bạn mã này qua email, điện thoại hay tin nhắn.",
  },
};

const HTML_ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
const escapeHtml = (text: string): string => text.replace(/[&<>"']/g, (ch) => HTML_ESCAPES[ch]!);

/**
 * The sign-in mail (spec 2026-11-10 §6): the code and three sentences, as text and as minimal HTML. Nothing
 * to click or load: no link, no image, nothing remote; the only styling is a font size. The copy above has
 * no HTML character; the code is six digits and is escaped all the same.
 */
export function signInCodeEmail(code: string, locale: EmailLocale): { subject: string; text: string; html: string } {
  const copy = COPY[locale];
  const subject = `${copy.lead} ${code}`;
  const text = `${subject}\n\n${copy.enter}\n\n${copy.ignore}\n`;
  const html = [
    `<div lang="${locale}">`,
    `<p>${copy.lead}</p>`,
    `<p style="font-size:32px">${escapeHtml(code)}</p>`,
    `<p>${copy.enter}</p>`,
    `<p style="font-size:14px">${copy.ignore}</p>`,
    "</div>",
  ].join("\n");
  return { subject, text, html };
}
