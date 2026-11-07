---
title: Vigie PRD — addendum
created: 2026-11-06
updated: 2026-11-07
---

# Addendum: mechanisms and research behind the PRD

Technical detail that belongs to architecture or stories, kept here so it isn't lost. The architecture spine has been amended for these (AD-24 to AD-26 added, AD-6, AD-9, AD-13, AD-16, AD-18, AD-19, AD-20, AD-22, AD-23 amended); §5 records the impacts.

## 1. Away detection (FR-49)

- Input idle: seconds since the last keyboard, mouse or trackpad event for the login session (Quartz event source "seconds since last event", combined session state). Not reset by power assertions, so Keep-awake does not distort it. Believed to need no permission; confirm in a Spike.
- Additional Away signals: screen locked, screensaver started, display asleep (distributed and workspace notifications).
- Rules: Present if input within ~90 s; work time counts only while Present; break taken once Away ≥ break length; then the cycle restarts.
- Known weak spot: long passive reading or video looks Away. Acceptable for break reminders (they come late, never wrongly early).
- Rejected: camera presence (intrusive, permission, against the privacy line); time since last lock (Keep-awake makes it misleading).

## 2. Privacy mode detection (FR-55)

To verify on macOS 15 and later:
- Excluding Vigie's windows from capture (window sharing type "none") was historically the simple answer, but recent macOS versions reportedly ignore it for ScreenCaptureKit captures. Do not rely on it alone.
- Candidates: the system screen-recording indicator state, known conferencing apps sharing the screen, a CGWindow/ScreenCaptureKit query. Pick in a Spike; fall back to the manual toggle.
- Permission cost: prefer a method needing no new permission. If it needs Screen Recording, AD-20 must add it, and Vigie requests it only when automatic detection is turned on.

## 3. `vigie run` (FR-23)

- Wraps the existing generic agent CLI (SPEC §8.4): start a Session with agent name `run` and the command as title, exec the command as a child with inherited stdio, forward signals, report done or failed by exit code, then exit with the child's code.
- Must keep the hook rule's spirit: if Vigie isn't running, the command still runs normally and events spool.
- Session identity uses the terminal tab of the calling shell, so Focus works like agents.

## 4. Community scripts (FR-42 to FR-44)

- Link format: `vigie://install?url=<https URL of the .md script>`. Vigie registers the URL scheme.
- Flow: fetch over HTTPS only → parse front matter (name, author, source URL, version) → show full file, source, author → Confirmation → write to the scripts folder with source metadata.
- Updates: re-fetch source URL (at most daily) → if content differs, show diff → new Confirmation → replace. Until confirmed, the old version keeps running.
- Repository: separate GitHub repo (name TBD, e.g. `vigie-scripts`), one folder per script, PR review by the maintainer, CI that validates front matter against the script JSON schema. Public website (static, GitHub Pages, generated from the repo, with install buttons) later.
- Signing: on merge, repository CI signs each script's exact bytes with an Ed25519 key held in a protected GitHub environment and publishes a detached signature next to the file (`<script>.md.sig`). The link may also carry it (`&sig=`), which lets Vigie verify scripts hosted elsewhere. Vigie embeds a list of trusted public keys so a key can be rotated by an app update. Verification runs on install and on every update; a valid signature shows "Verified: Vigie Script repository". Implementation: Ed25519 via CryptoKit.
- Distribution with a closed-source app: the code repository can be private, but DMGs and the Sparkle appcast must be public. Options: a public releases-only GitHub repository, or a static host. Homebrew cask needs only a public download URL. AD-20 and SPEC §12 assume one public repository; amend both.
- Architecture impact: AD-16 (network only for Sparkle, opt-in providers, user scripts) must add "script install and update fetches, user-initiated or user-enabled".

## 5. Architecture spine impacts to apply

| PRD item | Spine change |
|---|---|
| FR-13 local activity log | New local store, retention 30 days; never synced; holds no secrets |
| FR-23 `vigie run` | VigieCLI command; AD-6 carve-out: `vigie run` returns the child's output and exit code; only its event send follows the socket-else-spool rule |
| FR-29 multiple Accounts | AD-23 usage identity becomes Adapter id + Account; ring per Account or per Provider to decide; Keychain items per Account |
| FR-33, FR-34 Drop zones | New Drop zone providers; text recognition uses on-device Vision |
| FR-31 non-drag paths (2026-11-07) | AD-19 `DropPayload.source` gains `.paste` (`⌘V` on the Shelf tab) and `.service` (Services entry "Stash in Vigie"); the Send to menu on Shelf items uses `.stashItem`; AD-20 Info.plist gains `NSServices`. No new target (no Share extension in v1) |
| FR-42, FR-43 script install and updates | AD-16 network allowlist; AD-18 Confirmation covers link installs and updates; URL-scheme handler |
| FR-45 to FR-49 Time module | New built-in module; Away signal as a shared host service (ModuleContext); AD-13 canonical alert kinds and sound mapping gain Timer-end and break kinds |
| FR-55 Privacy mode | A host-level display filter all modules respect (modules declare which fields are sensitive) |
| FR-55 Privacy mode permission | AD-20 may need Screen Recording (see §2) |

SPEC sections to amend: §1 (new modules), §2 and §2.1 (on hold, business model), §4.6 (AirDrop, Image to Text drop zones), §6 (alert kinds, reminder), §7 (Time module, multi-Account usage, `vigie run`), §9 (install from link, updates), §10.2 (Privacy mode), §11 (new config keys), §13 (roadmap slots), §14 (new open questions).

## 6. Market research

- [research-landscape.md](research-landscape.md): competitors, open gaps, user complaints (with sources).
- [research-macmenubar.md](research-macmenubar.md): 154 notch apps from notch.macmenubar.com, by category.
- Ideas taken from the catalogue: Time module (Crowny, Toki, FocusIsland), Keep-awake (Lidnight; already in SPEC), `vigie run` (QuakeNotch, Lynx), Privacy mode (Notchie, Stock Island), multiple Accounts (Brow), example scripts (MakerNotch, Pulse, NotchBuddy), Image to Text, formerly Copy text (Vortex, Notchet), AirDrop (NotchDrop), break reminders (HealthyNotch).
- Rejected: companions and pets, live feeds as built-ins (scripts cover them), teleprompter, screen time, local models.
