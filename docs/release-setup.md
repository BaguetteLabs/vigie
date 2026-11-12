# Release setup: what the maintainer does by hand

Stories 6.1 and 6.2 (AD-17, AD-20, SPEC §12, A49, A86). The build settings for signing are committed in
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
   `keychain-access-groups` = `BWMPMACCYZ.fr.baguettelabs.vigie.dev` and
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
  `BWMPMACCYZ.*` and `com.apple.application-identifier` `BWMPMACCYZ.fr.baguettelabs.vigie`.
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

1. Download the Sparkle 2 release archive from github.com/sparkle-project/Sparkle/releases and unpack it.
2. `./bin/generate_keys`: creates the key pair in the login keychain and prints the public key
   (`SUPublicEDKey`, goes into Info.plist in Story 6.3; it is not a secret).
3. `./bin/generate_keys -x sparkle_private_key.txt`: exports the private key; its contents are
   `SPARKLE_PRIVATE_KEY`. Keep a copy in your password manager, then delete the file. Losing it means existing
   installs can no longer verify updates.

## 7. GitHub organization, public releases repository and its token (To do, A49, A86)

Choose the organization that hosts the private code repository, the public releases-only repository
(`<org>/vigie-releases`, SPEC §12.1) and the Homebrew tap (`<org>/homebrew-vigie`). The appcast URL and the cask
are built from it (Stories 6.2, 6.3).

**Public release host (decided 2026-11-06, SPEC §12.1, AD-20):** a separate **public** GitHub repository that only
holds releases. GitHub Releases of the private code repository are not an option: visitors without access to the
code cannot see them, so Sparkle and Homebrew could not download anything. `release.yml` publishes there with a
token, and the private repository's own `GITHUB_TOKEN` stays read-only.

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
  **Tag**, pattern `v*.*.*`.
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
| `SPARKLE_PRIVATE_KEY` | exported EdDSA private key (step 6; read by Story 6.3) |
| `RELEASE_REPO_TOKEN` | fine-grained token with Contents read/write on `<org>/vigie-releases` only (step 7) |

Only the release (Developer ID) profile is a secret. The `.dev` Development profile is Xcode-managed per Mac and
lists only registered Macs; CI never signs Debug builds, so it is never stored in GitHub (AD-20, amended
2026-11-12 by Story 6.2). The Homebrew tap token (SPEC §12.3 step 8) comes with the tap story.

## Releasing (Story 6.2)

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
   zip and the DMG, signs, notarizes and staples the DMG, writes checksums and publishes. The keychain, profile and
   API key file are deleted at the end, also when a step fails.
4. Result, on `https://github.com/<RELEASE_REPO>/releases/tag/vX.Y.Z`:
   - `Vigie-X.Y.Z.dmg`: signed, notarized and stapled, the app and an Applications link, for manual download;
   - `Vigie-X.Y.Z.zip`: the stapled app, for Sparkle (signed with EdDSA and listed in `appcast.xml` by Story 6.3);
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
