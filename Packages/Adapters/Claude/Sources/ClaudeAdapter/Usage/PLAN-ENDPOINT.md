# Claude plan-usage endpoint (Story 7.3)

Unofficial, undocumented, and the only remote call the Claude adapter makes. Every assumption below is coded in
`ClaudePlanUsageClient.swift` (request, status mapping, decode) and `ClaudeCodeCredential.swift` (stored login).
When it breaks, patch those two files and the fixtures in `Tests/PlanUsageFixtures/`; nothing outside this
package knows the shape.

## Request

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access token>
anthropic-beta: oauth-2025-04-20
Accept: application/json
```

Sent through `AdapterContext.http` only (AD-16). Timeout 15 s. Refreshed every 5 minutes and when the expanded
view opens, only while `[modules."agents.sessions".adapter.claude] usage_providers` contains `"plan"`.

## Response (200)

```json
{
  "five_hour":        { "utilization": 37.0, "resets_at": "2026-11-08T15:00:00.123456+00:00" },
  "seven_day":        { "utilization": 12.0, "resets_at": "2026-11-12T08:00:00+00:00" },
  "seven_day_opus":   null,
  "seven_day_sonnet": { "utilization": 4.0, "resets_at": null },
  "extra_usage":      { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
}
```

Treated as untrusted:

- An entry is a window only if it is an object with a numeric `utilization` (0–100, percent used) **and** a
  `resets_at` key. `resets_at` is ISO-8601 (fractional seconds of any length) or `null` (window not started:
  kept, no reset time). An unparseable `resets_at` skips the window.
- `five_hour` → `5h`, `seven_day` → `weekly`; any other window is kept under its key (`seven_day_opus`, …).
- `null` entries and objects without both fields (`extra_usage`) are ignored.
- A 200 body that is not a JSON object, or holds no window → `PlanUsageError.formatChanged`.

Windows become `UsageWindow(name:, used: utilization, limit: nil, resetsAt:)` (limit nil = `used` is a percent).

## Errors

| Case | `PlanUsageError` |
|---|---|
| transport failure | `.unavailable(status: nil)` |
| 401, 403 | `.unauthorized` |
| other non-200 | `.unavailable(status:)` |
| bad JSON / no window | `.formatChanged` |

`agents.usage` keeps the last good windows (`STALE · HH:MM`), raises one `setup.problem` "Claude plan usage
unavailable" (dedupe `plan:claude`), and resolves it on the next success.

## Credential

`plan_auth` (local.toml):

- `token`: the user pastes a token; stored by SecretStore as `adapter.claude/plan_token` (data-protection
  keychain, never synced). Missing → `.credentialMissing`.
- `claude_code`: Claude Code's stored login, read with `SecretStore.readExternal(ClaudeCodeCredential.descriptor)`
  only after the user clicked Allow (consent in `local.toml` `[consents."claude.claude_code_login"] granted_at`).
  - Login keychain, generic password, service `Claude Code-credentials`, account = macOS user name (no account
    hint: the first item of the service is read).
  - Value: JSON `{"claudeAiOauth": {"accessToken", "refreshToken", "expiresAt" (ms since 1970), "scopes",
    "subscriptionType"}}`. Only `accessToken` and `expiresAt` are read.
  - `expiresAt` at or before now → `.credentialExpired`. Vigie **never** uses the refresh token, never writes
    or renews the item: the user signs in to Claude Code again (Claude Code renews it itself when it runs).
  - No consent → `.consentRequired`; item missing or unreadable (or the Keychain prompt denied) →
    `.credentialMissing`.

The pasted token is read from SecretStore at each fetch. Claude Code's login is read once per launch: the
provider keeps its `accessToken` and `expiresAt` (not the refresh token) in process memory
(`ExternalCredentialCache`, one per `ClaudeAdapter`) and reads the Keychain again only when the held token has
expired, or on the fetch after the endpoint answered 401/403. So macOS's Keychain prompt appears at most once per
launch (SPEC §7.2, AD-9 amended 2026-11-12). Nothing is logged, written to disk or renewed; revoking consent
drops the held token at the next fetch.

## Verified

- 2026-11-08: the Keychain item's attributes on the dev Mac (service and account only; the value was not read).
- The response shape is from community reports of Claude Code's `/usage`; not yet seen live by Vigie. First live
  check: Romain, with `plan` enabled in Settings › Usage.
