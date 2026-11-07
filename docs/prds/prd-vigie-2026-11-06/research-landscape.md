# Vigie: competitive landscape research

Date: 2026-11-06. Method: web search, vendor pages, the GitHub REST API (stars, push dates, latest releases, pulled on 2026-11-06), GitHub issue lists and the HN Algolia search. Star counts and dates come from the GitHub API unless marked otherwise. Vendor marketing claims are flagged where they could not be checked.

## TL;DR

- **The market has split in two, and the halves are starting to merge.** General notch apps (NotchNook, boring.notch, Alcove, DynamicLake, Atoll, MediaMate) do media, shelf and calendar. A crowded wave of agent notch apps appeared in 2026 (Vibe Island, CodeIsland, Vibe Notch/Claude Island, MioIsland, notchi, Open Island, Ping Island, Notchcode, Claude Pulse and 15+ smaller ones). They do agent status and approvals. Few products do both, and the ones that do (Crowny, NotchNook Pro, Topsoil) are closed source or brand new.
- **Closest competitors to Vigie:**
  1. **Crowny** ($5, closed): agents plus notes, shelf, calendar, clipboard and 15+ panels. This is almost exactly Vigie's feature set.
  2. **CodeIsland (wxtsky)** (MIT, free, 2.6k stars, released 2026-10-28): the strongest open-source agent notch app, covering 30+ agents, opt-in plan limits and iPhone/Watch companions.
  3. **Vibe Island** ($19.99, closed): the commercial leader on agent coverage, terminal jump and multi-provider quota.
  4. **NotchNook Pro** (€19 lifetime or €3/month): the biggest general notch app. Its pricing page now lists "approve Claude Code and Codex from the notch".
  5. **boring.notch / Atoll** (GPL-3.0, 11.3k and 5.2k stars): the open-source general notch incumbents, with no agent features.
- **Usage tracking is mostly done by menu-bar apps:** CodexBar (23k stars), ccusage (19k), Claude-Code-Usage-Monitor (8.8k), OpenUsage (4.6k) and Claude-Usage-Tracker (3.8k). Plan-usage data relies on an undocumented Anthropic OAuth endpoint that has had aggressive 429 rate limiting. Treat that as a platform risk.

---

## 1. General notch apps

| App | Price model | Open source | Standout features | Activity / maintenance |
|---|---|---|---|---|
| **NotchNook** (lo.cafe) | Pro: €19 lifetime or €3/mo. Classic: €14 lifetime or €2/mo. 48 h trial, license covers 2 Macs, 7-day refund. Also on Setapp. Older press: $25 one-time for 5 devices. | No | Pro: Liquid Glass notch, Live Activities, Pocket and Clipboard, **approve Claude Code and Codex from the notch**, teleprompter and terminal, lyrics, Pomodoro and to-dos, file converter. Classic: music, calendar, Nook widgets, Tray with AirDrop, camera mirror. | Active. A new Pro tier launched, and Classic is at v1.6.20. Pro is Apple-silicon only, macOS 14.6+. |
| **boring.notch** (TheBoredTeam) | Free | Yes, GPL-3.0 | Music with visualizer, calendar, file shelf with AirDrop (derived from NotchDrop), HUD replacement. Roadmap: weather, lock-screen widgets, extension system, notifications. | 11.3k stars. Pushed 2026-11-06. **Last tagged release v2.7.3 on 2025-11-24**, with nightly/pre-release builds since. 265 open issues and 159 open PRs. Not notarized: no Apple Developer account, so users get a Gatekeeper warning. |
| **Atoll** (Ebullioscopic) | Free, donations through GitHub Sponsors and Buy Me a Coffee | Yes, GPL-3.0 | boring.notch-derived. Media, Live Activities, lock-screen widgets, CPU/GPU/RAM stats, timers, clipboard, color picker, calendar, gestures. Credits OpenUsage for **LLM usage tracking**. | 5.2k stars. Pushed 2026-11-06, release v2.3.3 on 2026-07-24. 234 open issues. |
| **Alcove** | $12.99 one-time (third-party sources say $5 to $17). 48 h trial according to a German review. | No | Polished Dynamic Island look: transitions, Live Activities, HUDs, lock-screen widgets, AirPods. Style over utility. | v1.7, macOS 15+. Release date not shown. |
| **DynamicLake (Pro / DynamicLake 2)** | About $16.90 one-time for 3 Macs (MakerStack review). 30-day money-back, frequent 15 to 20% promos. | No | Notifications, drag and drop, file converter, calls, AirDrop, timer, miniLake mode, Liquid Glass, **new "Plugins & Market"**. | Active. DynamicLake 2 and the plugin market are recent. |
| **MediaMate** | One-time, roughly €6.99 or $5, pay-what-you-want at times (sources conflict) | No | Replaces volume and brightness HUDs, adds now-playing to the notch. Narrow scope. | No recent news found. |
| **TopNotch** | Free (one roundup says $5 Pro) | No | Hides the notch with a black menu bar. An anti-notch tool, not a notch app. | Mac App Store listing. Low activity. |
| **NotchDrop** (Lakr233) | Free | Yes, MIT | File drop shelf with AirDrop. Upstream of boring.notch's shelf. | 2.1k stars, pushed 2026-05-18. |
| **MewNotch** | Free | Yes | HUD replacement, plus a **Bash Script View** that runs one shell command in the expanded notch. This was the only script-in-notch feature found. | Stats not retrieved (API rate limit). |
| **Bartender Pro** | Paid | No | Added widgets, clipboard and file storage to the notch (MacRumors thread). | Notable as a bigger incumbent moving into the space. |
| **DynamicNotchKit** (MrKai77) | Free library | Yes, MIT | SwiftUI library for notch UIs. Could serve as a building block. | 478 stars, release 1.1.0 on 2026-04-05. |

