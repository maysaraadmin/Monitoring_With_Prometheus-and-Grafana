# Handoff

## Sprint 1 Handoff: secure the stack (2026-11-16)
**Status:** ⚠️ Done with gaps
**Commit / PR:** on branch `sprint-1-secure-the-stack`, recorded by the follow-up commit. Not
pushed and not merged — awaiting the user's go-ahead.

### Delivered
- **F1.1 Stop publishing the ports that nothing needs** — ACs passing: 3/4
  - `node-exporter` and `blackbox` have no `ports:` block at all now. Prometheus reaches them as `node-exporter:9100` and `blackbox:9115` on the `monitoring` network, which is how it always worked; the host ports were never needed by anything.
  - `prometheus`, `alertmanager` and `grafana` are bound to `127.0.0.1`.
  - Each binding carries a comment saying *why* it is loopback-only, so a later edit does not silently undo it. The blackbox comment says outright that it is the most important line in the file.
  - AC1.1.2 is **unverified** — it needs a second device on the LAN. See below.
- **F1.2 Drop the Prometheus lifecycle API** — ACs passing: 1/2, one partial
  - `--web.enable-lifecycle` removed; `POST /-/reload` now returns 403. Recorded as D-013.
- **F1.3 Real Grafana credentials from an untracked file** — ACs passing: 4/4
  - `.env.local`, untracked, holds a generated 24-character password, wired in with `env_file:`, plus `GF_USERS_ALLOW_SIGN_UP=false`. `.env.local.example` is committed with placeholders only.
- **F1.4 Get the placeholder credential files out of the repo** — ACs passing: 2/3
  - `.gitignore` added for `.env`, `.env.local` and `secrets/`. `.env` and `config` untracked with `git rm --cached` and deleted from disk — nothing referenced either of them. The `./alertmanager:/config` mount in the compose file is a directory and unrelated.
  - `alertmanager.yml` now uses `auth_password_file: /run/secrets/smtp_password`, mounted from the untracked `./secrets`, so Sprint 2 has nowhere convenient to commit a real password.
  - AC1.4.3 **failed**. See below.

### Not delivered / deferred
- **AC1.4.3 failed, and is not achievable as specified.** The plan assumed Alertmanager would refuse to start with the secret file missing. It does not: it starts normally and `amtool check-config` reports SUCCESS, because `auth_password_file` is read at notify time, not at config load. A missing or placeholder secret is therefore completely silent — the stack looks healthy while being unable to send a single alert. Logged as **I-011**. The fix is not in Alertmanager; it is the startup placeholder check already planned as F5.3 / S5.2, and this finding is the argument for it.
- **AC1.1.2 not run.** Proving the ports are closed *from outside* needs a second device on the network, which was not available. T1.S1 was run as the strongest available substitute: the host's own `netstat` shows exactly three LISTENING sockets, all on `127.0.0.1` (3001, 9090, 9093), with 9100 and 9115 absent entirely. That is good evidence but not the same check — it confirms what this host believes, not what a peer sees. **Run T1.2 before relying on the claim.**
- **AC1.2.2 partial.** Restart-based reload was exercised and `promtool check config` passes afterwards, but no scrape-interval change was actually made, so the full round trip is unproven.

### Tests
Config validators 4/4 · Integration 9/10 with 1 partial · Security 3/3 · Manual 0/1 not run
**Sprint 1: 13 scenario rows — 11 passing, 1 partial, 1 failed, 1 not run.** Counted 2026-11-16.

All four validators pass after the change: `promtool check config` (valid, 1 rule file),
`promtool check rules` (4 rules), `amtool check-config` (SUCCESS), `docker compose config`
(exit 0, with the known obsolete-`version:` warning, G-010).

