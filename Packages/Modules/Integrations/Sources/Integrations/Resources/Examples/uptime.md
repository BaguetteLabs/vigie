---
id: system.uptime
name: Mac uptime
icon: clock
interval: 1m
runtime: sh
widget: text
surfaces: [home, side]
priority: 9
---

# Mac uptime

Shows how long this Mac has been running since its last restart, for example `3d 4h` or `12m`. It needs no network, no token and no settings, which makes it the smallest useful example to copy from.

It reads the boot time with `sysctl -n kern.boottime` and prints one `text` widget.

**Trust.** Like every script, this one runs unsandboxed, as you, with your files and network. Read the code below before you confirm it, and only install scripts you trust.

```sh
boot=$(sysctl -n kern.boottime | sed -n 's/^{ sec = \([0-9][0-9]*\),.*/\1/p')
if [ -z "$boot" ]; then
  echo "system.uptime: cannot read kern.boottime" >&2
  exit 1
fi

secs=$(( $(date +%s) - boot ))
days=$(( secs / 86400 ))
hours=$(( secs % 86400 / 3600 ))
minutes=$(( secs % 3600 / 60 ))

if [ "$days" -gt 0 ]; then text="${days}d ${hours}h"
elif [ "$hours" -gt 0 ]; then text="${hours}h ${minutes}m"
else text="${minutes}m"
fi

printf '{"widget":{"type":"text","value":"%s","label":"UPTIME"}}\n' "$text"
```
