// Shared structured data (schema.org JSON-LD) and the guide registry. Every page builds its JSON-LD
// from here so names, ids and links stay identical across pages, llms.txt and the sitemap.
import { pathFor, type Lang } from '../i18n/ui';
import type { VideoId } from './videos';

export const siteUrl = 'https://shellx.pro';

// The byline of every page and guide (the user's choice: a team, not a person).
export const author = {
  '@type': 'Organization',
  '@id': `${siteUrl}/#team`,
  name: 'ShellPro Team',
  url: `${siteUrl}/`,
};

export const organization = {
  '@type': 'Organization',
  '@id': `${siteUrl}/#organization`,
  name: 'ShellX',
  url: siteUrl,
  logo: `${siteUrl}/apple-touch-icon.png`,
};

export const appId = `${siteUrl}/#app`;

export const keywords: Record<Lang, string[]> = {
  en: [
    'remote terminal app', 'SSH from phone', 'terminal on phone', 'control Mac terminal from iPhone',
    'remote terminal without VPN', 'no port forwarding', 'Claude Code on phone', 'tmux on phone',
    'terminal app for Mac and Windows', 'end-to-end encrypted terminal', 'mobile SSH alternative',
    'terminal for AI coding agents', 'run multiple AI coding agents', 'Claude Code terminal',
    'Codex, OpenCode, Gemini CLI and Pi', 'AI agent notifications', 'terminal with built-in browser',
    'browser automation for AI agents', 'vertical tabs and split panes', 'terminal workspaces',
    'terminal session restore', 'Ghostty-based terminal', 'GPU-accelerated terminal', 'terminal CLI and socket API',
  ],
};

export const featureList: Record<Lang, string[]> = {
  en: [
    'Open and control the terminal sessions of a Mac or PC from a phone',
    'End-to-end encrypted with the Noise protocol; the relay cannot read the content',
    'No open ports, static IP or VPN; works behind NAT and CGNAT',
    'Push notifications when a command finishes or a program needs you (OSC 9, 777, 99)',
    'Workspaces, split panes, session restore, command palette and custom shortcuts',
    'SSH workspaces and tmux attach, with automatic reconnect',
    'Phone pairing with a QR code',
    'Automations (macOS): describe a Claude Code job in plain English; ShellX saves it as a scheduled job, a workflow or a skill, draws its flowchart and runs it with launchd',
    'Run Claude Code, Codex, OpenCode, Gemini CLI and Pi side by side and see which agent is working, waiting or done',
    'Built-in browser pane that AI agents can drive: navigate, click, fill forms, run JavaScript, read the DOM, console and network',
    'Command-line tool and Unix socket API to create workspaces and panes, send input, read output and take screenshots',
    'Vertical tabs with Git branch, working directory and listening ports in the sidebar',
    'Ghostty terminal engine with GPU-accelerated rendering; custom themes, fonts, colors and shortcuts',
  ],
};

/**
 * The desktop app by area: the "Inside the desktop app" section of the home page and llms.txt.
 * Every line describes ShellX for macOS; the Windows app does not have all of it yet.
 */
export const capabilities: Record<Lang, Array<{ id: string; title: string; items: string[] }>> = {
  en: [
    { id: 'terminal', title: 'Terminal management', items: [
      'Vertical tabs in a sidebar',
      'Split panes, side by side or stacked; create, close, move and resize them',
      'Many terminals and workspaces at once, with quick switching and renaming',
      'Git branch, working directory and listening ports shown for each workspace',
    ] },
    { id: 'agents', title: 'AI coding agents', items: [
      'Run Claude Code, Codex, OpenCode, Gemini CLI and Pi side by side',
      'See at a glance which agent is working, which is waiting for you and which has finished',
      'A badge on the workspace, a ring around the pane and a notification list collect what needs you',
      'macOS desktop notifications when an agent needs input or completes its task',
      'Works with Claude Code agent teams',
    ] },
    { id: 'browser', title: 'Built-in browser', items: [
      'Open a browser pane next to your terminal and preview localhost',
      'Agents can navigate to a URL, click elements and fill in forms',
      'Read and snapshot the DOM, run JavaScript, read console logs and network requests',
      'A browser automation API, so an agent can test the page it just built',
    ] },
    { id: 'remote', title: 'SSH and remote development', items: [
      'SSH workspaces: terminals that run on a remote server',
      'Attach to the tmux sessions already running there',
      'Several SSH sessions at once, with automatic reconnect',
    ] },
    { id: 'automation', title: 'CLI and automation', items: [
      'The shellx command-line tool and a Unix socket API control the app',
      'Create and arrange workspaces and panes from a script',
      'Send input to a terminal, read its output and take a screenshot of it',
      'Automate workflows and connect outside tools',
    ] },
    { id: 'sessions', title: 'Sessions and state', items: [
      'Workspaces, layout and panes come back after a restart',
      'Working directories and terminal scrollback are restored',
      'Supported AI agent sessions can be resumed',
    ] },
    { id: 'customization', title: 'Customization', items: [
      'Themes, fonts and colors',
      'Keyboard shortcuts you can rebind',
      'Sidebar, workspace and terminal settings',
    ] },
    { id: 'mobile', title: 'Phone companion', items: [
      'iOS and Android apps open the sessions running on your computer',
      'Push notifications on your phone when a command finishes or an agent needs you',
      'Watch and answer from anywhere, end-to-end encrypted',
    ] },
    { id: 'dx', title: 'Developer experience', items: [
      'Ghostty terminal engine with GPU-accelerated rendering',
      'Git and port information without leaving the terminal',
      'Many projects open at the same time',
      'Keyboard-driven navigation and a command palette',
    ] },
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
  /** A video shown under the title (its VideoObject stays on /videos/). */
  video?: VideoId;
}

// Read as raw text, not as modules: the guide pages import Guide.astro, which imports this file.
const raw = import.meta.glob<string>(['../pages/guides/*.md'],
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
