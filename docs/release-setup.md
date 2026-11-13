# Release setup: what the maintainer does by hand

Stories 6.1, 6.2, 6.3 and 6.5 (AD-17, AD-20, SPEC §12, A49, A86). The build settings for signing are committed in
`App/Config/Signing.xcconfig`; everything below lives in Apple's portals, the maintainer's keychain or GitHub and
cannot be committed. Romain owns every step. Do them in order: later steps use what earlier ones create.

Status is for Romain's Mac mini "Sirius" as of 2026-11-12.

| # | Step | Status |
|---|------|--------|
| 0 | Baguette Labs team (`BWMPMACCYZ`) signed in to Xcode, Apple Development certificate of that team in the login keychain | Done |
| 1 | Register this Mac as a device, let Xcode create the `.dev` App ID and Development profile | To do |
| 2 | Developer ID Application certificate (Account Holder only) | To do (account transfer in progress) |
| 3 | Explicit App ID `fr.baguettelabs.vigie` | To do |
| 4 | Developer ID provisioning profile `Vigie Developer ID` | To do (needs 2 and 3) |
| 5 | App Store Connect API key for `notarytool` | To do |
| 6 | Sparkle EdDSA key pair | To do |
| 7 | GitHub organization name (A49), public releases-only repository and its token | To do |
| 8 | GitHub `release` environment and its secrets | To do (needs 2 to 7) |

## 0. Team and Apple Development identity (Done)

Xcode › Settings › Accounts lists the maintainer's Apple ID with the team **Baguette Labs** (`BWMPMACCYZ`). The login
keychain has `Apple Development: ROMAIN HUGO MICHEL GONCALVES (78GQ79YW3X)` (SHA-1 `1CFEAEC7…FE2`, certificate OU
`BWMPMACCYZ`). The other identity, `Apple Development: Romain Gonçalves (4N5C2VUHK8)`, belongs to another team
(`SL52497QTV`) and must not sign Vigie.

On a new Mac: Xcode › Settings › Accounts › Baguette Labs › Manage Certificates… › + › Apple Development.

## 1. Dev signing on this Mac: device, `.dev` App ID and Development profile (To do)

Debug builds (`fr.baguettelabs.vigie.dev`, "Vigie Dev") use automatic signing: Xcode registers the explicit App ID
and creates and renews the Mac App Development profile itself. No profile is downloaded by hand. A Development
profile only installs on registered Macs, so this Mac must be registered once.

1. Once per Mac, in the repository: `Scripts/dev-signing.sh --team BWMPMACCYZ` (writes the gitignored
   `App/Config/Signing.local.xcconfig`: Debug becomes automatic signing for the team with
   `Vigie.signed.entitlements`). Done in the Story 6.1 worktree; the main checkout still has the older identity-only
   file and needs the same command after the merge.
2. Register the Mac, one of:
   - Command line (registers the device, the App ID and creates the profile in one go):
     `cd App && xcodegen generate && xcodebuild -project Vigie.xcodeproj -scheme Vigie -configuration Debug build -allowProvisioningUpdates -allowProvisioningDeviceRegistration`
   - Or open `App/Vigie.xcodeproj` in Xcode › target Vigie › Signing & Capabilities (Debug) › **Register Device**.
   - Or by hand: developer.apple.com › Account › Certificates, IDs & Profiles › Devices › + › Platform macOS,
     Device Name `Sirius`, Device ID (UDID) `00006020-001641040298C01E` (System Information › Hardware ›
     Provisioning UDID) › Continue › Register; then build once with `-allowProvisioningUpdates`.
3. Check: `codesign -d --entitlements - "<DerivedData>/Build/Products/Debug/Vigie Dev.app"` shows
   `keychain-access-groups` = `BWMPMACCYZ.fr.baguettelabs.vigie.dev` plus `BWMPMACCYZ.fr.baguettelabs.vigie.notes`
   (the notes key group shared with the release build, AD-9) and
   `com.apple.application-identifier` = `BWMPMACCYZ.fr.baguettelabs.vigie.dev`; Vigie Dev no longer shows the
   "Secrets are unavailable in this build" setup problem.

Other contributors without the team keep ad-hoc Debug builds (no `Signing.local.xcconfig`, or
`Scripts/dev-signing.sh` without `--team` for a stable identity only); SecretStore then reports "unavailable".

