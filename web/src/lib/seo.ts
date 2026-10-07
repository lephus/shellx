// Shared structured data (schema.org JSON-LD) and the guide registry. Every page builds its JSON-LD
// from here so names, ids and links stay identical across pages, llms.txt and the sitemap.
import { pathFor, type Lang } from '../i18n/ui';

export const siteUrl = 'https://shellx.pro';

export const author = {
  '@type': 'Person',
  '@id': `${siteUrl}/#founder`,
  name: 'Phu Le',
  url: 'https://huuphule.coregenaihub.com',
  sameAs: [
    'https://huuphule.coregenaihub.com',
    'https://www.linkedin.com/in/lehuuphu',
    'https://github.com/lephus',
    'https://medium.com/@phule9225',
  ],
};

export const organization = {
  '@type': 'Organization',
  '@id': `${siteUrl}/#organization`,
  name: 'ShellX',
  url: siteUrl,
  logo: `${siteUrl}/apple-touch-icon.png`,
  founder: { '@id': author['@id'] },
};

export const appId = `${siteUrl}/#app`;

export const keywords: Record<Lang, string[]> = {
  vi: [
    'terminal trên điện thoại', 'SSH từ điện thoại', 'điều khiển terminal từ xa', 'remote terminal',
    'terminal Mac từ xa', 'không cần VPN', 'không cần mở port', 'Claude Code trên điện thoại',
    'tmux trên điện thoại', 'app terminal cho Mac và Windows', 'mã hóa đầu cuối',
  ],
  en: [
    'remote terminal app', 'SSH from phone', 'terminal on phone', 'control Mac terminal from iPhone',
    'remote terminal without VPN', 'no port forwarding', 'Claude Code on phone', 'tmux on phone',
    'terminal app for Mac and Windows', 'end-to-end encrypted terminal', 'mobile SSH alternative',
  ],
};

export const featureList: Record<Lang, string[]> = {
  vi: [
    'Mở và điều khiển các phiên terminal của máy Mac hoặc PC từ điện thoại',
    'Mã hóa đầu cuối bằng giao thức Noise; máy chủ chuyển tiếp không đọc được nội dung',
    'Không cần mở port, IP tĩnh hay VPN; hoạt động sau NAT và CGNAT',
    'Thông báo đẩy khi lệnh chạy xong hoặc chương trình cần bạn (OSC 9, 777, 99)',
    'Workspace, chia pane, khôi phục phiên, bảng lệnh và phím tắt tùy chỉnh',
    'Workspace SSH và gắn phiên tmux, tự kết nối lại khi mất mạng',
    'Ghép nối điện thoại bằng mã QR',
  ],
  en: [
    'Open and control the terminal sessions of a Mac or PC from a phone',
    'End-to-end encrypted with the Noise protocol; the relay cannot read the content',
    'No open ports, static IP or VPN; works behind NAT and CGNAT',
    'Push notifications when a command finishes or a program needs you (OSC 9, 777, 99)',
    'Workspaces, split panes, session restore, command palette and custom shortcuts',
    'SSH workspaces and tmux attach, with automatic reconnect',
    'Phone pairing with a QR code',
  ],
};

export interface GuideFrontmatter {
  lang: Lang;
  slug: string;
  order: number;
  title: string;
  metaTitle: string;
  description: string;
  published: string;
  updated: string;
  keywords: string[];
}

// Read as raw text, not as modules: the guide pages import Guide.astro, which imports this file.
const raw = import.meta.glob<string>(['../pages/guides/*.md', '../pages/en/guides/*.md'],
  { eager: true, query: '?raw', import: 'default' });

/** Guide front matter is flat `key: value` lines; values are JSON (strings, arrays) or numbers. */
function parse(text: string): GuideFrontmatter & { body: string } {
  const m = text.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!m) throw new Error('guide without front matter');
  const data: Record<string, unknown> = {};
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^(\w+):\s*(.*)$/);
    if (!kv || kv[1] === 'layout') continue;
    const v = kv[2].trim();
    data[kv[1]] = /^["[]/.test(v) ? JSON.parse(v) : /^\d+$/.test(v) ? Number(v) : v;
  }
  return { ...(data as unknown as GuideFrontmatter), body: m[2].trim() };
}

const all = Object.values(raw).map(parse);

export function guidePath(lang: Lang, slug: string): string {
  return `${pathFor(lang, 'guides')}${slug}/`;
}

/** The guides of one language, in reading order, with their Markdown body (for llms-full.txt). */
export function guides(lang: Lang): Array<GuideFrontmatter & { path: string; body: string }> {
  return all
    .filter((g) => g.lang === lang)
    .sort((a, b) => a.order - b.order)
    .map((g) => ({ ...g, path: guidePath(lang, g.slug) }));
}

export function breadcrumbs(items: Array<{ name: string; path: string }>) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((it, i) => ({
      '@type': 'ListItem', position: i + 1, name: it.name, item: `${siteUrl}${it.path}`,
    })),
  };
}
