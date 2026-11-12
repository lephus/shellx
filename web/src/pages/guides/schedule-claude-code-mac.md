---
layout: ../../layouts/Guide.astro
lang: en
slug: schedule-claude-code-mac
order: 9
title: "How to schedule Claude Code on your Mac (cron jobs, workflows and skills)"
metaTitle: "Schedule Claude Code on a Mac: cron jobs & workflows — ShellX"
description: "Run Claude Code on a schedule on your own Mac: describe the job in plain English, check the flowchart, save. Compared with Claude Desktop, cloud tasks and cron."
published: "2026-11-09"
updated: "2026-11-09"
keywords: ["schedule Claude Code", "Claude Code cron job", "run Claude Code on a schedule", "Claude Code scheduled tasks Mac", "Claude Code launchd", "automate Claude Code", "Claude Code skills", "claude -p cron"]
video: automations
---

**Short answer:** to run Claude Code on a schedule on your own Mac, with your repos, your tools and your secrets, open **Automations** in ShellX, describe the job in one sentence, and save the draft Claude Code writes for you. ShellX installs it as a launchd job, so it runs at the set time **even when the ShellX app is closed**, and tells you on your Mac when it is done, fails or needs you. If the job should run while your computer is off, use Anthropic's **cloud scheduled tasks** instead; there is a comparison of all four options below.

## What you need

