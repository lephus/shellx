# Task 12 one-off: classify vi values spelled like the English into identityLocales.vi reasons.
import json, re, sys
keys = json.load(open(sys.argv[1]))
R = {
 "brand": "Product, agent, plan or app name is invariant in Vietnamese; the translated entry is still required.",
 "term": "English UI or developer term Vietnamese ShellX keeps as-is (glossary: terminal, tab, agent, prompt, commit, branch, fork, log, OK, Cloud VM); the translated entry is still required.",
 "syntax": "Command-line, socket or config syntax, field names and output columns are invariant; the translated entry is still required.",
 "format": "Placeholder-only format, number, unit abbreviation or symbol; nothing to translate in Vietnamese. The translated entry is still required.",
 "debug": "Debug-only lab label or preset name kept in English for developers; the translated entry is still required.",
}
brand = re.compile(r"^(agent\.|agentSession\.provider\.|taskManager\.agent\.|sessionIndex\.agent\.|machines\.agent\.|command\.cmuxConfig\.default|textbox\.submitAction\.|settings\.textBox\.submitAction\.|cli\.codexMonitor\.notification|cli\.claude-hook\.notification|menu\.help\.codexTeams|agentInbox\.plan|settings\.account\.max|pricing\.|sidebar\.account\.teamWith|cli\.vm\.resize\.planName|sidebar\.template\.|sidebar\.help\.githubIssues|simulator\.location|featureFlags\.computerUseUX|settings\.section\.computerUse|computerUse\.onboarding)")
debug = re.compile(r"^(debug\.|feed\.buttonDebug\.|feed\.textEditorDebug\.)")
syntax = re.compile(r"^(cli\.|socket\.|config\.validation\.|glaeda\.|sidebar\.custom\.validation)")
fmt_only = re.compile(r"^[\s%@$\d.,:·~+()/\-a-zA-Z•⚠↳\[\]]*$")
out = {}
for key in keys:
    if debug.search(key): out[key] = R["debug"]
    elif brand.search(key): out[key] = R["brand"]
    elif syntax.search(key): out[key] = R["syntax"]
    elif re.search(r"(relativeTime|countdown|usage\.period|hiddenWebViewDiscardDelay\.(minutes|seconds|minutesSeconds)|widthPoints|paneResizeStep\.value|provisionedCPU|estimatedCost|tagged|headerLabel|teamRowLabel|settingsLabel|glyph\.tooltip|requester_value|\.port\.title)", key): out[key] = R["format"]
    else: out[key] = R["term"]
json.dump(out, open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
import collections; print(collections.Counter(v[:12] for v in out.values()))
for k, v in out.items():
    if v == R["term"]: print("TERM", k)
