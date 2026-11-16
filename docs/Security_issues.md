# Security: Monitoring with Prometheus and Grafana

This is an infrastructure stack, not a web app with user accounts, so the generic controls are
mapped to what actually applies here. Prometheus, Alertmanager, node-exporter and
blackbox-exporter ship **with no authentication at all** — upstream treats network isolation as
the control. That makes port binding the single most important decision in this repo.

## Deployment context (sets every severity below)
Confirmed by the user on 2026-11-16: this stack runs **only on one Windows workstation behind
NAT**, with no port forwarding. See D-010.

That changes the ratings, and it is worth being precise about how:
- **Network-exposure findings drop by one level.** `0.0.0.0` on a NAT'd host means reachable
  from the local network, not from the internet. Still a real surface — any other device on the
  same Wi-Fi, any container on the host, any script in a browser on this machine — but not
  remotely exploitable.
- **Two findings do not drop at all**, because NAT is irrelevant to them:
  - **S0.3** (credentials in tracked files) — the fork is a **public** GitHub repo. Network position has nothing to do with it.
  - **S0.7** (notification failure is undetected) — a correctness problem. Monitoring that cannot tell you it has gone deaf fails at its one job whatever the network looks like.

Re-rating on 2026-11-16: **2 High, 5 Medium, 2 Low** (was 6 High, 3 Medium when the ratings
assumed a public VPS).

## Global controls (every sprint)
| Control | Applies | State today |
|---|---|---|
| Secrets only in environment variables, never in git | Yes — SMTP password, Grafana admin password | ❌ Placeholders are committed; `.env` and `config` are tracked and unreferenced (S0.3) |
| Server-side validation of input | Not applicable — no application endpoints of our own | — |
| Authorization on every resource access | Yes — all five HTTP surfaces | ❌ None of the four Prometheus-family services has auth (S0.1) |
| Rate limits and lockout on login | Yes — Grafana only | ⬜ Grafana defaults, not reviewed |
| Sessions: secure cookies, timeout, CSRF | Yes — Grafana only | ⬜ Grafana defaults over plain HTTP |
| Security headers, HTTPS only | Yes — all surfaces | ❌ Everything is plain HTTP. Accepted for a loopback-only stack (D-010); revisit if it ever leaves this host |
| File uploads | Not applicable | — |
| Audit log of logins and permission changes | Yes — Grafana | ⬜ Grafana default logging only |
| Backups, verified by restoring | Yes — TSDB and Grafana volume | ❌ No backup or restore procedure (G-009) |
| Dependency audit before every handoff | Yes — container images | ❌ All images are `latest`, never scanned (G-008) |
| Least privilege in containers | Yes | ⚠️ Grafana runs `user: '0'` (root); node-exporter mounts `/` read-only by design |

## Sprint 0 (baseline, recorded 2026-11-16)
### Threats
Severity column re-rated for the NAT'd-workstation context. The bracketed value is the original
VPS-assumption rating, kept so the reasoning stays auditable if this ever moves to a server.

| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S0.3 | SMTP and Grafana credentials live in tracked files (`alertmanager/alertmanager.yml`, `.env`, `config`) in a repo that is **public** on GitHub. Placeholders today, but the next person to fill them in commits a working Gmail app password, and git history keeps it after any later "fix" | Secrets | **High** [High] | Move secrets to an untracked env file or a Docker secret; add `.env` to `.gitignore`; use Alertmanager's `auth_password_file` | T0.S3 | ⚠️ Partly — placeholders untracked and `auth_password_file` in use, but git history keeps the old values and Sprint 2 still has to put a real password somewhere |
| S0.7 | Notification failure is silent to the operator: email has never delivered, and nothing watches whether Alertmanager can send. A real outage would raise an alert nobody receives | Alerting | **High** [High] | Fix the credentials, then add a dead-man's-switch (an always-firing alert whose *absence* pages) and an alert on `alertmanager_notifications_failed_total` | T0.S7 | ⬜ Open |
| S0.1 | Prometheus on `0.0.0.0:9090` with no auth: anyone on the local network can read every metric, including host inventory, and `--web.enable-lifecycle` lets them POST `/-/reload` | Prometheus | Medium [High] | Bind to `127.0.0.1`; drop `--web.enable-lifecycle` unless a reload workflow needs it | T0.S1 | ✅ Fixed Sprint 1 — bound to 127.0.0.1, lifecycle API removed (reload now 403) |
| S0.2 | Grafana reachable on the local network with the default `admin`/`admin` | Grafana | Medium [High] | Set an admin password from an untracked env file; disable sign-up | T0.S2 | ✅ Fixed Sprint 1 — password changed via API from untracked `.env.local`, sign-up off |
| S0.4 | blackbox-exporter on `0.0.0.0:9115` is an unauthenticated outbound-request relay (SSRF): `/probe?target=…` makes the container fetch any URL the caller names. Behind NAT the caller must be on the LAN or on this host, but the *targets* it can reach include everything inside the network perimeter, other containers on the Docker network, and WSL2-internal addresses | Blackbox | Medium [High] | Do not publish 9115 to the host at all — only Prometheus needs it, over the `monitoring` network | T0.S4 | ✅ Fixed Sprint 1 — port 9115 no longer published |
| S0.5 | Alertmanager on `0.0.0.0:9093` with no auth: anyone on the local network can create silences and suppress every alert | Alertmanager | Medium [High] | Bind to `127.0.0.1` | T0.S5 | ✅ Fixed Sprint 1 — bound to 127.0.0.1 |
| S0.8 | `repeat_interval: 30s` against Gmail with bad credentials is a self-inflicted auth-failure loop. Google may rate-limit or block the account for abuse — a consequence that lands on the user's real mailbox, not on this host, so NAT does not reduce it | Alerting | Medium [Medium] | Raise `repeat_interval` to hours; fix G-001 | — | ⬜ Open |
| S0.9 | All images are `latest`, so known-vulnerable versions are pulled silently and no scan ever runs | Supply chain | Medium [Medium] | Pin image versions or digests; scan on a schedule | — | ⬜ Open |
| S0.6 | node-exporter on `0.0.0.0:9100` discloses kernel version, filesystems, network interfaces and uptime. Reconnaissance value only, and it describes the WSL2 VM rather than anything sensitive | node-exporter | Low [Medium] | Do not publish 9100 to the host | T0.S6 | ✅ Fixed Sprint 1 — port 9100 no longer published |

### Business-logic abuse cases
Most of the generic list is about money, ownership and roles, none of which exist here. The ones
that do apply to a monitoring stack:

- **Can an unauthenticated caller read data they should not?** Yes — every metric on all four Prometheus-family ports (S0.1, S0.6).
- **Can an unauthenticated caller change state?** Yes — Alertmanager silences (S0.5) and the Prometheus reload endpoint (S0.1).
- **Can the monitoring system be turned into an attack tool against other systems?** Yes — blackbox-exporter probes arbitrary targets on request (S0.4). Behind NAT the caller has to be local, but the reach is still "anything the container can route to".
- **Can an attacker blind the monitoring?** Yes, three ways: silence everything (S0.5), rely on the already-broken email path (S0.7), or exploit that a permanently-firing bogus alert (G-002) trains the on-call to ignore the channel. The third needs no attacker at all.
- **Does sensitive data leak into responses or logs?** Metric labels carry hostnames and mount paths. Alertmanager logs the SMTP username on every failure.
- **Is anything replayable or raceable?** Not applicable — no transactions.
- **Can someone bulk-export data?** Yes — the Prometheus query API will dump any series range to an unauthenticated caller (S0.1).

---

## Sprint 1 — Secure the stack
### Threats
| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S1.1 | Closing the ports is assumed to work but never verified; a typo in the bind address leaves a service exposed while the docs claim otherwise | Compose | High | Assert the bind address from outside the container, not by reading the YAML | T1.S1 | ✅ Verified by T1.S1 (host netstat), not by reading the YAML |
| S1.2 | Moving the Grafana password to an env file leaves the old `admin`/`admin` working, because Grafana only applies `GF_SECURITY_ADMIN_PASSWORD` when it initialises its database — an existing volume keeps the old password | Grafana | High | Change it through the Grafana API, or recreate the volume, and prove the old password is rejected | T1.S2 | ✅ Confirmed, then fixed — the env var alone did not work |
| S1.3 | `.gitignore` is added but the already-tracked `.env` and `config` stay in the index, so the next edit to them is still committed | Secrets | High | `git rm --cached` them as well as ignoring them, and assert `git ls-files` no longer lists them | T1.S3 | ✅ Fixed — T1.S3 failed before `git rm --cached`, as designed |
| S1.4 | Prometheus can no longer reach node-exporter or blackbox after the ports are unpublished, because something was relying on the host port rather than the Compose network | Prometheus | Medium | Assert all targets still `up` after the change | T1.3 | ✅ Verified — `node` and `blackbox` still `up` |

