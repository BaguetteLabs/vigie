# Reconcile: imports/ref-claude-usage-tracker-pace-bar.png

**What it shows (qualities):** tiny, glanceable horizontal bar labelled "Session"; fill = quota consumed (green when healthy); a vertical marker = time elapsed in the 5h window; one comparison (fill vs marker) tells whether you are ahead of pace; color shifts to orange when consumption outpaces time. Minimal, no numbers needed.

**Kept**
- Import event: "horizontal session progress bar with a vertical marker showing elapsed time ... bar turns orange when consumption outpaces time ... User likes this pace indicator".
- "(decision) Pace indicator (elapsed-time marker, orange when ahead of pace) on both closed ring and expanded bar; optional per setting".
- Glanceable quota: "(decision) Closed notch left side: circular progress ring for quota"; "(decision) Left side: one ring per provider; nested rings when two quotas".

**Intentionally dropped**
- Bar shape in the closed notch: replaced by the ring (pace marker transposed onto the ring per the decision above). Bar survives in expanded view.

**Silently dropped / at risk**
- Not rendered yet: theme-family-4-looks.html and compare-a-vs-c-v3.html show no elapsed-time marker on the closed ring and no "ahead of pace" color state (only a C "now" marker in expanded). Unvalidated visually, especially on small nested rings.
- Color collision: "orange when ahead" clashes with the working status amber (C #F0A43C) and the metal palette; "(decision) every status color individually configurable" does not list a pace/warning color.
- Green = healthy fill semantics not carried over; no decision on the normal-state fill color.
- Absent/variable windows: "(event) ... Claude recently removed the 5h window for ... Ultra plan" - no decision on pace behavior for weekly-only or other window lengths.
- Relation to "(decision) Quota warning: threshold configurable" - pace-ahead vs threshold warning are two signals; not stated whether pace-ahead can trigger the alert/sound.
