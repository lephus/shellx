/** Parses disposable_email_blocklist.conf: one domain per line, `#` comments, blank lines ignored. */
export function parseBlocklist(text: string): string[] {
  const domains = new Set<string>();
  for (const line of text.split(/\r?\n/)) {
    const domain = line.trim().toLowerCase();
    if (domain === "" || domain.startsWith("#")) continue;
    domains.add(domain);
  }
  return [...domains].sort();
}

/** One domain per line so that list refreshes produce readable diffs. */
export function renderDomainsJson(domains: readonly string[]): string {
  return `[\n${domains.map((d) => `  ${JSON.stringify(d)}`).join(",\n")}\n]\n`;
}