### Business-logic abuse cases
Sprint 1 touches secrets and network exposure, not money, ownership or files. The relevant
questions: can an unauthenticated caller still reach any service after the change (T1.S1), and
does a secret still exist anywhere in the working tree or the index (T1.S3)? Git **history**
keeps the placeholder values regardless — that is accepted, since they were never real.

---

## Sprint 2 — Correct the alert rules and deliver notifications
### Threats
| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S2.1 | A real Gmail app password is committed while fixing G-001 — the exact failure S0.3 predicts | Secrets | High | The password only ever enters an untracked file read via `auth_password_file`; a CI secret-scan step | T2.S1 | ⬜ |
| S2.2 | Notification delivery is declared fixed on the strength of one test email, while the retry/failure path is still unmonitored | Alerting | High | A dead-man's-switch plus an alert on `alertmanager_notifications_failed_total`, and assert the latter fires when credentials are deliberately wrong | T2.S2 | ⬜ |
| S2.3 | Alert fatigue as a security failure: permanently-firing alerts (D-004, G-002) train the operator to ignore the channel, so a real alert is missed | Alerting | Medium | No alert fires on a healthy stack except the deliberate demonstrations, and those are renamed so they read as intentional | T2.7 | ⬜ |

### Business-logic abuse cases
The abuse case that matters here is self-inflicted: **can the operator be trained to ignore a
real alert?** Today, yes — five alerts fire permanently. S2.3 is the control. Also: can a silence
created to quiet the noise outlive the noise and hide a genuine incident? Silences need an
expiry, and S0.5's fix stops anyone on the LAN creating them.

---

## Sprint 3 — CI config validation
### Threats
| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S3.1 | A workflow on a public repo runs on `pull_request` from forks and gets access to secrets, or runs untrusted code from a PR branch | CI | Medium | Trigger on `push` and `pull_request` only, with no secrets exposed to the job; keep `permissions: contents: read` | T3.S1 | ⬜ |
| S3.2 | Actions are pinned to a floating major tag, so a compromised action release runs in CI | CI | Medium | Pin actions to a commit SHA | T3.S2 | ⬜ |
| S3.3 | CI validates the YAML but not the secrets, so a committed credential still ships | Secrets | High | A secret-scan step that fails the build, closing S0.3 and S2.1 mechanically | T3.S3 | ⬜ |

### Business-logic abuse cases
A public repo's CI is itself an attack surface. The questions: does any job see a secret it does
not need (S3.1), can a third party change what CI executes (S3.2), and does CI actually block
the thing it exists to block — a bad config or a leaked secret reaching `main` (S3.3)?

---

## Sprint 4 — Real targets, pinned images, retention and restore
### Threats
| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S4.1 | Pinned images are never updated, so pinning trades silent drift for silent staleness | Supply chain | Medium | A scheduled job that reports newer versions; record the pinned versions and their date | T4.S1 | ⬜ |
| S4.2 | A backup of the TSDB and the Grafana volume contains metric labels with host and path names, written somewhere less protected than the stack | Backups | Medium | Document where backups go and who can read them; keep them off any shared or synced folder | T4.S2 | ⬜ |
| S4.3 | A restore is assumed to work and never drilled, so the backup is worthless at the moment it is needed | Backups | High | An actual restore into a scratch volume, with a dated result | T4.10 | ⬜ |
| S4.4 | `windows_exporter`, if added, runs as a privileged service on the host and publishes host metrics on a new port | node-exporter | Medium | Bind it to loopback; confirm it is not reachable from the LAN | T4.S4 | ⬜ |

### Business-logic abuse cases
Backups are the bulk-export path for this project: one file holds every metric ever collected.
Who can read it, and where does it live? A restore drill is also the only check that the data is
real rather than an empty volume that merely mounts cleanly.

---

## Sprint 5 — Go-live and runbook
### Threats
| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S5.1 | The runbook documents the loopback-only assumption, and someone later publishes a port without re-reading it, silently restoring S0.1–S0.6 | Docs | Medium | State the assumption where the ports are defined, as a comment in `docker-compose.yml`, not only in the docs | T5.S1 | ⬜ |
| S5.2 | Secrets are listed in the runbook as "set these", and nothing checks they were set to real values | Secrets | High | A startup check that fails loudly on a placeholder value, so a forgotten secret cannot pass as configured | T5.S2 | ⬜ |

