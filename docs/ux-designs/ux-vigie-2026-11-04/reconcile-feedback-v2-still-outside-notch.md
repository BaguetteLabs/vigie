# Reconcile: imports/feedback-v2-still-outside-notch.png

**What it shows (qualities):** v2 closed state, both variants. A: island widened by two "wings", 1px hairlines leaving the island and fading within 100px, a soft violet glow/gradient below the menu bar, iridescent rim highlight sliding along the hairlines. C: silver corner brackets outside the island, "VIGIE · ONLINE" and "14:48:06 · 3 LINKS" readouts below it, a 720px tick scale. In-island content: quota dial "62% CLAUDE · 5H" left; "3 / 1 BLOCKED" + urgency-sorted glyphs right (blocked diamond ripples, working arc turns, idle ring still). The island also sits between real menu-bar items (Window/Help, battery, clock).

**Kept**
- Strict containment: "(override) Containment rule tightened ... in closed state EVERYTHING is drawn inside the black island/notch shape ... Peek/expanded: only the panel itself".
- v3 event: "strict containment (island clips all ornaments; panels only neutral drop shadow)"; island 540x34.
- Left quota / right sessions layout: "(decision) Closed notch left side: circular progress ring for quota"; "(decision) Closed notch right side: per-session animated status glyphs ... 'perfect visualisation system'".
- Urgency ordering: "(decision) Session slot priority: blocked sessions supersede everything".

**Intentionally dropped**
- Outside hairlines, glow, brackets, readouts, 720 scale: the override above; v3 event "C lost closed-state online/clock readouts".

**Silently dropped / at risk**
- Information carried by the removed readouts ("ONLINE" health, "3 LINKS" connected-agents count, clock) - the ornaments were dropped, but no decision moves this info elsewhere (only the "no agent connected" empty state covers part of it).
- A's "light catching glass" rim highlight motion - no decision whether it survives inside the island.
- Menu-bar collision: a 540px island overlaps app menus / status items on smaller or busy menu bars; no decision on width adapting to free space.
- Containment on non-notch displays (virtual notch / "menu_bar style" plain display) - rule worded for the notch; not stated whether it applies identically there.