## 2. Developer ID Application certificate (To do)

Only the **Account Holder** of the Baguette Labs membership can create it, and an account has at most five.
**Account transfer caveat:** while the Account Holder role is being transferred, the Developer ID option is
greyed out or refused for everyone else. Create the certificate once the transfer is complete, signed in as the
account that is then the Account Holder, so the person who can revoke and renew it is the final one. Its name will
read `Developer ID Application: Baguette Labs (BWMPMACCYZ)`.

Create it on the portal from a certificate signing request, so the private key is in your keychain and can be
exported for CI (not through Xcode's cloud-managed signing, whose key never leaves Apple):

1. Keychain Access › Certificate Assistant › Request a Certificate From a Certificate Authority… › your email,
   Common Name `Baguette Labs Developer ID`, Saved to disk › Continue.
2. developer.apple.com › Account › Certificates, IDs & Profiles › Certificates › + › **Developer ID Application**
   › Continue › Profile Type **G2 Sub-CA (Xcode 11.4.1 or later)** › choose the `.certSigningRequest` › Continue ›
   Download, double-click the `.cer` (login keychain).
3. Check: `security find-identity -v -p codesigning` lists
   `Developer ID Application: Baguette Labs (BWMPMACCYZ)`.
4. Export for CI: Keychain Access › login › My Certificates › right-click the Developer ID Application identity ›
   Export… › `.p12`, with a strong password. `base64 -i DeveloperID.p12 | pbcopy` gives `DEVELOPER_ID_P12`, the
   password is `DEVELOPER_ID_P12_PASSWORD` (step 8). Keep the `.p12` in your password manager and delete the file.

## 3. Explicit App ID for the release bundle (To do)

developer.apple.com › Certificates, IDs & Profiles › Identifiers › + › App IDs › Continue › App › Continue:
Description `Vigie`, Bundle ID **Explicit** `fr.baguettelabs.vigie` › Continue › Register. No capability box to
tick: Keychain Sharing on macOS is the `keychain-access-groups` entitlement, which every profile of the team
authorises as `BWMPMACCYZ.*`.

## 4. Developer ID provisioning profile `Vigie Developer ID` (To do)

developer.apple.com › Profiles › + › Distribution › **Developer ID** › Continue › Profile Type **Mac** › App ID
`Vigie (BWMPMACCYZ.fr.baguettelabs.vigie)` › Continue › the Developer ID Application certificate of step 2 ›
Continue › Provisioning Profile Name **`Vigie Developer ID`** (exact: `PROVISIONING_PROFILE_SPECIFIER` in
`App/Config/Signing.xcconfig`) › Generate › Download.

- Check: `security cms -D -i "Vigie_Developer_ID.provisionprofile"` shows `keychain-access-groups` containing
  `BWMPMACCYZ.*` (the wildcard covers the notes group `BWMPMACCYZ.fr.baguettelabs.vigie.notes`) and
  `com.apple.application-identifier` `BWMPMACCYZ.fr.baguettelabs.vigie`.
- To build Release on this Mac, double-click the profile (installs it), then
  `xcodebuild -project App/Vigie.xcodeproj -scheme Vigie -configuration Release build`.
- For CI: `base64 -i Vigie_Developer_ID.provisionprofile | pbcopy` gives `DEVELOPER_ID_PROFILE` (step 8).
- The profile expires with the certificate; regenerate it (same name) when you renew the certificate.

## 5. App Store Connect API key for notarization (To do)

appstoreconnect.apple.com › Users and Access › Integrations › App Store Connect API › Team Keys (the first time,
the Account Holder clicks Request Access and accepts the terms) › + (Generate API Key): Name `Vigie notarytool`,
Access **Developer** (the least role `notarytool` accepts) › Generate.

- Download the `.p8` right away: Apple offers it **once**. Its contents are `ASC_KEY_P8`.
- Key ID (the row) is `ASC_KEY_ID`; Issuer ID (above the table) is `ASC_ISSUER_ID`.
- Check: `xcrun notarytool history --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER>` answers with an
  empty history.

## 6. Sparkle EdDSA keys (To do)

One Ed25519 key pair signs every update zip and appcast (Story 6.3) and the price table (Story 6.5). The
public key is built into the app; the private key exists only in your password manager and the `release`
environment.

1. Get the pinned Sparkle tools (the same 2.10.1 release the app links, checked by SHA-256):
   `BIN="$(Scripts/release/sign-update.sh tools)"` prints their folder.
2. `"$BIN/generate_keys"`: creates the key pair in your **login keychain** (item "Private key for signing Sparkle
   updates", account `ed25519`) and prints the public key. If a key already exists there it is reused, not
   replaced: never run it on a Mac whose keychain holds another project's Sparkle key unless you add
   `--account vigie` (then pass the same `--account` to `-x` below).
3. `"$BIN/generate_keys" -x sparkle_private_key.txt`: exports the private key (base64 of the 32-byte seed). Its
   contents are the `SPARKLE_PRIVATE_KEY` secret (step 8). Keep a copy in your password manager, then delete the
   file. Losing it means installed copies can no longer accept updates; leaking it means anyone can sign one.
4. Public key into the app: in `App/Config/Updates.xcconfig` set `VIGIE_SPARKLE_PUBLIC_KEY = <public key>` (the
   base64 string `generate_keys` printed; `"$BIN/generate_keys" -p` prints it again) and commit. It is not a secret.
   If the printed key contains `//`, delete the keychain item and generate again: an xcconfig reads `//` as the
   start of a comment and would cut the key short (`sign-update.sh check-config` refuses such a key).
   Release builds then carry it as `SUPublicEDKey`. Debug (`Vigie Dev`) never gets it: dev builds do not update.
   Cross-check: `SPARKLE_PRIVATE_KEY="$(cat sparkle_private_key.txt)" Scripts/release/sign-update.sh public-key`
   prints the same string (needs Homebrew `openssl`, OpenSSL 3).
5. Optional: remove the keychain item once the private key is in the password manager and GitHub; signing never
   needs the keychain (`sign-update.sh` passes the secret to `sign_update --ed-key-file -` on stdin).

With an empty `VIGIE_SPARKLE_PUBLIC_KEY` the app logs "updater off in this build" once, never starts Sparkle and
makes no update request; Settings › Updates shows "Updates are not set up in this build." `release.yml` refuses to
build a release in that state (step "Updater configured for this release host").

## 7. GitHub organization, public releases repository and its token (To do, A49, A86)

Choose the organization that hosts the private code repository, the public releases-only repository
(`<org>/vigie-releases`, SPEC §12.1) and the Homebrew tap (`<org>/homebrew-vigie`). The appcast URL and the cask
are built from it (Stories 6.2, 6.3).

**Public release host (decided 2026-11-06, SPEC §12.1, AD-20):** a separate **public** GitHub repository that only
holds releases. GitHub Releases of the private code repository are not an option: visitors without access to the
code cannot see them, so Sparkle and Homebrew could not download anything. `release.yml` publishes there with a
token, and the private repository's own `GITHUB_TOKEN` stays read-only.

0. In `App/Config/Updates.xcconfig` replace the placeholder `VIGIE_RELEASE_REPO = OWNER/vigie-releases` with
   `<org>/vigie-releases` and commit (the same value as the `RELEASE_REPO` variable, step 8). The app's feed is
   `https://github.com/<org>/vigie-releases/releases/latest/download/appcast.xml` (`SUFeedURL`). While it reads
   `OWNER/…` the app treats the feed as unconfigured and never checks, and `release.yml` stops.
1. github.com › New repository › Owner `<org>`, name `vigie-releases` (any name works: it is the `RELEASE_REPO`
   variable, step 8), **Public**, *Add a README* ticked (a release needs one commit for its tag to point at; the
   README says "Releases of Vigie. The source code is not public."). No code ever goes in it. Settings › General:
   untick Wikis, Issues (unless you want public bug reports there), Projects, Discussions.
2. Token, scoped to that repository only: github.com › Settings › Developer settings › Fine-grained personal access
   tokens › Generate new token: Name `Vigie release publish`, Resource owner `<org>` (the organization may need to
   allow fine-grained tokens: Organization › Settings › Personal access tokens), Expiration the longest the
   organization allows (calendar a renewal), Repository access **Only select repositories** › `<org>/vigie-releases`,
   Permissions › Repository › **Contents: Read and write** (Metadata: read is added automatically), nothing else ›
   Generate. Its value is `RELEASE_REPO_TOKEN` (step 8).
   A GitHub App installed only on `vigie-releases` would avoid an expiring token; `release.yml` reads only
   `RELEASE_REPO_TOKEN`, so switching later is a workflow change.

## 8. GitHub `release` environment and secrets (To do)

Private code repository › Settings › Environments › New environment `release` › Configure:

- Deployment protection rules: **Required reviewers** › Romain; tick Prevent self-review only if a second
  maintainer exists.
- Deployment branches and tags › **Selected branches and tags** › Add deployment branch or tag rule › Ref type
  **Tag**, pattern `v*.*.*`; and a second rule › Ref type **Branch**, pattern `master`, for `prices.yml` (Story 6.5:
  it publishes the price table when `prices/` changes on `master`; pull requests never run it).
- Environment variables › Add environment variable: `RELEASE_REPO` = `<org>/vigie-releases` (step 7; not a
  secret, it appears in the release URLs). A repository variable of the same name works too.
- Environment secrets › Add environment secret, one per name (names are what `release.yml`, Story 6.2, reads):

| Secret | Value |
|--------|-------|
| `DEVELOPER_ID_P12` | base64 of the exported Developer ID Application `.p12` (step 2) |
| `DEVELOPER_ID_P12_PASSWORD` | its export password |
| `DEVELOPER_ID_PROFILE` | base64 of `Vigie Developer ID` `.provisionprofile` (step 4) |
| `ASC_KEY_ID` | App Store Connect API Key ID (step 5) |
| `ASC_ISSUER_ID` | Issuer ID (step 5) |
| `ASC_KEY_P8` | contents of `AuthKey_<KEYID>.p8` (step 5) |
| `SPARKLE_PRIVATE_KEY` | exported EdDSA private key, base64 seed from `generate_keys -x` (step 6; Story 6.3) |
| `RELEASE_REPO_TOKEN` | fine-grained token with Contents read/write on `<org>/vigie-releases` only (step 7) |

Only the release (Developer ID) profile is a secret. The `.dev` Development profile is Xcode-managed per Mac and
lists only registered Macs; CI never signs Debug builds, so it is never stored in GitHub (AD-20, amended
2026-11-12 by Story 6.2). The Homebrew tap token (SPEC §12.3 step 8) comes with the tap story.

## Releasing (Story 6.2)

**CI minutes are currently off (2026-11-12): do not push release tags and do not push `prices/` changes expecting
them to publish.** `release.yml` and `prices.yml` are checked with `actionlint` and dry runs only until minutes are
back.

`.github/workflows/release.yml` does the whole release on a GitHub macOS runner; the logic is in
`Scripts/release/*.sh`, each runnable locally with `--dry-run`.

1. On `master`, with CI green: `git tag -a v1.2.0 -m "Vigie 1.2.0" && git push origin v1.2.0`. The tag must be on
   `master` and be `vX.Y.Z`, or `vX.Y.Z-<suffix>` (`v1.2.0-beta.1`) for a pre-release. `CFBundleShortVersionString`
   is `X.Y.Z` (also for a pre-release), `CFBundleVersion` the run number (docs/versioning.md).
2. Job `check` (no secrets) stops with an `::error::` if the tag is not on `master`, is malformed, or does not give
   the project version through `Scripts/version.sh`.
3. Job `release` waits for approval: Actions › the run › **Review deployments** › `release` › Approve. It then
   imports the certificate into a temporary keychain, installs the profile, archives and exports (Developer ID),
   checks the signature, Hardened Runtime and versions of the app, notarizes and staples the app, packages the
   zip and the DMG, signs, notarizes and staples the DMG, signs the zip with the Sparkle key and (stable tags only)
   writes the signed `appcast.xml`, writes checksums and publishes. The keychain, profile and
   API key file are deleted at the end, also when a step fails.
4. Result, on `https://github.com/<RELEASE_REPO>/releases/tag/vX.Y.Z`:
   - `Vigie-X.Y.Z.dmg`: signed, notarized and stapled, the app and an Applications link, for manual download;
   - `Vigie-X.Y.Z.zip`: the stapled app, for Sparkle (its EdDSA signature is in `appcast.xml`);
   - `appcast.xml` (stable tags only): the feed the app reads at `releases/latest/download/appcast.xml`, one item
     per stable release (earlier items copied from the current feed), signed as a whole;
   - `SHA256SUMS.txt`: `shasum -a 256` of both, check with `shasum -a 256 -c SHA256SUMS.txt`.
   Notes: the `## X.Y.Z` section of `CHANGELOG.md` at the tag if there is one, otherwise the tag message. A suffixed
   tag is published as a pre-release and never as "latest", so the stable appcast never offers it.
5. Re-run: a failed job can be re-run from the run page (Re-run failed jobs). For a new run, Actions › release ›
   Run workflow › **Use workflow from › Tags › vX.Y.Z** and the same tag in the `tag` field. Publishing creates a
   draft first and reuses a draft left by an earlier failed run; if the release is already published, delete it
   on `<RELEASE_REPO>` first (and its tag there) to publish again.
6. Rehearsal without secrets: Run workflow with `dry_run` ticked (any ref, an existing tag in `tag`): the `check`
   job runs for real, then every release command is printed instead of run. Locally:
   `Scripts/release/check-tag.sh --tag vX.Y.Z` and the same scripts with `--dry-run`; tests in
   `Scripts/tests/release-*.sh` (run by `Scripts/ci-local.sh` and CI).

Pull requests and forks cannot reach the secrets: `release.yml` runs only on tag pushes and manual dispatch, and
the `release` environment admits only `v*.*.*` tags and waits for a reviewer.

## What Story 6.1 could not verify without the certificate

- A signed Release build (`xcodebuild -configuration Release build` stops at "No profile for team 'BWMPMACCYZ'
  matching 'Vigie Developer ID' found", as expected): the embedded profile, the final entitlements
  (`com.apple.application-identifier`, `com.apple.developer.team-identifier`, `keychain-access-groups`, no
  `get-task-allow`), the Developer ID designated requirement of app and helper, the secure timestamp.
- Notarization (`notarytool submit`), stapling and Gatekeeper (`spctl -a -vv`), which belong to Story 6.2.
- `xcodebuild archive` + `-exportArchive` with a Developer ID export (Story 6.2).

Story 6.2 could not run either without the certificate: the Release archive builds unsigned
(`CODE_SIGNING_ALLOWED=NO`, universal, versions from `Scripts/version.sh`), the DMG builds with `hdiutil` and its
signing stops at "no identity found", and everything else is covered by dry runs and tests only. The first real
tag is the end-to-end test: push a pre-release tag such as `v0.1.0-rc.1` first.

After steps 2–4, check on this Mac:

```sh
xcodebuild -project App/Vigie.xcodeproj -scheme Vigie -configuration Release build -derivedDataPath /tmp/dd-release
APP=/tmp/dd-release/Build/Products/Release/Vigie.app
codesign -dv --verbose=2 "$APP"                        # Authority=Developer ID Application: Baguette Labs (BWMPMACCYZ), flags=0x10000(runtime), Timestamp=…
codesign -d --entitlements - "$APP"                    # apple-events, keychain-access-groups BWMPMACCYZ.fr.baguettelabs.vigie (+ identifiers)
codesign -dv --verbose=2 "$APP/Contents/Helpers/vigie" # same authority, runtime, Timestamp=…
codesign -d --entitlements - "$APP/Contents/Helpers/vigie" # none
codesign --verify --deep --strict --verbose=2 "$APP"
```

## Auto-update (Story 6.3)

- **Feed:** `appcast.xml` of the newest stable release on `<RELEASE_REPO>` (GitHub redirects
  `releases/latest/download/` to it). `Scripts/release/appcast.sh` writes it: `sparkle:version` = build number,
  `sparkle:shortVersionString` = `X.Y.Z`, `sparkle:minimumSystemVersion` = 15.0, the notes of `notes.sh` as
  Markdown, the zip's `sparkle:edSignature` and `length`. Pre-release tags get no item (A63; the beta feed is Story
  19.3). The whole feed is signed too (`SURequireSignedFeed`).
- **Signing:** `Scripts/release/sign-update.sh` runs Sparkle's `sign_update` from the pinned release zip
  (version and SHA-256 in the script, same version as `App/project.yml`), the key on stdin only. Its `sign`,
  `verify --public-key` and `public-key` commands are what Story 6.5 reuses for the price table.
- **Rejected updates:** Sparkle checks the zip's EdDSA signature against `SUPublicEDKey` before extracting
  (`SUVerifyUpdateBeforeExtraction`), the feed's signature, and that the new app's code signature matches the
  installed one (same Developer ID team); Gatekeeper checks notarization when the new version opens. Any failure
  shows Sparkle's error and keeps the installed version. Tested here: a tampered zip and an edited feed fail
  verification (`Scripts/tests/release-sparkle-test.sh`).
- **In the app** (`App/Sources/SparkleUpdater.swift`): `[updates] auto_check` (default on) schedules checks every
  `check_interval` (default 24 h, at least 1 h); off = Sparkle is not started and no update request is made, except
  when the user picks "Check for Updates…" (Settings › Updates or the notch context menu). `auto_install` (default
  off) lets Sparkle download in the background and install when Vigie quits; off = Sparkle asks first. Ticking
  "Automatically download and install updates" in Sparkle's alert writes `auto_install = true` to `config.toml`.
- **Relaunch (AD-21):** "Install and Relaunch" quits Vigie through the normal path: `applicationShouldTerminate`
  stops the modules, the Event Server (socket closed; unlinked only if it is still the inode it bound) and the
  config store, `applicationWillTerminate` releases the instance lock. Sparkle's installer waits for the process to
  exit, replaces the bundle and opens the new version, which takes the lock, binds the socket and replays the spool
  (events the CLI spooled meanwhile) before `host.ready` (`RelaunchHandoverTests`).
- **No installer launcher service:** Vigie is not sandboxed, so `SUEnableInstallerLauncherService` and
  `SUEnableDownloaderService` stay unset and the XPC services inside `Sparkle.framework` are never launched; no
  entitlement is added. Sparkle's `Autoupdate` / `Updater.app` run only while an update installs.

What only a real release can verify: a Developer ID export re-signing Sparkle's nested helpers with Hardened
Runtime and passing notarization; the redirect of `releases/latest/download/appcast.xml`; an actual update from
one published version to the next (download, signature check, install, relaunch, spool replay); the "ask first"
alert. Test it with two stable tags in a row (for example `v0.1.0` then `v0.1.1`) once steps 2 to 8 are done.

## Price table (Story 6.5)

- **Source:** `prices/prices.json` at the repository root (schema 2: `schema`, integer `version`, a `providers` map
  keyed by adapter id, each with `currency`, `unit`, `updated` and `models`; optional `tiers` per model are kept but
  not applied yet). The app bundles a copy in `Packages/Modules/AgentsUsage/Sources/AgentsUsage/Resources/prices.json`;
  a Swift test and `prices.sh` refuse a copy that differs. To change prices: edit `prices/prices.json`, bump
  `version` by one, set the section's `updated`, copy the file over the bundled one, commit on `master`.
- **Location:** `https://github.com/<RELEASE_REPO>/releases/latest/download/prices.json` and `prices.json.sig`,
  next to `appcast.xml`. The app derives it from `SUFeedURL`; while `VIGIE_RELEASE_REPO` is the `OWNER/…`
  placeholder or `VIGIE_SPARKLE_PUBLIC_KEY` is empty, the app logs "price table updates off in this build" once
  and never requests it.
- **Signing:** `Scripts/release/prices.sh sign --dist DIR` checks the table, copies it to `DIR/prices.json` and
  writes `DIR/prices.json.sig`: one line, the base64 Ed25519 signature of the file's bytes made by Sparkle's
  `sign_update` with `SPARKLE_PRIVATE_KEY` (the same key as updates). The app verifies it with `SUPublicEDKey`
  (CryptoKit), refuses a lower version or a bad signature (one setup problem), and keeps an accepted table in
  `modules/agents.usage/` of its Application Support folder.
- **Publishing:** every release tag publishes both files (`release.yml`, step "Sparkle signature, appcast and price
  table"; `publish.sh` uploads all of `$DIST`). Between releases, a push to `master` that changes `prices/` runs
  `prices.yml`: it signs the table and replaces both files on the latest release of `RELEASE_REPO`
  (`prices.sh publish-latest`, `RELEASE_REPO_TOKEN`). A pre-release is never "latest", so it never serves the
  table. Test: `Scripts/tests/release-prices-test.sh` (dry runs, refusals, sign and verify round trip).
- **In the app:** `[updates] prices` (default on, Settings › Updates) and `[updates] check_interval`; Settings ›
  Usage has `Check now`. Off or offline: no request, the newest table already on disk is used.

What only a real release can verify: the `releases/latest/download/prices.json` redirect, `prices.yml` running
with the `release` environment on `master`, and an installed app picking up a newer table.