### Business-logic abuse cases
The go-live question for this project is the inverse of the usual one: not "can an attacker get
in" but **"will this tell me when something breaks?"** The runbook has to be verifiable — every
step a command with an expected result, so the answer is demonstrated rather than assumed.

---

## Sprint 6 — Container monitoring
### Threats
| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S6.1 | **The Docker socket is root on the host.** cAdvisor needs `/var/run/docker.sock`, and anything that can talk to that socket can start a privileged container, mount the host filesystem and read or change anything on it. `:ro` on the mount does *not* make it read-only in any useful sense — it stops the file being replaced, not the API being used to write. This single mount is a larger privilege than everything else in this stack combined | Docker | **High** | A read-only socket proxy that allows only the endpoints cAdvisor reads, rather than the raw socket; cAdvisor on no published port; a decision recorded under F6.4 stating what socket access means | T6.S1 | ⬜ |
| S6.2 | cAdvisor's own metrics endpoint discloses every container's name, image, labels, command and mount paths — a complete inventory of what runs on the host, including the unrelated projects. Published, it is better reconnaissance than node-exporter | cAdvisor | Medium | Do not publish the port at all; it is only needed on the `monitoring` network | T6.S2 | ⬜ |
| S6.3 | Container labels become metric labels, so anything secret in a label or an image tag lands in the TSDB, in the backup from F4.4, and in any alert notification | Secrets | Medium | Check the labels actually present on the 11 containers before enabling label collection; drop label sets not needed via `metric_relabel_configs` | T6.S3 | ⬜ |
| S6.4 | cAdvisor is the heaviest component here and reads every cgroup on every housekeeping interval. Mis-tuned, the monitoring becomes the load — and on a workstation that is also the thing being monitored, it distorts its own measurements | cAdvisor | Medium | CPU and memory limits, a sane `--housekeeping_interval`, unused collectors disabled, verified by AC6.1.3 | T6.4 | ⬜ |
| S6.5 | Container alerts that fire forever on containers which are *expected* to be exited — this host has six — repeat the D-004 and G-002 mistake and retrain the operator to ignore alerts | Alerting | Medium | Exclude expected-exited containers explicitly; AC6.3.4 requires a quiet healthy host | T6.11 | ⬜ |

### Business-logic abuse cases
This sprint is the first that grants a real privilege rather than merely exposing data, so the
questions change shape:

- **What can an attacker do with the capability we are adding?** With the Docker socket: everything. Start a container with `--privileged` and `-v /:/host`, and the host is theirs. This is why S6.1 is High under D-010 even though nothing new is published — the threat is not network reach, it is that a container breakout or a compromised cAdvisor image escalates straight to host root.
- **Does the new component widen the network surface?** It must not. AC6.1.1 and AC6.4.4 both assert no published port, and AC6.4.4 deliberately re-runs the Sprint 5 loopback check so adding a service cannot quietly undo Sprint 1.
- **Does new data leak anything?** Container labels and image tags are copied into metric labels and travel into backups and notifications (S6.3). Worth reading the actual labels on this host's 11 containers before turning label collection on.
- **Can the monitoring now harm what it monitors?** Yes, newly so (S6.4). cAdvisor on a workstation competes with the work being measured.
- **Is any of this in scope?** Six of the 11 containers belong to unrelated projects. Monitoring them is probably wanted, but it means this repo now holds an inventory of those projects. See D-012.

---

## Sprint 7 — Monitor remote VPSes
### Threats
This is the first sprint whose surface is **not** behind NAT. D-010 still holds for the
monitoring host, but it does not extend to the targets: a VPS has a public IP, so findings here
are rated as internet-facing.

