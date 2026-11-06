// The site's videos: files in public/media/, captions in src/videos/<name>.srt. The captions are
// burned into the picture, so the players carry no text track; the .srt files feed the chapters, the
// transcripts and the VideoObject JSON-LD, so those never drift from what is said.
import type { Lang } from '../i18n/ui';
import { organization, siteUrl } from './seo';
import introCaptions from '../videos/shellx-intro.srt?raw';
import tutorialCaptions from '../videos/shellx-tutorial.srt?raw';
import automationsCaptions from '../videos/shellx-automations.srt?raw';

export type VideoId = 'intro' | 'tutorial' | 'automations';

interface Source {
  /** File stem in public/media/: <name>.mp4 and the poster <name>.webp. */
  name: string;
  /** Length of the mp4, rounded to the second. */
  seconds: number;
  /** First published on shellx.pro. */
  uploaded: string;
  /** The .srt of the narration. */
  captions: string;
  title: Record<Lang, string>;
  description: Record<Lang, string>;
  /** Each chapter starts at a cue, numbered as in the .srt. */
  chapters: Array<{ cue: number; title: Record<Lang, string> }>;
}

const sources: Record<VideoId, Source> = {
  intro: {
    name: 'shellx-intro',
    seconds: 60,
    uploaded: '2026-10-29T13:00:00+07:00',
    captions: introCaptions,
    title: { en: 'ShellX in one minute' },
    description: {
      en: 'ShellX is a terminal for Mac and PC: a workspace per project, split panes, a built-in browser and your AI agents. Open your sessions from your phone, end-to-end encrypted.',
    },
    chapters: [{ cue: 1, title: { en: 'Introduction' } }],
  },
  tutorial: {
    name: 'shellx-tutorial',
    seconds: 183,
    uploaded: '2026-10-29T13:00:00+07:00',
    captions: tutorialCaptions,
    title: { en: 'Getting started with ShellX' },
    description: {
      en: 'Step by step: create workspaces, split panes, run Claude Code or Codex, pair your phone, follow your agents and answer their requests in Needs You.',
    },
    chapters: [
      { cue: 1, title: { en: 'Getting started' } },
      { cue: 3, title: { en: 'Workspaces and the sidebar' } },
      { cue: 7, title: { en: 'Split panes and the built-in browser' } },
      { cue: 9, title: { en: 'Command palette' } },
      { cue: 11, title: { en: 'Run an AI agent' } },
      { cue: 13, title: { en: 'Approve an agent request' } },
      { cue: 16, title: { en: 'Pair your phone' } },
      { cue: 22, title: { en: 'Follow agents from your phone' } },
      { cue: 26, title: { en: 'Needs You: allow, answer, review plans' } },
      { cue: 31, title: { en: 'End-to-end encryption' } },
      { cue: 34, title: { en: 'Download ShellX' } },
    ],
  },
  automations: {
    name: 'shellx-automations',
    seconds: 97,
    uploaded: '2026-11-06T17:00:00+07:00',
    captions: automationsCaptions,
    title: { en: 'Automations for Claude Code' },
    description: {
      en: 'Describe a job in plain English and Claude Code drafts it: a schedule, a folder, the commands it may run and how it tells you. Check the flowchart, save, and ShellX runs it on your Mac.',
    },
    chapters: [
      { cue: 1, title: { en: 'Introduction' } },
      { cue: 2, title: { en: 'Skills, workflows and jobs in one place' } },
      { cue: 4, title: { en: 'Describe a new automation' } },
      { cue: 6, title: { en: 'Claude Code drafts the cronjob' } },
      { cue: 8, title: { en: 'Choose how to hear back' } },
      { cue: 9, title: { en: 'Check the flowchart and the skill file' } },
      { cue: 11, title: { en: 'Save it and run it now' } },
      { cue: 14, title: { en: 'Your existing Claude Code skills' } },
      { cue: 16, title: { en: 'Download ShellX' } },
    ],
  },
};

interface Cue { start: string; end: string; text: string }

function parseSrt(srt: string): Cue[] {
  return srt.trim().split(/\r?\n\r?\n/).map((block) => {
    const [, timing, ...text] = block.split(/\r?\n/);
    const [start, end] = timing.split(' --> ');
    return { start, end, text: text.join(' ') };
  });
}

/** Seconds of an SRT timestamp such as 00:01:23,461. */
function seconds(ts: string): number {
  const [h, m, s] = ts.replace(',', '.').split(':').map(Number);
  return h * 3600 + m * 60 + s;
}

export interface Chapter { start: number; end: number; title: string; text: string }

export interface Video {
  id: VideoId;
  name: string;
  title: string;
  description: string;
  mp4: string;
  poster: string;
  seconds: number;
  chapters: Chapter[];
}

export function video(lang: Lang, id: VideoId): Video {
  const s = sources[id];
  const cues = parseSrt(s.captions);
  const chapters = s.chapters.map((c, i) => {
    const next = s.chapters[i + 1];
    const last = next ? next.cue - 1 : cues.length;
    return {
      start: Math.floor(seconds(cues[c.cue - 1].start)),
      end: next ? Math.floor(seconds(cues[next.cue - 1].start)) : s.seconds,
      title: c.title[lang],
      text: cues.slice(c.cue - 1, last).map((cue) => cue.text).join(' '),
    };
  });
  return {
    id, name: s.name, title: s.title[lang], description: s.description[lang],
    mp4: `/media/${s.name}.mp4`, poster: `/media/${s.name}.webp`,
    seconds: s.seconds, chapters,
  };
}

/** m:ss, as shown next to a chapter. */
export function clock(s: number): string {
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/** Query that opens the watch page at second `t` of video `id`: plain ?t= for the tutorial (the first
 *  video with chapters, whose links are already shared), ?v=<id>&t= for the others. */
export function startQuery(id: VideoId, t: number): string {
  return id === 'tutorial' ? `?t=${t}` : `?v=${id}&t=${t}`;
}

/** VideoObject for the watch page at `path`; a chapter is a Clip that opens the page at its start. */
export function videoLd(v: Video, path: string) {
  const s = sources[v.id];
  return {
    '@context': 'https://schema.org', '@type': 'VideoObject', '@id': `${siteUrl}${path}#${v.id}`,
    name: v.title, description: v.description,
    thumbnailUrl: [`${siteUrl}${v.poster}`],
    uploadDate: s.uploaded,
    duration: `PT${Math.floor(v.seconds / 60)}M${v.seconds % 60}S`,
    contentUrl: `${siteUrl}${v.mp4}`,
    inLanguage: 'en',
    transcript: v.chapters.map((c) => c.text).join(' '),
    publisher: { '@id': organization['@id'] },
    ...(v.chapters.length > 1 && {
      hasPart: v.chapters.map((c) => ({
        '@type': 'Clip', name: c.title, startOffset: c.start, endOffset: c.end,
        url: `${siteUrl}${path}${startQuery(v.id, c.start)}`,
      })),
    }),
  };
}