### Security
- **Five Sprint 0 threats closed:** S0.1 (Prometheus unauthenticated plus lifecycle API), S0.2 (Grafana default credentials), S0.4 (blackbox SSRF relay), S0.5 (Alertmanager silences), S0.6 (node-exporter disclosure).
- **S0.3 is only partly closed.** The placeholders are untracked and Alertmanager reads a file now, but **git history still contains them**. Harmless, since they were never real values, and not worth rewriting history for. Sprint 2 still has to put a real password somewhere, and that is when the control is tested for real.
- **S0.7 untouched**, deliberately — it belongs to Sprint 2.
- All three Sprint 1 security tests passed, and two earned their place rather than rubber-stamping the work:
  - **T1.S2** — `admin`/`admin` returned **200** after `GF_SECURITY_ADMIN_PASSWORD` was set, because Grafana had already initialised its database and ignores the variable from then on. S1.2 predicted precisely this. The password had to be changed through the API. Had the test only asked "does the new password work", it would have passed while the old one still worked.
  - **T1.S3** — run in the required order, and it **failed before** `git rm --cached`, confirming that `.gitignore` alone does not untrack an already-tracked file.

### Deviations from plan
- AC1.2.1 expected 405 or 404 from the disabled reload endpoint; Prometheus returns **403**. The control works; the plan's expected value was wrong and has been corrected in place in `docs/Implementation.md` rather than left to mislead the next reader.
- AC1.4.3's premise was wrong about how Alertmanager behaves. The criterion is left in the plan marked ❌ with the reason, not quietly deleted.
- The `.env` file was **deleted**, not merely untracked. It held only commented-out placeholders referring to `${ADMIN_USER}` and `${ADMIN_PASSWORD}`, and the compose block that used them is gone, so it was a decoy. `secrets/` was added as a new gitignored directory, which the plan implied but did not name.
- Recreating the stack hit a transient `bind: Only one usage of each socket address` on 9093 — the old container's socket in `TIME_WAIT`. A second `docker compose up -d` succeeded. Worth a line in the Sprint 5 runbook.

### Known issues & tech debt
- **I-011** (new, Medium): a missing or placeholder SMTP secret is silent. Fix planned as F5.3.
- The Grafana password now lives in two places that have to agree: `.env.local`, which is only read on a fresh database, and Grafana's own database, which is what actually authenticates. Anyone changing it must change it through the API *and* update `.env.local`, or deleting `grafana_data` later silently reverts to the `.env.local` value.
- `grafana` still runs `user: '0'`. Out of scope this sprint, still worth testing whether it can be dropped now that a named volume is in use.
- All five images are still `latest` (G-008, S0.9) — Sprint 4.

### How to run / demo
```
docker compose up -d
```
- Grafana **http://localhost:3001** — user `admin`, password in `.env.local` (untracked: `grep GF_SECURITY_ADMIN_PASSWORD .env.local`). `admin`/`admin` is now rejected.
- Prometheus **http://localhost:9090** and Alertmanager **http://localhost:9093** — both loopback-only.
- node-exporter and blackbox have **no host port**. To reach them: `docker exec prometheus wget -qO- http://node-exporter:9100/metrics`.
- Validators: see "How to run" in `docs/Implementation.md`. Git Bash on Windows needs `MSYS_NO_PATHCONV=1`.
- From a clean checkout: `cp .env.local.example .env.local` and set a password, then `mkdir -p secrets` and write the Gmail app password into `secrets/smtp_password`.

### Next sprint should know
- **Sprint 2 is where S0.3 actually gets tested.** Everything Sprint 1 did was preparation; the only remaining way to leak a credential is to type it into a tracked file by hand. Put the Gmail app password in `secrets/smtp_password` and nowhere else, and check `git status` before committing.
- **I-011 changes Sprint 2's shape.** Do not treat "Alertmanager started and the config validates" as evidence that notifications can be sent — Sprint 1 proved those two are independent. AC2.4.1 and AC2.5.1 are the criteria that mean anything.
- `secrets/smtp_password` currently holds the literal string `replace-with-your-gmail-app-password`. It is a placeholder, and nothing will warn about it. That is I-011.
- The loopback bindings already carry explanatory comments in `docker-compose.yml`. F5.2 was planned to add those; **that half is done** — F5.2's remaining work is the automated check, not the comments.
- Nothing in Sprint 1 touched the alert rules, so all five permanently-firing alerts are still firing, including the always-true memory rule (G-002).