| ID | Threat | Area | Severity | Control | Test | Status |
|---|---|---|---|---|---|---|
| S7.1 | node-exporter on a VPS bound to `0.0.0.0:9100` — the public-internet version of S0.6. Unauthenticated, and it discloses kernel version, filesystems, interfaces, uptime and process counts to anyone who scans the address. Shodan indexes port 9100 | node-exporter | **High** | `--web.listen-address=<private-ip>:9100`, verified from off-network, before any scrape job is added | T7.S1 | ⬜ |
| S7.2 | A firewall allowlist is used instead of a private transport, then silently stops matching when the workstation's address changes. Scraping fails, which looks like the servers are down, or the rule is widened "temporarily" to fix it | Network | High | A mesh VPN or SSH tunnel, so authorisation does not depend on a source IP (AC7.1.3) | T7.3 | ⬜ |
| S7.3 | The mesh VPN or SSH key material needed to reach the VPSes is committed, or ends up in a tracked file. The same failure as S0.3, but the credential now grants access to production servers rather than a mailbox | Secrets | **High** | Key material only under the gitignored `secrets/`, never in `docker-compose.yml` or any committed config; the Sprint 3 secret scan covers it | T7.S3 | ⬜ |
| S7.4 | The monitoring is trusted to report downtime that it provably cannot: the collector is off whenever the workstation is. An operator who has seen green dashboards for weeks will assume silence means health | Alerting | **High** | Document the gap where it is seen, not only in the docs (F7.4), and decide explicitly whether an external service covers paging (AC7.4.3) | T7.13 | ⬜ |
| S7.5 | Metric labels now carry production hostnames, IPs, mount paths and site names for real infrastructure, and they travel into the TSDB, the F4.4 backup, and alert emails | Secrets | Medium | Keep the backup off shared storage (S4.2); use role labels rather than revealing names where it costs nothing | T7.S5 | ⬜ |
| S7.6 | A compromised VPS serves hostile metric output to Prometheus — a very large or high-cardinality response that exhausts memory on the monitoring host | Prometheus | Medium | `sample_limit` and `label_limit` on the scrape job; the scrape timeout left at its default rather than raised | T7.S6 | ⬜ |
| S7.7 | Blackbox is pointed at the user's own sites, and the probe targets reveal which sites belong to the same owner, in a public repo | Blackbox | Low | Keep the real target list in an untracked file if that matters, or accept it | T7.S7 | ⬜ |

### Business-logic abuse cases
The shape changes again: for the first time the stack reaches *into* production.

- **What does an attacker gain from the monitoring host?** The private transport's credentials, and with them network reach to every VPS. The workstation is now part of the production trust boundary, which is an argument for D-014's rejected alternative.
- **What does an attacker gain from a target?** If node-exporter is public (S7.1), a full inventory of the server before touching it.
- **Can the monitoring be used to attack the servers?** Blackbox could already probe arbitrary URLs; Sprint 1 closed that by unpublishing it. Keep it closed — the private transport makes internal addresses reachable that were not before.
- **Can a target attack the monitoring?** Yes, newly (S7.6). Prometheus parses whatever a target returns.
- **Does anyone believe something the system cannot deliver?** Yes, and this is the one that will actually cost something (S7.4). Everything else here is a misconfiguration; this is a misunderstanding, and it survives correct configuration.

---

## Audit (2026-11-16)
First pass, done by reading the configs and probing the running stack. **Not a penetration
test:** nothing was attacked from off-host, so the `T0.S*` rows in `docs/Test_scenarios.md` are
reasoned from the port bindings rather than demonstrated. Severities are the re-rated ones for
the NAT'd-workstation context (D-010).

| ID | Finding | Severity | Fix | Status |
|---|---|---|---|---|
| S0.3 | Credential placeholders in tracked files in a public repo | High | Untracked secrets, `.gitignore`, `git rm --cached`, `auth_password_file` | ⚠️ Sprint 1 untracked them and moved Alertmanager to `auth_password_file`. Still open: git history keeps the placeholders, and Sprint 2 must place a real password without committing it |
| S0.7 | No detection of notification failure | High | Dead-man's-switch plus an alert on failed notifications | ⬜ Planned, Sprint 2 |
| S0.1 | Prometheus published unauthenticated, with the lifecycle API on | Medium | Bind to loopback, drop `--web.enable-lifecycle` | ✅ Fixed Sprint 1 — bound to 127.0.0.1, lifecycle API removed (reload now 403) |
| S0.2 | Grafana default credentials | Medium | Admin password from an untracked env file | ✅ Fixed Sprint 1 — password changed via API from untracked `.env.local`, sign-up off |
| S0.4 | blackbox-exporter published unauthenticated (SSRF relay) | Medium | Stop publishing port 9115 | ✅ Fixed Sprint 1 — port 9115 no longer published |
| S0.5 | Alertmanager published unauthenticated | Medium | Bind to loopback | ✅ Fixed Sprint 1 — bound to 127.0.0.1 |
| S0.8 | 30s retry loop against Gmail with bad credentials | Medium | Raise `repeat_interval` | ⬜ Planned, Sprint 2 |
| S0.9 | `latest` image tags, no scanning | Medium | Pin versions, scan in CI | ⬜ Planned, Sprint 4 |
| S0.6 | node-exporter published unauthenticated | Low | Stop publishing port 9100 | ✅ Fixed Sprint 1 — port 9100 no longer published |
