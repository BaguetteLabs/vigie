# Versioning

Story 6.4 (FR107). Vigie takes no outside contributions, so there is no CONTRIBUTING file (PRD section 9 Q1); this note is the rule.

## App version and build number

- `CFBundleShortVersionString` (`MARKETING_VERSION`) is `X.Y.Z`, taken from the release git tag `vX.Y.Z`. Anything that is not a plain triple (`v1.2`, `v1.2.3-beta`) is rejected.
- `CFBundleVersion` (`CURRENT_PROJECT_VERSION`) is the CI run number (`$GITHUB_RUN_NUMBER`). It only goes up, and Sparkle compares `CFBundleVersion`, so every published build is newer than the last whatever its tag.
- Dev and local builds use `0.0.0` and `git rev-list --count HEAD` as the build number.

`Scripts/version.sh` is the single source:

```
Scripts/version.sh --tag v1.4.0 --build "$GITHUB_RUN_NUMBER" --xcconfig App/Config/Version.xcconfig
```

It writes `App/Config/Version.xcconfig` (generated, gitignored), which `App/project.yml` attaches to both configurations, and `App/Info.plist` reads `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. Run it before `xcodegen generate`; `Scripts/ci-local.sh` and the CI `version` step do. The release workflow and the Sparkle appcast step call it with the tag and run number and read the same values.

## Protocol and schema numbers

- The wire protocol version `v` (`WireProtocol.version`, carried in every `Envelope`) covers the socket and spool format, including adapter events.
- The `schema` numbers cover script modules and module state files (`{ "schema": n, "value": ... }`), and the config file.

Bump these on an incompatible change. An incompatible change ships only in a major app version (`X` increases). Compatible additions keep the numbers.
