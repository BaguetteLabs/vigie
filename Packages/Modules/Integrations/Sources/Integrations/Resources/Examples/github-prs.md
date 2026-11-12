---
id: github.prs
name: GitHub PRs
icon: arrow.triangle.pull
interval: 5m
runtime: sh
widget: number
surfaces: [home, side]
priority: 5
settings:
  - { key: repo,  type: string, label: "Repository (owner/name)" }
  - { key: token, type: secret, label: "GitHub token", help: "Optional for public repositories. Stored in this Mac's Keychain." }
---

# GitHub PRs

Shows how many pull requests are open on one repository, and opens the pull request list when you click the widget.

It asks the GitHub search API (`GET /search/issues`) with `curl`, so it needs nothing installed beyond macOS.

**Settings** (Settings › Scripts)

- `repo`: the repository as `owner/name`, for example `apple/swift`. Required.
- `token`: a GitHub personal access token. Optional for public repositories (it raises the rate limit); needed for private ones. It reaches the script as `VIGIE_SETTING_TOKEN` and is never written to a file.

**Trust.** Like every script, this one runs unsandboxed, as you, with your files and network. Read the code below before you confirm it, and only install scripts you trust.

```sh
repo=${VIGIE_SETTING_REPO:-}
case $repo in
  */* ) ;;
  * ) echo "github.prs: set 'repo' (owner/name) in Settings > Scripts" >&2; exit 2 ;;
esac
case $repo in
  *[!A-Za-z0-9._/-]* ) echo "github.prs: invalid repo '$repo'" >&2; exit 2 ;;
esac

if [ -n "${VIGIE_SETTING_TOKEN:-}" ]; then
  body=$(curl -fsS --max-time 20 -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $VIGIE_SETTING_TOKEN" \
    "https://api.github.com/search/issues?q=repo:$repo+type:pr+state:open&per_page=1") || exit 1
else
  body=$(curl -fsS --max-time 20 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/search/issues?q=repo:$repo+type:pr+state:open&per_page=1") || exit 1
fi

count=$(printf '%s' "$body" | grep -o '"total_count": *[0-9]*' | grep -o '[0-9]*$' | head -n 1)
if [ -z "$count" ]; then
  echo "github.prs: no total_count in the GitHub response" >&2
  exit 1
fi

state=ambient
[ "$count" -gt 0 ] && state=active
printf '{"state":"%s","widget":{"type":"number","value":%s,"label":"OPEN PRS"},"action":{"open":"https://github.com/%s/pulls"}}\n' \
  "$state" "$count" "$repo"
```
