# Script signing

How Vigie proves that a script installed from a `vigie://install` link comes from the Script repository (SPEC §9.4,
AD-18, Stories 12.8 and 12.9). A signature means "reviewed and merged by the maintainer", not "safe": the Script
Confirmation always shows the whole file, and nothing is installed without the user's Confirm.

## Algorithm and formats

- **Algorithm:** Ed25519 (RFC 8032), verified in the app with CryptoKit (`Curve25519.Signing`).
- **What is signed:** the exact bytes of the script file (`<script>.md`) as served. No normalisation: a changed byte,
  line ending or BOM invalidates the signature.
- **Signature file:** a detached signature published next to the file as `<script>.md.sig`. The repository's CI
  writes the raw 64-byte signature **base64-encoded** (88 characters, standard alphabet, padding, optional trailing
  newline). Vigie also accepts the raw 64 bytes. Anything else counts as an invalid signature.
- **Where Vigie looks:** the link's `sig` parameter if present, else `<file URL>.sig` (the path gains `.sig`, query
  kept). HTTPS only; a 404 or any other failure means the file is unsigned.
- **Public keys:** raw 32-byte Ed25519 public keys, base64 (44 characters).

## Trusted keys

The keys live in the app binary: `TrustedScriptKeys.base64` in
`Packages/Modules/Integrations/Sources/Integrations/Install/ScriptSignature.swift`. A signature verifies when any key
of the list verifies it. The list is **empty** until the Script repository exists (`TODO(A84)`; the repository waits
for the GitHub organisation name, A49), so today every link install shows the stronger warning.

What the Script Confirmation shows:

| Case | Line | Author |
|---|---|---|
| A trusted key verifies the signature, and the file's `source` (if any) has the download's host | `Verified: Vigie Script repository` | `Author: <author>` |
| No signature | `Not verified: this file is not signed.` | `Author: <author> (claimed by the file)` |
| A signature no trusted key verifies (tampered bytes, unknown or retired key, garbage) | `Not verified: its signature does not match any key this Vigie trusts.` | claimed |
| A valid signature, but the front matter `source` names another host than the download URL | `Not verified: the file says it comes from another site.` | claimed |

So the repository's CI must publish `source` values on the same host the install links download from (for GitHub,
the raw file host, `raw.githubusercontent.com`), or leave `source` out.

## Updates

An update (Story 12.10) is verified the same way, on the new bytes: its signature is fetched from the recorded `sig`
URL, else `<source URL>.sig`, and checked again when the update review opens. A version that verified before does
not carry its state over: an unsigned or tampered update shows the stronger warning.

## Producing a signature (repository CI, Story 12.8)

The private key exists only in the repository's protected signing environment; pull-request workflows never see it.
Equivalent of what the signing job does for each changed script, with OpenSSL 3:

```sh
openssl pkey -in signing-key.pem -pubout -outform DER | tail -c 32 | base64          # the public key to embed
openssl pkeyutl -sign -rawin -inkey signing-key.pem -in ci-status.md | base64 > ci-status.md.sig
```

## Key rotation

A key is never replaced in one step, because installed apps only trust the keys compiled into them:

1. Generate the new key pair in the protected environment. Keep signing with the old key.
2. Add the new public key to `TrustedScriptKeys.base64` (next to the old one) and ship that app release.
3. Wait until the release with both keys is the one users run (Sparkle updates; at least one release cycle).
4. Switch the CI to the new key and re-sign every published script with it.
5. In a later app release, remove the old public key. Scripts still signed with it now show the stronger warning.

A compromised key skips step 3: remove it from the list in an app update right away, re-sign with a new key, and
accept that users on older builds see the stronger warning on re-signed scripts until they update.
