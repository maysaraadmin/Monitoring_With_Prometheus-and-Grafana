# UI Guidelines

**This project builds no UI of its own.** The only interface is Grafana, which brings its own
design system, and one imported community dashboard. So the usual tokens-and-components
document would be fiction. What follows is the real, narrow set of conventions that apply when
changing anything under `grafana/provisioning/`.

## Tokens
Grafana's own theme. Do not hardcode colours in dashboard JSON — use the field-config
thresholds and the palette names (`green`, `yellow`, `red`, `text`) so both themes work. The
default theme is dark; light must stay readable because it is one toggle away.

## Layout rules
- Keep the existing row structure of "Node Exporter Full": collapsed rows by section (CPU,
  Memory, Disk, Network), with the summary row expanded at the top.
- Panels are 24 grid units wide. Use 12 for a pair, 8 for a triple, 6 for a quad.
- Do not exceed 24 in a row — Grafana reflows and the layout jumps on narrow screens.
- Right-to-left is not supported by Grafana dashboards and is out of scope.

## Components
Only four panel types are in use, and new panels should stay within them:
- **Time series** — anything with a rate or a trend over time. Always set a unit.
- **Stat** — a single current value. Set thresholds so the colour means something.
- **Gauge** — a value against a known maximum (disk percentage used, memory percentage used). Never for an unbounded value.
- **Table** — inventory, such as filesystems or interfaces.

## Required states for every panel
A panel is not finished until all four read correctly:
- **Data** — the query returns series and the unit is set, so the axis is not a bare number.
- **No data** — the panel says "No data", not `0`. A gauge stuck at zero looks like a real reading of zero and hides a broken scrape. Set "No value" explicitly rather than leaving the default.
- **Error** — a datasource or query error shows the panel's error corner, not an empty graph.
- **Stale** — if the target stops being scraped, the line must end rather than flatten. Leave the "Connect null values" setting off.

## Accessibility
- Never rely on colour alone: a red stat panel must also show the number and its unit.
- Every panel has a title that says what it measures, with the unit in the field config.
- Thresholds use Grafana's defaults (green/yellow/red), which do not pass contrast checks for
  colour-blind viewers on their own. The number next to the colour is what carries the meaning.
- Dashboards must be readable at 1280px without horizontal scrolling.

## Rules learned from QA
- 2026-11-16 — A dashboard can be correctly provisioned and still appear missing, because
  Grafana opens on its generic welcome page rather than on any dashboard. When adding a
  dashboard, also decide whether it should be the home dashboard
  (`GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`), and record the direct `/d/<uid>/<slug>` URL in
  `docs/Handoff.md`. "No dashboard shows" is usually navigation, not provisioning — check
  `GET /api/search?type=dash-db` before touching any config.
- 2026-11-16 — An imported community dashboard references its datasource through a
  `${DS_PROMETHEUS}` template variable. Check that variable resolves to the provisioned
  datasource before concluding the data is missing; a datasource UID mismatch looks exactly
  like an empty database.

## References
- "Node Exporter Full", Grafana dashboard 1860, uid `rYdddlPWk` — the layout all panels follow.
- "Website Monitoring", uid `website-monitoring`, written for this project
  (`grafana/provisioning/dashboards/websites.json`). One templated dashboard rather than one file
  per site: a `site` variable drives every panel, so each website has its own bookmarkable URL
  (`/d/website-monitoring/website-monitoring?var-site=https://yoursite.com`) and a new site
  appears in the dropdown as soon as it is added to `prometheus/targets/sites.yml`. Forms were
  chosen by job: stat tiles for single headline values, a state timeline for up/down over time
  (so a period with *no data* reads as blank rather than as a line at zero), one unstacked
  series for total latency, and a stacked series for the phase breakdown. Status colours are
  reserved and always paired with the words UP/DOWN, never colour alone.
- The blackbox dashboard shown in the README's screenshots is still not the one in this repo;
  `websites.json` above was written from scratch for this project rather than imported, so it
  will not look like that screenshot.

## Rule: the default view holds only what is read every day
Added 2026-11-16 after the site dashboards reached 19 visible panels and the user asked for them
to be simplified. The panels were all individually justified; the problem was that everything
earned a place in the *default* view.

- A dashboard's first screen answers the everyday questions only. For a website that is: is it
  up, is it reliably up, how many probes failed, when does the certificate expire, what has
  availability looked like, how fast is it, and where does the time go. Seven panels.
- Anything needed only when something is wrong goes in a **collapsed row**. Grafana renders
  nothing inside a collapsed row until it is opened, so it costs no load time and no attention,
  and nothing has to be deleted to get a clean view.
- Name the row for when to open it, not for what is in it: "Diagnostics (open when something is
  wrong)" tells the reader whether they need it. "Advanced metrics" does not.
- Prefer collapsing over deleting. The twelve diagnostic panels were what actually identified a
  33% probe failure rate and told connection drops apart from mid-transfer timeouts. Deleting
  them to tidy the view would have thrown away the only part that explained a real problem.