### Metrics
ACs passed first run: 10/13 · corrected or re-run to passing: 2 (AC1.3.1 after the API password
change, AC1.2.1 after fixing the expected status code) · failed: 1 (AC1.4.3) · not run: 1
(AC1.1.2) · User-reported issues since last sprint: 1 (containers not monitored, now Sprint 6) ·
Open security findings: 4 of the baseline 9 remain (S0.3 partial, S0.7, S0.8, S0.9) · New issues
found by this sprint: 1 (I-011) · Tests: 13 Sprint 1 rows, 11 passing. Counted 2026-11-16.

### Review
(the planner's notes after reviewing the diff)

## Sprint 0 Handoff: baseline (2026-11-16)
**Status:** ⚠️ Done with gaps
**Commit / PR:** docs are commit `6e81e92`; the config fixes that preceded them are `d052b8e`.
Both pushed to `origin/main` (`maysaraadmin/Monitoring_With_Prometheus-and-Grafana`). No PR —
see D-008.

### Delivered
No features were built in this sprint. An existing 2023 Compose stack was made to run, then
documented as five retroactive sprint sections.

- F0.1.1 Five-service Compose definition — ACs passing: 4/4
- F0.2.1 node-exporter with host mounts, F0.2.2 Prometheus scrape config — ACs passing: 2/3 (AC0.2.3 not yet run)
- F0.3.1 Provisioned datasource, F0.3.2 Provisioned dashboard — ACs passing: 3/4 (AC0.3.4 not yet run)
- F0.4.1 Alert rules, F0.4.2 Alertmanager routing — ACs passing: 3/5 (AC0.4.4 not run, AC0.4.5 failing)
- F0.5.1 Blackbox modules, F0.5.2 Probe job with relabelling — ACs passing: 3/3

Four config bugs were fixed to get there (commit `d052b8e`, and I-001 to I-005 in
`docs/Issues.md`):
1. `prometheus/alert_rules.yml` — `rules:` under the `NodeMemUsgae` group was indented 3 spaces instead of 2. Prometheus validates rule files at startup and exited, so **the stack had never started as committed**.
2. `alertmanager/alertmanager.yml` — the `to:` placeholder contained an apostrophe inside a single-quoted YAML scalar, which also broke startup.
3. `docker-compose.yml` — Grafana bind-mounted `/grafana_data` instead of the `grafana_data` named volume the file already declared, so dashboards were lost on `docker compose down`.
4. `docker-compose.yml` — Grafana moved to host port 3001 (D-007) because port 3000 is held on this machine by an unrelated Forgejo container, and the home dashboard was set so the root URL opens the Node Exporter dashboard.

Docs created: `Implementation.md`, `Security_issues.md`, `Test_scenarios.md`, `UI_guidelines.md`,
`Decisions.md`, `Issues.md`, `Handoff.md`.

**Sprints 1–5 planned in full**, approved by the user the same day: 56 new acceptance criteria
across 20 features, each with its threats in `Security_issues.md` and its test rows in
`Test_scenarios.md`, written together rather than deferred. Nothing from them is built yet.

| Sprint | Goal | Features | ACs |
|---|---|---|---|
| 1 | Secure the stack — unpublish 9100/9115, loopback-bind the rest, real Grafana password, credentials out of the index | 4 | 13 |
| 2 | Correct the alert rules and actually deliver notifications | 5 | 14 |
| 3 | CI config validation, rule unit tests, secret scanning | 4 | 11 |
| 4 | Decide what is monitored, pin images, choose retention, drill a restore | 4 | 11 |
| 5 | Runbook, and make the loopback assumption self-defending | 3 | 7 |

### Not delivered / deferred
- No code or config was changed for Sprints 1–5. They are planned only; the next session starts at "start sprint 1".
- No pull request to `upstream`. Fixes 1 and 2 are genuine upstream bugs, but 3 and 4 are local preferences, so the commit would need splitting first (D-008).
- The blackbox dashboard shown in the README does not exist in this repo and is not planned.
- **D-011 is deliberately left open:** what this stack should actually measure. It blocks F4.1 and needs the user, not an executor.

### Tests
Config validation (promtool / amtool / compose) 4/4 · Integration (service APIs) 11/13 with 3 not run · Manual 0/1 · Security 1/7
Totals, counted on 2026-11-16: **27 scenario rows — 16 passing, 8 failing, 3 not yet run.**
The 8 failures are not regressions; they are the pre-existing gaps this baseline set out to find.

### Security
- Controls in place: container isolation on a user-defined bridge network; read-only host mounts for node-exporter; named volumes rather than host paths.
- **Open threats from the baseline: 9 — re-rated to 2 High, 5 Medium, 2 Low.** All in `docs/Security_issues.md` under "Sprint 0", with an audit table dated 2026-11-16. Sprints 1–5 add 16 forward-looking threats, so the file now holds 25 in total.
- **The re-rating matters and is recorded as D-010.** The user confirmed this stack runs only on one Windows workstation behind NAT, so the five "unauthenticated service on `0.0.0.0`" findings drop one level: LAN-reachable, not internet-reachable. The original VPS-assumption ratings are kept in brackets in the threat table, so the reasoning can be re-applied if this ever moves to a server.
- **Two findings did not drop**, because network position is irrelevant to them: S0.3 (credentials in tracked files — the fork is a *public* GitHub repo) and S0.7 (notification failure is undetected — monitoring that cannot report its own deafness is broken anywhere).
- The headline finding is **S0.4**: blackbox-exporter is published on `0.0.0.0:9115` with no authentication, which makes it an SSRF relay — any caller can ask it to fetch any URL from inside the network, including cloud metadata endpoints. Nothing needs port 9115 on the host, because Prometheus reaches it over the Compose network, so the fix is to stop publishing it.
- S0.1, S0.2, S0.5 and S0.6 are the same shape: four services with no auth, all bound to every interface. S0.3 is credentials in tracked files on a now-public fork. S0.7 is that notification failure is itself undetected.
- Severities assume a host with a public IP, as the README's "monitor a Linux server" framing implies. On a laptop behind NAT the practical risk is much lower. **This assumption needs the user's confirmation** — it changes whether Sprint 1 is urgent or routine.
- No penetration testing was done: nothing was attacked from off-host, so the `T0.S*` rows are reasoned from port bindings rather than demonstrated.

### Deviations from plan
Phase 0 assumes an application codebase with a test suite. This repo is 12 config files with no
code, no tests and no CI, so three steps were adapted:
- "Map the existing tests" became defining the config validators and API assertions as the test suite (D-009). There was no prior test to map.
- "Write `UI_guidelines.md` from the real design" — there is no design of ours. The file documents dashboard-JSON conventions and is explicit that Grafana owns the design system.
- The generic security control list is mostly about money, ownership and roles, none of which exist here. It was rewritten as a table of what applies and what does not, rather than dropped.

### Known issues & tech debt
Ten gaps, G-001 to G-010 in `docs/Implementation.md`. The ones that would bite first:
- **G-002** — `HostMemoryIsUnderutilized` compares a byte count (14.9 GB observed) to the literal `80`, so it fires permanently on a healthy host. The alert name, its `critical` severity and its description ("< 20% for 1 week") contradict both each other and the expression. Someone needs to decide what this rule was *meant* to detect; it cannot be fixed mechanically.
- **G-001** — no alert email has ever been delivered. Gmail returns `535 BadCredentials` and Alertmanager retries every 30 seconds, which is also an abuse risk against the account (S0.8).
- Taken together with D-004 (two targets fail on purpose), five alerts fire permanently. The moment notifications work, the on-call gets an unactionable alert twice a minute and learns to ignore the channel. Sprint 2 should address the rules and the delivery together, not separately.
- **G-003** — no CI. Both startup-blocking bugs were YAML parse errors that `promtool` and `amtool` catch in under a second, which is the strongest available argument for Sprint 3.

### How to run / demo
```
docker compose up -d
```
- Grafana http://localhost:3001 — `admin` / `admin`. The root URL opens "Node Exporter Full"; direct link http://localhost:3001/d/rYdddlPWk/node-exporter-full
- Prometheus http://localhost:9090 — `/alerts` shows 5 firing, `/targets` shows 6 targets with 2 down by design
- Alertmanager http://localhost:9093 · node-exporter http://localhost:9100/metrics · blackbox http://localhost:9115
- Validation commands are in `docs/Implementation.md` under "How to run". In Git Bash on Windows they need `MSYS_NO_PATHCONV=1`, or Git rewrites the container paths to `C:/Program Files/Git/...` and promtool reports a missing file.

### Next sprint should know
- **Read `docs/Decisions.md` D-004 first.** Two targets fail on purpose, as teaching aids. Do not "fix" them by deleting the targets without deciding what demonstrates the alert path instead.
- D-001 to D-006 were reconstructed from code and git history, not recorded at the time. The "Why" lines are inference. If the user remembers different reasoning, correct them.
- **D-007 (port 3001) looks wrong for anyone else.** It solves a clash specific to this machine and contradicts the README and the upstream article. If this stack moves to a server where 3000 is free, supersede it rather than carrying it forward.
- `.env` and the file named `config` (no extension) are tracked, hold placeholder credentials and are referenced by nothing — not by `docker-compose.yml`, not by any service. Delete them or wire them up in Sprint 1; leaving them is how a real password gets committed by accident.
- The `grafana` service runs `user: '0'` (root). Probably to dodge a volume-permission problem that the named volume may have already solved. Worth testing whether it can be dropped.
- **I-010 was raised from Medium to High after the user's answer, and it is the most important thing in this handoff.** The stack runs only on this Windows workstation — and node-exporter reads the WSL2 VM's `/proc`, so the machine this exists to monitor is the one machine it is not monitoring. The dashboard shows plausible numbers that refer to a VM nobody cares about, which is worse than showing nothing. Recorded as D-011, deliberately left **Open**, and planned as F4.1 with AC4.1.1 so Sprint 4 cannot close without a decision between `windows_exporter`, accepting the VM, or moving to a Linux host. Do not let it close silently.
- **Sprint 1 before Sprint 2, and Sprint 1's F1.4 before Sprint 2's F2.4.** F2.4 puts a real Gmail app password into the stack; F1.4 is what makes a tracked file an impossible place to put it. Doing them in the other order is how S0.3 becomes a real leak in a public repo.
- Two planned tests are deliberately written to **fail first**: T1.S3 must fail before `git rm --cached` (proving that `.gitignore` alone does not untrack a tracked file) and T3.7 must fail against the pre-Sprint-2 memory rule (proving the fixtures would have caught G-002). If either passes on the first run, the test is not reaching what it claims to test.
- T1.2 and T4.S4 need a second device on the network. They cannot be run from this host, and asserting the bind address from `docker compose ps` alone is not the same check.
- The IDE's markdownlint flags table-pipe spacing and blank lines around tables throughout `docs/`. There is no markdownlint config in the repo and the rules are style-only, so they were left alone. Add a config or ignore them, but do not reformat all seven files by hand.

### Metrics
**Sprint 0 baseline:** ACs passed first run 15/19 (3 not yet verified, 1 failing) · User-reported
issues since last sprint: 3 (the stack not starting, the dashboard not showing, and where to
push) · Open security findings from the baseline: 9 (2 High, 5 Medium, 2 Low after the D-010
re-rating) · Open issues: 5 of 10 · Baseline tests: 27 scenario rows, 16 passing.

**Doc set after planning Sprints 1–6:** 92 acceptance criteria · 33 features · 115 test rows ·
30 threats · 12 decisions · 7 docs. Sprint 6 (container monitoring) was added later the same
day, after the user asked whether the stack monitors Docker containers — it monitors none. See
D-012.

All counted mechanically on 2026-11-16, not estimated. Checks that passed at the time of writing:
every one of the 75 acceptance criteria appears in `Test_scenarios.md`; every one of the 25
threat IDs has a test row; every test ID cross-referenced from `Security_issues.md` resolves;
every file path named in the docs exists, except three that Sprints 3 and 5 are planned to create
(`.github/workflows/validate.yml`, `prometheus/alert_rules_test.yml`,
`docs/Go_live_checklist.md`). Re-run those four checks before trusting this entry if the docs
have been edited since.

### Review
(the planner's notes after reviewing the diff)