Takeaways:
- Pricing has settled at **$5 to $25 one-time**, with €2 to €3/month as an option. Nobody runs donationware with a notarized build except some OSS projects, and boring.notch is not notarized.
- **Extensibility is the next battleground.** DynamicLake shipped a plugin market, the boring.notch roadmap has an "extension system" and an open "API support" issue (#1747), and MewNotch has one bash view. No notch app has a SwiftBar/xbar-style script-plugin folder.

## 2. Notch and menu-bar tools for AI coding agents

### 2a. Agent notch apps (session status, approvals, jump to terminal)

| App | Price | Open source | Agents | Standout features | Activity |
|---|---|---|---|---|---|
| **Vibe Island** (vibeisland.app) | $19.99 one-time for 1 Mac, 1 year of updates (app keeps working after). 2- to 5-day trial. `brew install --cask vibe-island` | No. The GitHub repo is an issue tracker only. | 25 to 30: Claude Code, Codex CLI and Desktop, Gemini CLI, Cursor, OpenCode, Droid, Kiro, Kimi and more | Approve, deny and answer questions from the notch. Plan review with Markdown. Jump across 20+ terminals and tmux. **SSH remote**. 8-bit sounds. **Quota for Claude, Codex, Kimi, GLM and DeepSeek**. Fully local, no telemetry. Native, under 100 MB RAM. | Very active (custom-agents beta 1.0.55). 97 open issues. Runs SEO "best notch apps" pages. |
| **CodeIsland** (wxtsky) | Free | Yes, MIT | 30+ including Claude Code, Codex, Gemini CLI, Cursor, OpenCode, Copilot CLI, Qwen, Kiro, plus custom hooks. Claude Desktop Cowork. | Live status, current tool, last reply, progress bar, git branch and worktree. Approve, deny or always-allow. Multi-question answers. Jump to terminal, IDE, tmux, zellij or Herdr. **Opt-in 5-hour and weekly Claude plan limits**. Quiet hours. SSH. **iPhone/Watch Buddy app** and an ESP32 desk buddy. Webhooks. Sparkle updates. | 2,557 stars. Created 2026-04-06, release v1.0.41 on 2026-10-28. Only 8 open issues. **Strongest OSS competitor.** |
| **Vibe Notch** (formerly **Claude Island**, farouqaldori) | Free | Yes, Apache-2.0 | Claude Code only | The original. Notch overlay, multi-session, approve and deny, chat history with Markdown. Auto-installs hooks over a Unix socket. Mixpanel analytics. | 2,529 stars. **Last push and release v1.3.2 on 2026-04-20.** About 6.5 months idle, 59 open issues and PRs. Effectively stalled. |
| **MioIsland** (MioMioOS, formerly xmqywx/CodeIsland) | Free for personal use | Source-available, **CC BY-NC 4.0** | Claude Code (Codex mentioned) | Fork of Claude Island. Approvals, jump across 10+ terminals including cmux and Ghostty. **"Code Light" iPhone companion** with remote launch. Buddies and pixel cat. | 541 stars, pushed 2026-10-13, v3.1.3 on 2026-08-13. |
| **notchi** (sk-ruban) | Free | Yes, GPL-3.0 | Claude Code and Codex | Animated sprite per session that reacts to activity. Quick replies. Reads Claude's OAuth token from Keychain (asks for keychain permission on first launch). | 1,047 stars, pushed 2026-10-04. Open issues are mostly feature requests (multi-sprite, remote, external monitor). |
| **Open Island** (Octane0411/open-vibe-island) | Free | Yes, GPL-3.0 | Claude Code, Codex, Cursor, OpenCode and more | Status, approvals, jump. Hooks fail open, so agents keep running if the app closes. | Stats not retrieved. |
| **Ping Island** (erha19) | Free | Yes | Claude, Codex, Gemini, Qwen, OpenCode and more | Pitched as an open alternative to Vibe Island. Event filtering, SSH, usage analytics, draggable "Buddy". | v0.5.x. Stats not retrieved. |
| **Notchcode** | Free | Yes, MIT (per Product Hunt) | Claude Code and Codex | Notch on Mac, **top-center pill on Windows**. Jump to the waiting terminal. Weekly usage versus budget. No telemetry. | Launched on Product Hunt 2026-06-15 (84 upvotes). |
| **Claude Pulse** | Free | No | Claude Code only | Approvals, multi-session, live 5-hour and weekly limits from the CLI's Keychain credentials. macOS 15+, Apple silicon. | Active as of Sept 2026, with a changelog and blog. |
| **Crowny** (crowny.lol) | **$5 one-time** (down from $15), 1 Mac, 14-day refund | Not stated, likely closed | Claude Code, Codex, Grok | **Hybrid, the closest to Vigie.** Agent status faces, approve and deny, answer questions, Claude usage (session and weekly, reset times, spend). Also Today/calendar with Meet join, **Notes (Obsidian vault)**, **Shelf**, clipboard, music, weather, reminders, GitHub, Mail, Home Assistant, timers, wellbeing reminders, mini-games, voice input. A dev SDK (`@crowny/app`: `notch.progress/ask/done`). Apple silicon, macOS 15+. | v0.2.5 first build in Sept 2026, launched Oct 2026. Site still says "almost ready". |
| **Topsoil** | Unknown | Unknown | Claude Code, Codex, Cursor CLI | **Hybrid.** Agent terminal panes plus now playing, calendar, battery/CPU/RAM, and a "pixel plant" that grows while agents run. | Show HN on 2026-07-13 (1 point). |
| **AgentNotch** (AppGram) | Free | No license file | Claude Code and others | Live tool calls, file ops, shell commands, token usage, cost estimates. | 221 stars, **last push 2026-01-19**. Stale. |
| **CodeIsland forks and lookalikes**: rifqiakrm/code-island (GPL-3.0, 9 stars, v1.4.10 July 2026), luokebi/coder-island (11 stars, idle since April), Lision/CodeIsland, NotchBar, notch-so-good, claude-notch (65 stars, active Nov 2026), Buddi (GPL-3.0), ClaudeNotch (non-commercial source-available), NotchClaude (closed, usage only), Notchy, Notchly, Notchling, Runnock (paid, macOS 26+), NotchCode ($19.99, notchcode.pages.dev), AgentPeek, Arcade Agents, Coucou, Crest, Fetch, DockTerm, Notch Pilot | Mostly free | Mixed | Mostly Claude Code, some Codex | Variations on status plus approvals plus mascot. | HN Show posts in 2026 all got 1 to 9 points. The niche is saturated with low-traction clones. |

### 2b. Usage and quota trackers (menu bar or CLI)

| Tool | Price | OSS | Scope | Activity |
|---|---|---|---|---|
| **CodexBar** (steipete) | Free | MIT | 100+ providers (Codex, Claude, Cursor, Gemini, Copilot, OpenRouter…). Session, weekly and monthly windows, reset countdowns, cost scans, provider-status incident badges, WidgetKit widgets, CLI, Linux Qt app. **No notch.** | **23,039 stars**, v0.83.0 on 2026-10-31. Very active. The usage incumbent. |
| **ccusage** | Free | Yes | CLI cost and usage report from local Claude Code (and other) logs | 19.3k stars, v20.0.48 on 2026-11-02 |
| **Claude-Code-Usage-Monitor** (Maciek-roboblog) | Free | MIT | Terminal real-time token, burn-rate and limit predictions | 8.8k stars, v4.0.0 on 2026-06-27 |
| **OpenUsage** (robinebers) | Free | MIT | Subscription usage across AI tools (Atoll uses it) | 4.6k stars, pushed 2026-11-06 |
| **Claude-Usage-Tracker** (hamed-elfayome) | Free | MIT | Claude limits, multiple profiles, Claude Code auto-detect | 3.8k stars, v3.3.0 on 2026-08-29 |
| **claude-statistics** (sj719045032) | Free | MIT | Claude Code, Codex and Gemini CLI stats plus notch active-sessions view, resume in terminal. Not notarized. | 48 stars, v3.6.1 on 2026-09-14 |
| Small ones: agent-tracker, cli-usage-bar, usage (aqua5230, local-logs only), LLimit (multi-account), tokentap, codex-meter, notch-limits | Free | Mostly MIT | Claude plus Codex 5-hour and weekly windows | Low stars. Some idle since spring 2026. |

**How usage data is obtained (risk):** tools either (a) read the Claude CLI OAuth token from Keychain and poll the undocumented `api.anthropic.com/api/oauth/usage` endpoint, (b) parse local JSONL transcripts or statusline output, or (c) use browser cookies. A Claude Code bug report (opened 2026-03-06, closed 2026-06-01) said the endpoint returned **429s so aggressively that polling was unusable**, with no Retry-After header. Anthropic also tightened how third-party apps on subscription OAuth are billed (April and May 2026 reports). Local-file parsing is the safer default, and network polling should be opt-in (CodeIsland already does this).

## 3. User complaints (issues, HN, Reddit)

**Agent notch apps**
- **Stability and resources:** Vibe Notch #112, "memory leak grows to ~64 GiB overnight, freezes macOS". boring.notch #1637 (high memory) and #1744 (dropped files never cleaned up, 14 GB).
- **State desync:** Vibe Notch #98 (stuck on "Processing…" after a background Bash), #11 (no session detected), #18 (alert fires on context resume).
- **Wrong jump target:** Vibe Island #260, #256, #236 and #248 (VS Code, tmux, Remote-SSH, multiple Claude instances).
- **Quota accuracy:** Vibe Island #259 (Codex spend understated 25x), #254 (Claude usage error), #250 (missing quota for CLI-only users), #233 (disabled provider still shown).
- **Hook hygiene:** Vibe Island #245 (an update re-adds its hook over a user-replaced one), #251 (statusline wrapper drops args), #265 (no hook timeout, so a stalled SSH tunnel freezes the agent). Vibe Notch #7 asks for hooks to ship as a Claude Code plugin rather than as edits to `~/.claude`.
- **Screen real estate:** Vibe Notch #41 and #100 (UI too large, covers Chrome tabs), #58 (wants a menu-icon mode), #19 (screen choice), #32 (cursor moves when the window retracts). notchi #24 (external monitors).
- **Multi-account:** Vibe Island #249 (separate `CLAUDE_CONFIG_DIR`s merged).
- **Trust and install friction:** many OSS apps are not notarized (boring.notch, claude-statistics) and need Gatekeeper bypass. Vibe Notch and Claude Visor ship Mixpanel or anonymous analytics. notchi requires a Keychain "Always Allow" prompt.
- **Saturation and fatigue:** a dozen-plus Show HN notch-for-Claude posts in 2026 drew 1 to 9 points each, and the Reddit Notchly post drew 1 point and 5 comments. Novelty is gone, so a new entrant needs a clear differentiator.

**General notch apps**
- boring.notch: the notification mirroring feature is buggy on nightly builds (#1577, #1586, #1602, #1605). Now Playing adapter keeps running after quit (#1728). Non-notch sizing (#1689). macOS 27 Accessibility rename (#1561). Users ask for an **API** (#1747) and a Dropover-style floating shelf (#1572).
- Reviews frame Alcove as pretty but light, and NotchNook as functional but pricier with a subscription option. Reported Alcove prices vary widely ($5 to $17).

## 4. Open positions and gaps for Vigie

1. **An open-source hybrid "dev notch".** OSS agent apps (CodeIsland, notchi, Open Island) do agents only. OSS general apps (boring.notch, Atoll) do media and shelf only. The hybrids (Crowny, NotchNook Pro, Topsoil) are closed or unproven. Nobody offers a **GPL, notarized, agents plus notes, shelf, calendar and scripts** app. This is Vigie's clearest slot.
2. **Script and plugin widgets (xbar/SwiftBar model in the notch).** No notch app has a folder-of-scripts plugin system. DynamicLake has a closed market, boring.notch only has a roadmap item, and MewNotch shows a single bash view. Developers already know xbar's stdout format, so Vigie could reuse it. CI status, deploys and on-call widgets would come for free.
3. **Usage in the notch, done safely.** Usage is fragmented in menu-bar apps (CodexBar) or tied to a single agent. Vigie could do a unified Claude, Codex and Gemini plan meter that is **local-first** (JSONL and statusline parsing), with opt-in network polling and backoff, and that tolerates the undocumented endpoint changing. Accuracy complaints (Vibe Island #259 and #254) show users notice wrong numbers.
4. **Non-invasive, reversible hooks.** Users dislike apps that rewrite `~/.claude` hooks, override user edits and lack timeouts. Vigie could ship hooks as a **Claude Code plugin** (Vibe Notch #7) with fail-open and timeouts, plus an uninstall that restores the original config.
5. **Restraint and small footprint.** Memory leaks and oversized overlays are the top complaints. Clear options would help: a compact mode, per-display placement, a menu-bar fallback for notch-less displays, and quiet hours or focus awareness for "done" pings.
6. **Trust signals as a feature.** Notarized builds, no telemetry by default and a GPL license. Most OSS rivals miss at least one of these (unsigned builds, Mixpanel, CC BY-NC).
7. **Maintenance vacuum at the original.** Claude Island/Vibe Notch has the brand recognition (2.5k stars) and has been idle since April 2026. Some of its users are looking for a maintained, broader successor. CodeIsland is currently absorbing them.
8. **Watch-outs:**
   - CodeIsland is free, MIT, fast-moving and already covers 30+ agents, phone companions and plan limits. Vigie should not try to beat it on agent breadth alone.
   - Crowny at $5 already ships the hybrid bundle.
   - NotchNook Pro is adding agent approvals.
   - Anthropic or OpenAI could ship native status surfaces, such as the Codex Desktop app and Claude Desktop Cowork, which reduce the need for terminal-only monitoring.

## Sources

General notch apps
- NotchNook pricing and Pro features: https://lo.cafe/notchnook
- NotchNook $25 coverage: https://www.imore.com/apps/mac-apps/this-dollar25-app-gives-my-macbook-pro-a-dynamic-island-and-it-was-worth-every-penny , https://www.lowyat.net/2024/327211/notchnook-dynamic-island-macbooks-us25/
- boring.notch: https://github.com/TheBoredTeam/boring.notch , issues: https://github.com/TheBoredTeam/boring.notch/issues
- Atoll: https://github.com/Ebullioscopic/Atoll
- Alcove: https://tryalcove.com/ , https://www.macobserver.com/tips/round-ups/notchbook-vs-alcove-what-macbook-notch-app-is-actually-worth-using-in-2026/ , https://www.ifun.de/alcove-bringt-das-dynamic-island-auf-den-mac-246561/
- DynamicLake: https://dynamiclake.com/ , https://makerstack.co/reviews/dynamiclake-review/
- MediaMate: https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/ , https://www.bgr.com/2177168/apps-that-make-macbook-notch-useful/ , https://www.producthunt.com/products/mediamate
- TopNotch: https://apps.apple.com/nz/app/top-notch/id1367977894 , https://sourceforge.net/app/topnotch/mac/
- NotchDrop: https://github.com/Lakr233/NotchDrop
- MewNotch: https://github.com/monuk7735/mew-notch
- Bartender Pro notch: https://forums.macrumors.com/threads/bartender-pro-brings-widgets-clipboard-and-file-storage-to-the-macbook-notch.2482292/
- DynamicNotchKit: https://github.com/MrKai77/DynamicNotchKit
- SwiftBar (plugin model reference): https://github.com/swiftbar/SwiftBar

Agent notch apps
- Vibe Island: https://vibeisland.app/ , https://vibeisland.app/codex , https://vibeisland.app/best-ai-agent-notch-apps/ , issues: https://github.com/vibeislandapp/vibe-island/issues
- CodeIsland: https://github.com/wxtsky/CodeIsland , https://dev.to/krisying/i-turned-my-macbooks-notch-into-a-control-center-for-ai-coding-agents-2o57
- Vibe Notch / Claude Island: https://github.com/farouqaldori/vibe-notch , issues: https://github.com/farouqaldori/vibe-notch/issues
- MioIsland: https://github.com/MioMioOS/MioIsland
- notchi: https://github.com/sk-ruban/notchi , issues: https://github.com/sk-ruban/notchi/issues
- Open Island: https://github.com/Octane0411/open-vibe-island
- Ping Island: https://erha19.github.io/ping-island
- Notchcode: https://www.producthunt.com/products/notchcode , https://hunted.space/product/notchcode
- NotchCode (paid): https://notchcode.pages.dev/
- Claude Pulse: https://claudepulse-5bw.pages.dev/
- Crowny: https://www.crowny.lol/ , https://chatgate.ai/post/crowny
- Topsoil: https://news.ycombinator.com/item?id=48886544
- AgentNotch: https://github.com/AppGram/agentnotch
- Others: https://github.com/rifqiakrm/code-island , https://github.com/luokebi/coder-island , https://github.com/lukataylo/NotchBar , https://github.com/deepshal99/notch-so-good , https://github.com/rawsun007/claude-notch , https://agentpeek-web.pages.dev/permissions/ , https://www.producthunt.com/products/runnock , https://www.producthunt.com/products/arcade-agents , https://alphasignal.ai/news/coucou-puts-claude-code-agent-approvals-inside-your-mac-s-notch , https://feedbagel.com/post/buddi-open-source-macbook-notch-utility-for-claude-code-companion , https://notchy.pages.dev/
- HN search (Show HN traction): https://hn.algolia.com/api/v1/search?query=notch%20claude%20code&tags=story

Usage trackers
- CodexBar: https://github.com/steipete/CodexBar
- ccusage: https://github.com/ccusage/ccusage
- Claude-Code-Usage-Monitor: https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor
- OpenUsage: https://github.com/robinebers/openusage
- Claude-Usage-Tracker: https://github.com/hamed-elfayome/Claude-Usage-Tracker
- claude-statistics: https://github.com/sj719045032/claude-statistics
- agent-tracker: https://github.com/rylgyl/agent-tracker ; cli-usage-bar: https://github.com/svenedik/cli-usage-bar ; usage: https://github.com/aqua5230/usage ; LLimit: https://github.com/githajae/LLimit ; tokentap: https://github.com/sebasrodriguez/tokentap
- notch-limits: https://www.tabnews.com.br/martinscode/pitch-notch-limits-os-limites-do-claude-code-e-do-codex-no-notch-do-mac-lidos-do-que-os-clis-ja-gravam-em-disco

Platform risk
- OAuth usage endpoint 429 bug: https://claudeissues.com/issue/31637-bug-api-oauth-usage-endpoint-aggressively-rate-limits-making-usage-monitoring-un
- Third-party OAuth routing and billing: https://claudeissues.com/issue/45123-bug-anthropic-api-error-third-party-app-routing-for-claude-max-oauth-sessions
- Shared Claude and Claude Code limits: https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan

## Caveats
- Several stats (MewNotch, Open Island, Ping Island) were not retrieved because of the GitHub API rate limit.
- The NotchNook Pro "approve Claude Code and Codex" claim comes from lo.cafe's pricing page and was not seen in press coverage.
- Crowny's open-source status and release state are unclear.
- The vibeisland.app roundup is competitor marketing.
