---
id: site.status
name: Site status
icon: globe
interval: 1m
runtime: sh
widget: status
surfaces: [home, side, page]
priority: 5
settings:
  - { key: url, type: string, label: "URL to check", default: "https://example.com" }
---

# Site status

Checks that a web page answers over HTTPS, and shows `OK` or `DOWN` with the HTTP status and the response time, for example `200 · 142 ms`. Clicking the widget opens the page.

It makes one `curl` request a minute (redirects followed, 10 second limit). A 2xx answer is `OK`, or `WARN` when it took more than 2 seconds; anything else, including no answer at all, is `DOWN` and raises the module's alert.

**Settings** (Settings › Scripts)

- `url`: the address to check, starting with `https://` (or `http://`).

**Trust.** Like every script, this one runs unsandboxed, as you, with your files and network. Read the code below before you confirm it, and only install scripts you trust.

```sh
url=${VIGIE_SETTING_URL:-}
case $url in
  http://* | https://* ) ;;
  * ) echo "site.status: 'url' must start with https:// (Settings > Scripts)" >&2; exit 2 ;;
esac
case $url in
  *[\"\\]* | *' '* ) echo "site.status: invalid url" >&2; exit 2 ;;
esac

# curl prints "000" as the status when it cannot connect; the time is in seconds.
result=$(curl -sS -L -o /dev/null --max-time 10 -w '%{http_code} %{time_total}' "$url" 2>/dev/null)
code=${result% *}
ms=$(awk -v t="${result#* }" 'BEGIN { printf "%d", t * 1000 + 0.5 }')

host=${url#*://}
host=${host%%/*}

case $code in
  2?? )
    level=ok; value=OK; state=ambient
    [ "$ms" -gt 2000 ] && level=warn
    ;;
  * )
    level=error; value=DOWN; state=alert
    ;;
esac
if [ "$code" = "000" ]; then detail="no answer"; else detail="$code · $ms ms"; fi

printf '{"state":"%s","widget":{"type":"status","level":"%s","value":"%s","label":"%s","detail":"%s"},"action":{"open":"%s"}}\n' \
  "$state" "$level" "$value" "$host" "$detail" "$url"
```