- A Mac with macOS 14 or later and ShellX 1.7.0 or later — [download](/#download). Automations is in the macOS app only.
- [Claude Code](https://code.claude.com/docs) installed and signed in on that Mac. Automations runs your own Claude Code, with your account; if ShellX can't find it, it says *"Claude Code was not found on this Mac. Install it, then try again."*

## Step by step: a weekday pull-request summary

1. **Open Automations** in the ShellX sidebar. Each card shows a job's schedule, its next run and how the last run went.
2. **Press New and describe the job**, for example: *"Every weekday at 9am, summarize the pull requests in ~/code/web."*
3. **Answer Claude Code's questions.** It asks one thing at a time: the schedule, the folder the job runs in, and the commands it may use while you're away. It grants the least that works, for example `Bash(gh pr list:*)` and `Bash(gh pr view:*)` rather than all of Bash, and asks how you want to hear back: **When done**, **When failed**, **When it needs you**.
4. **Check the draft.** The **Flowchart** tab draws the job's logic as steps, decisions and the points where it stops to ask you. The **Text** tab shows the `SKILL.md` file Claude Code will follow. While drafting, Claude Code can only read files; ShellX writes the files when you save.
5. **Press Save.** ShellX schedules the job on this Mac, and the new card shows its next run.
6. **Press Run now** to try it right away. The card shows the run in progress, then the result. **Open log** shows what Claude did, and **Continue in terminal** reopens that Claude Code session (`claude --resume`) in a ShellX tab.

## Skills, workflows and cron jobs

ShellX Automations keeps three kinds of Claude Code automation in one place:

- **Cron job:** one prompt that runs on a schedule, unattended. This is the usual choice for reports, triage, audits and clean-ups.
- **Workflow:** an ordered list of steps, each with its own prompt, run one after another in the same Claude Code session, on demand or on a schedule. If a step fails, the run stops there.
- **Skill:** a `SKILL.md` in `~/.claude/skills/` that Claude Code loads when it's relevant in your normal chats. ShellX doesn't schedule skills; Claude Code runs them.

**Skills you already have show up too.** Every personal skill in `~/.claude/skills/` appears in Automations, including the ones ShellX didn't create. Open one and press **Draw flowchart**: Claude Code reads its `SKILL.md`, with no tools, and draws it, including the steps where it stops to ask you. That's a quick way to check what a skill you installed actually does.

## How a scheduled run works

Under the hood, nothing is hidden:

- Each scheduled job is a **launchd agent** of your user, at `~/Library/LaunchAgents/pro.shellx.automation.<id>.plist`. launchd starts it; the ShellX app doesn't have to be open.
- The job runs `claude -p` in the folder you chose, with `--permission-mode default` and `--allowedTools` set to the commands you approved. The rules you already allow in your Claude Code settings still apply.
- Claude is told it is running unattended: when it needs a decision or a permission it doesn't have, it stops and the run ends as **Needs you**, with the reason (for example *"Needs permission for: …"*) instead of guessing.
- Each Claude Code call is stopped after 2 hours (a workflow makes one call per step). If the previous run is still going, the next one is skipped rather than run twice.
- Files live in `~/.shellx/automations/<id>/`: the job, its `SKILL.md`, and the last 30 runs with their output. Deleting a job moves its folder to the Trash.
- **If your Mac is asleep** at the scheduled time, launchd starts the job once when the Mac wakes, not once per missed run. The Mac has to be on, with you logged in.

## ShellX Automations vs Claude Desktop, cloud tasks and cron

Anthropic's own options are documented in [Compare scheduling options](https://code.claude.com/docs/en/scheduled-tasks.md#compare-scheduling-options) (checked November 2026; cloud tasks are a research preview and change often).

| | ShellX Automations | Claude Desktop local tasks | Claude Code cloud tasks | cron or launchd + `claude -p` |
|---|---|---|---|---|
| Runs on | Your Mac | Your computer | Anthropic's cloud | Your computer |
| App must be open | No, launchd starts it | Yes, Claude Desktop must be running | No | No |
| Computer must be on | Yes; a missed run starts once on wake | Yes; one catch-up run on wake | No | Yes; cron skips missed runs, launchd runs once on wake |
| Your local files and tools | Yes | Yes | No, it works on a fresh clone of your GitHub repos | Yes |
| Set up by describing it | Yes, Claude Code drafts it | Yes, ask Claude in a session | Web form or `/schedule` in the CLI | No, you write the crontab or plist |
| Several steps in one session | Yes, workflows | One prompt per task | One prompt per task | If you script it |
| Flowchart of the job | Yes | No | No | No |
| Unattended permissions | Allowed commands per job | Permission mode per task, saved approvals | Auto mode by default | Whatever flags you pass |
| Plans | ShellX is free; runs on your Claude Code account | Your Claude plan | Pro, Max, Ultra, Team, Enterprise | Your Claude Code account |

**Which one to pick:**

- Choose **ShellX Automations** if the job needs your Mac's files and tools, should run without any app open, and you want to see its logic as a flowchart, chain several steps, or reuse the skills you already have.
- Choose **Claude Desktop local tasks** if you already live in Claude Desktop, keep it open all day, and want each run as a session there (it can also give each run its own Git worktree).
- Choose **cloud tasks** if the job must run while your computer is off, or should start on a GitHub event or an API call.
- Choose **plain cron or launchd** if you want no app at all and are happy to write and maintain the schedule yourself.

## Doing it by hand with cron

If you'd rather not use an app, a crontab entry works too. Set `PATH` and use full paths, because cron starts with an almost empty environment and won't find Homebrew tools such as `gh`:

```bash
# crontab -e — weekdays at 9:00
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
0 9 * * 1-5 cd "$HOME/code/web" && "$HOME/.local/bin/claude" -p "Summarize the open pull requests" --allowedTools "Bash(gh pr list:*)" >> "$HOME/pr-summary.log" 2>&1
```

Cron skips runs while the Mac sleeps; a launchd agent with `StartCalendarInterval` runs once on wake instead, which is what ShellX sets up for you, along with the log, the run history and the notification.

## FAQ

**Does ShellX have to be open for a job to run?** No. Each job is a launchd agent that starts the ShellX command-line tool directly. The app only needs to be open to create or edit jobs.

**What happens if my Mac is asleep at 9am?** launchd starts the job once when the Mac wakes. If your prompt depends on the time of day, say so in it, for example *"only summarize pull requests opened since yesterday"*.

**What can a job do while I'm away?** Only the commands you approved for it, plus what your Claude Code settings already allow. If it needs anything else, it stops and the run shows **Needs you** with the reason; you can pick the session up with **Continue in terminal**.

**Does it work with Codex or Gemini CLI?** No, Automations uses Claude Code only. You can still run Codex, Gemini CLI or any other agent in a ShellX pane and follow it from your phone: [Run Codex CLI, Gemini CLI or Aider from your phone](/guides/ai-coding-agent-on-phone/).

**Is Automations on Windows?** No. It is in the macOS app only.

**Where do I see the jobs' results?** On each card in Automations: the last run's status, **Open log**, and the history of the last 30 runs. Mac notifications tell you when a run is done, fails or needs you, depending on what you chose.
