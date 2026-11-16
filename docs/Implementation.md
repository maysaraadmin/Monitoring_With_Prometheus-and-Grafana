# Implementation Plan: Monitoring with Prometheus and Grafana

## Overview
A Docker Compose monitoring stack for a Linux host. Prometheus scrapes host metrics from
node-exporter and website availability from blackbox-exporter, evaluates alert rules, and
routes firing alerts to Alertmanager, which emails them. Grafana reads Prometheus and renders
the "Node Exporter Full" dashboard. There are two human roles: the **operator**, who opens
Grafana to see current state, and the **on-call**, who receives alert email.

This repo is a fork of `sagarkpanda/Monitoring_With_Prometheus-and-Grafana`
(remote `upstream`). It is configuration only — there is no application source code.

## Stack
Metrics store · Prometheus (latest) — Collectors · node-exporter, blackbox-exporter (latest)
Alerting · Alertmanager (latest) to Gmail SMTP — Dashboards · Grafana (latest)
Runtime · Docker Compose on Docker Desktop / WSL2 — CI · none (see gap G-003)
See D-001.

## How to run
- Start: `docker compose up -d`
- Stop: `docker compose down` (add `-v` to drop metric and dashboard data)
- Validate config (this project's test suite — see `docs/Test_scenarios.md`):
  - `MSYS_NO_PATHCONV=1 docker exec prometheus promtool check config /etc/prometheus/prometheus.yml`
  - `MSYS_NO_PATHCONV=1 docker exec prometheus promtool check rules /etc/prometheus/alert_rules.yml`
  - `MSYS_NO_PATHCONV=1 docker exec alertmgr amtool check-config /config/alertmanager.yml`
  - `docker compose config --quiet`
  - `MSYS_NO_PATHCONV=1` is needed only in Git Bash on Windows; omit it elsewhere.
- URLs: Grafana http://localhost:3001 (`admin`/`admin`) · Prometheus http://localhost:9090
  · Alertmanager http://localhost:9093 · node-exporter http://localhost:9100
  · blackbox http://localhost:9115

## Sprint Status
| Sprint | Goal | Status | Handoff |
|---|---|---|---|
| 0.1 | Compose stack and networking (existing) | ✅ | Sprint 0 |
| 0.2 | Host metrics collection (existing) | ✅ | Sprint 0 |
| 0.3 | Grafana provisioning (existing) | ✅ | Sprint 0 |
| 0.4 | Alert rules and routing (existing) | ⚠️ | Sprint 0 |
| 0.5 | Blackbox website probing (existing) | ✅ | Sprint 0 |
| 1 | Secure the stack | ⬜ | |
| 2 | Correct the alert rules and deliver notifications | ⬜ | |
| 3 | CI config validation | ⬜ | |
| 4 | Real targets, pinned images, retention and restore | ⬜ | |
| 5 | Go-live and runbook | ⬜ | |
| 6 | Container monitoring (cAdvisor) | ⬜ | |

Sprints 1–5 were approved by the user on 2026-11-16 and planned in detail below.
Deployment context confirmed the same day: **one Windows workstation behind NAT** (D-010),
which is why Sprint 1 is hygiene rather than an emergency.

---

## Sprint 0.1: Compose stack and networking (existing)
**Definition of done:** `docker compose up -d` brings up five containers on one bridge
network; every service answers its own health endpoint.

### F0.1.1 Five-service Compose definition
- [x] `docker-compose.yml` defines node-exporter, prometheus, alertmanager, blackbox, grafana
- [x] One user-defined bridge network `monitoring` so services resolve each other by name
- [x] Named volumes for the Prometheus TSDB, Alertmanager state and Grafana data
- [x] `restart: unless-stopped` on every service

**Acceptance criteria**
- AC0.1.1: Given a clean checkout, when `docker compose up -d` runs, then five containers reach state `Up`.
- AC0.1.2: Given the stack is up, when each service health endpoint is requested, then all five return HTTP 200.
- AC0.1.3: Given the stack is up, when Prometheus resolves `node-exporter`, `blackbox` and `alertmanager` by name, then each resolves on the `monitoring` network.
- AC0.1.4: Given `docker-compose.yml`, when `docker compose config --quiet` runs, then it exits 0.

## Sprint 0.2: Host metrics collection (existing)
**Definition of done:** Prometheus holds host CPU, memory, disk and network series.

### F0.2.1 node-exporter with host mounts
- [x] `/proc`, `/sys` and `/` mounted read-only, with matching `--path.*` flags
- [x] Pseudo-filesystems excluded from the filesystem collector

### F0.2.2 Prometheus scrape configuration
- [x] 30s global scrape interval; `node` job scraping `node-exporter:9100`
- [x] `prometheus` self-scrape job

**Acceptance criteria**
- AC0.2.1: Given the stack is up, when the Prometheus targets API is queried, then the `node` and `prometheus` targets report health `up`.
- AC0.2.2: Given node-exporter is scraped, when `node_uname_info` is queried, then at least one series is returned.
- AC0.2.3: Given the filesystem collector excludes pseudo-filesystems, when `node_filesystem_size_bytes` is queried, then no series has a mountpoint under `/sys`, `/proc`, `/dev` or `/host`.

## Sprint 0.3: Grafana provisioning (existing)
**Definition of done:** a fresh Grafana container comes up with the Prometheus datasource and
the Node Exporter dashboard already present, with no manual clicks.

### F0.3.1 Provisioned datasource
- [x] `grafana/provisioning/datasources/datasource.yml` points at `http://prometheus:9090`, set as default

### F0.3.2 Provisioned dashboard
- [x] File provider in `grafana/provisioning/dashboards/dashboard.yml`
- [x] `grafana/provisioning/dashboards/node_exporter.json` ("Node Exporter Full")
- [x] Dashboard set as the default home dashboard via `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`

**Acceptance criteria**
- AC0.3.1: Given a recreated Grafana container, when the datasources API is queried, then exactly one Prometheus datasource exists with URL `http://prometheus:9090` and `isDefault` true.
- AC0.3.2: Given a recreated Grafana container, when the dashboard search API is queried, then "Node Exporter Full" is listed.
- AC0.3.3: Given the dashboard datasource variable resolves to the default datasource, when a panel query such as `node_load1` is run through the Grafana query API, then it returns data frames rather than a datasource error.
- AC0.3.4: Given `docker compose down` then `up -d` without `-v`, when Grafana restarts, then dashboard edits made in the UI survive.

## Sprint 0.4: Alert rules and routing (existing)
**Definition of done:** rule breaches raise alerts in Prometheus and reach Alertmanager.
⚠️ **Gaps:** email delivery fails (G-001) and one rule expression is wrong (G-002).

### F0.4.1 Alert rules
- [x] Four rules in four groups: `InstanceDown`, `HostMemoryIsUnderutilized`, `BlackboxProbeHttpFailure`, `BlackboxSslCertificateWillExpireSoon`
- [x] `dummy_node` job scraping `localhost:1234`, down on purpose to demonstrate `InstanceDown`

### F0.4.2 Alertmanager routing
- [x] Prometheus `alerting:` block targets `alertmanager:9093`
- [x] Single `Mail Alert` receiver over Gmail SMTP
- [ ] Working SMTP credentials — **open, see G-001**

**Acceptance criteria**
- AC0.4.1: Given `alert_rules.yml`, when `promtool check rules` runs, then it reports 4 rules and exits 0.
- AC0.4.2: Given `alertmanager.yml`, when `amtool check-config` runs, then it reports SUCCESS with 1 receiver.
- AC0.4.3: Given a target is down, when the `for:` window elapses, then Prometheus reports the `InstanceDown` alert as firing.
- AC0.4.4: Given an alert is firing in Prometheus, when Alertmanager is queried, then the same alert appears in its alert list.
- AC0.4.5: Given an alert reaches Alertmanager, when the notification is dispatched, then the on-call receives email. *(manual)* — **failing, see G-001**

## Sprint 0.5: Blackbox website probing (existing)
**Definition of done:** Prometheus reports HTTP reachability and TLS expiry for a list of URLs.

### F0.5.1 Blackbox exporter modules
- [x] `blackbox/blackbox.yml` with http, tcp, icmp and grpc prober modules

### F0.5.2 Probe scrape job with relabelling
- [x] `blackbox` job with `metrics_path: /probe` and `module: [http_2xx]`
- [x] Relabel chain moving `__address__` into `__param_target` and pointing `__address__` at `blackbox:9115`
- [x] Three demo targets, one failing on purpose to demonstrate the probe-failure alert

**Acceptance criteria**
- AC0.5.1: Given the blackbox job, when the targets API is queried, then the probe targets appear with `instance` set to the probed URL, not to `blackbox:9115`.
- AC0.5.2: Given a reachable HTTPS target, when `probe_success` is queried, then it is 1.
- AC0.5.3: Given a reachable HTTPS target, when `probe_ssl_earliest_cert_expiry` is queried, then a future timestamp is returned.

### Progress notes
- 2026-11-16 — Brought under the sprint-spec workflow. Four config errors were fixed first
  (commit `d052b8e`): a 3-space indent on `rules:` in `alert_rules.yml` that stopped Prometheus
  from starting, an apostrophe inside a single-quoted YAML string in `alertmanager.yml`, a
  Grafana bind mount of `/grafana_data` instead of the declared named volume, and the Grafana
  host port moved 3000 to 3001 because port 3000 was already taken locally. Stack verified up
  with all five health endpoints returning 200.

---

## Sprint 1: Secure the stack
**Definition of done:** from another device on the same network, none of the five services
answers. From this host, Grafana still works, needs a real password, and every Prometheus target
is still `up`. No credential is in a tracked file.

**Needs from the user:** a Grafana admin password (they choose it; it goes in an untracked file).

### F1.1 Stop publishing the ports that nothing needs
- [ ] Remove the `ports:` block from `node-exporter` — only Prometheus scrapes it, over the `monitoring` network
- [ ] Remove the `ports:` block from `blackbox` — same, and it closes the SSRF relay (S0.4)
- [ ] Bind Prometheus to `127.0.0.1:9090:9090` and Alertmanager to `127.0.0.1:9093:9093`
- [ ] Bind Grafana to `127.0.0.1:3001:3000`
- [ ] Add a comment above each `ports:` entry recording that loopback-only is a deliberate control, so the next edit does not silently undo it (S5.1)

**Acceptance criteria**
- AC1.1.1: Given the stack is up, when `docker compose ps` is read, then no published port is bound to `0.0.0.0` or `::`.
- AC1.1.2: Given the stack is up, when `curl http://<this-host-lan-ip>:9090/-/ready` is run from another device on the network, then the connection is refused or times out, and the same holds for ports 3001, 9093, 9100 and 9115.
- AC1.1.3: Given ports 9100 and 9115 are no longer published, when the Prometheus targets API is queried, then the `node` and `blackbox` targets are still `up`.
- AC1.1.4: Given the stack is up, when `curl http://localhost:3001/api/health` is run on this host, then it returns 200.

### F1.2 Drop the Prometheus lifecycle API
- [ ] Remove `--web.enable-lifecycle` from the Prometheus command
- [ ] Note in `docs/Decisions.md` how to reload config without it (`docker compose restart prometheus`)

**Acceptance criteria**
- AC1.2.1: Given the flag is removed, when `POST http://localhost:9090/-/reload` is sent, then it returns 405 or 404 rather than reloading.
- AC1.2.2: Given the flag is removed, when `docker compose restart prometheus` is run after a config change, then the new config is in effect and `promtool check config` still passes.

### F1.3 Real Grafana credentials, from an untracked file
- [ ] Create `.env.local` (untracked) holding `GF_SECURITY_ADMIN_PASSWORD` and `GF_SECURITY_ADMIN_USER`
- [ ] Reference it from the `grafana` service with `env_file:`, and set `GF_USERS_ALLOW_SIGN_UP=false`
- [ ] Commit `.env.local.example` with placeholder values and no real secret
- [ ] Because Grafana only reads the admin password when it initialises its database, change the existing password through the API as well, or recreate the volume (S1.2)

**Acceptance criteria**
- AC1.3.1: Given the new password is configured, when a login with `admin`/`admin` is attempted, then it is rejected.
- AC1.3.2: Given the new password is configured, when a login with the chosen password is attempted, then it succeeds.
- AC1.3.3: Given `GF_USERS_ALLOW_SIGN_UP=false`, when the Grafana login page is opened, then no sign-up link is offered.
- AC1.3.4: Given `.env.local` exists, when `git status --short` is run, then `.env.local` is not listed as untracked or modified, because `.gitignore` covers it.

### F1.4 Get the placeholder credential files out of the repo
- [ ] Add `.env`, `.env.local` and `config` to `.gitignore`
- [ ] `git rm --cached .env config` — ignoring a tracked file does not untrack it (S1.3)
- [ ] Switch `alertmanager.yml` to `auth_password_file: /run/secrets/smtp_password` and mount that file from an untracked path, so Sprint 2 has nowhere to commit a real password
- [ ] Delete the `config` file outright if nothing uses it, rather than leaving a decoy

**Acceptance criteria**
- AC1.4.1: Given the change, when `git ls-files` is run, then neither `.env` nor `config` appears.
- AC1.4.2: Given `alertmanager.yml` uses `auth_password_file`, when `amtool check-config` runs, then it reports SUCCESS.
- AC1.4.3: Given the secret file is absent, when Alertmanager starts, then it fails loudly with a readable error rather than starting with no password.

### Progress notes

## Sprint 2: Correct the alert rules and deliver notifications
**Definition of done:** on a healthy stack, no alert fires except the clearly-named deliberate
demonstrations. A real test alert arrives by email. If the mail path breaks, something says so.

**Needs from the user:** a Gmail address and app password (or a decision to use a different
channel), plus a decision on what `HostMemoryIsUnderutilized` was meant to detect.

### F2.1 Fix or replace the broken memory rule
- [ ] Decide the intent: the name says underutilized, the description says "< 20% for 1 week", the severity says critical, and the expression compares bytes to `80`. These are four different rules
- [ ] Rewrite as a ratio, not a byte count — for example `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100`
- [ ] Give it a `for:` window that matches the intent, and a severity that matches the consequence
- [ ] Make the description agree with the expression
- [ ] Replace the `{__name__="…", instance="…"}` form with a plain selector; hardcoding `instance` means the rule silently stops working if the target is renamed

**Acceptance criteria**
- AC2.1.1: Given a host with ample free memory, when the rules are evaluated, then the memory rule is not firing.
- AC2.1.2: Given the rule's threshold is crossed in a `promtool test rules` fixture, then the rule fires.
- AC2.1.3: Given the rule text, when its description and its expression are compared, then the threshold and the window stated in the description match the expression.
- AC2.1.4: Given a second node-exporter target is added, when the rules are evaluated, then the memory rule covers it without being edited.

### F2.2 Fix the SSL expiry rule
- [ ] Make the description's day count match the expression's (G-006)
- [ ] Exclude plain-http targets, which have no certificate and currently alert anyway

**Acceptance criteria**
- AC2.2.1: Given the blackbox targets include `http://prometheus.io`, when the rules are evaluated, then no SSL-expiry alert is raised for a non-TLS target.
- AC2.2.2: Given the rule text, when the description is compared to the expression, then both state the same number of days.

### F2.3 Make the deliberate demonstrations read as deliberate
- [ ] Keep `dummy_node` and the failing blackbox target (D-004), but rename or label them so an operator sees at a glance that they are intentional — for example a `purpose: demo` label
- [ ] Add that label to the alert annotations, so a notification about them is self-explanatory

**Acceptance criteria**
- AC2.3.1: Given the stack is healthy, when `/api/v1/alerts` is read, then every firing alert carries the demo label.
- AC2.3.2: Given a demo alert notification, when it is read, then it states that the target fails by design.

### F2.4 Working notification delivery
- [ ] Put the real app password in the untracked secret file from F1.4 — never in `alertmanager.yml`
- [ ] Raise `repeat_interval` from 30s to something humane, 4h or more (S0.8)
- [ ] Send a test alert and confirm it arrives

**Acceptance criteria**
- AC2.4.1: Given valid credentials, when an alert fires, then `docker logs alertmgr` shows no `Notify attempt failed`.
- AC2.4.2: Given valid credentials, when an alert fires, then the email arrives in the on-call inbox. *(manual)*
- AC2.4.3: Given `repeat_interval` is raised, when an alert stays firing for an hour, then at most one notification is sent in that hour.

### F2.5 Detect it when alerting itself breaks
- [ ] Add an alert on `rate(alertmanager_notifications_failed_total[5m]) > 0`
- [ ] Add a dead-man's-switch: an always-firing low-severity alert whose *absence* is the signal
- [ ] Document what to check when the switch goes quiet

**Acceptance criteria**
- AC2.5.1: Given the SMTP password is deliberately wrong, when notifications fail, then the notification-failure alert fires within 5 minutes.
- AC2.5.2: Given the dead-man's-switch rule, when the rules are evaluated on a healthy stack, then it is firing.
- AC2.5.3: Given Prometheus is stopped, when the external check for the dead-man's-switch runs, then its absence is reported. *(manual)* — needs something outside this stack to watch it, which is a known limit of a single-host setup.

### Progress notes

## Sprint 3: CI config validation
**Definition of done:** a push that breaks any config fails on GitHub before it can be pulled
onto the host. The two bugs that blocked Sprint 0 would both have been caught.

**Needs from the user:** nothing. Actions are already enabled on the fork
(`allowed_actions: all`, confirmed 2026-11-16).

### F3.1 Validation workflow
- [ ] `.github/workflows/validate.yml`, triggered on `push` and `pull_request` to `main`
- [ ] Run `promtool check config` and `promtool check rules` using the `prom/prometheus` image
- [ ] Run `amtool check-config` using the `prom/alertmanager` image
- [ ] Run `docker compose config --quiet`
- [ ] Set `permissions: contents: read` and expose no secrets to the job (S3.1)
- [ ] Pin each action to a commit SHA (S3.2)

**Acceptance criteria**
- AC3.1.1: Given a commit that reintroduces the 3-space indent on `rules:`, when CI runs, then the job fails and names the rule file.
- AC3.1.2: Given a commit that reintroduces the apostrophe in the Alertmanager `to:` value, when CI runs, then the job fails and names `alertmanager.yml`.
- AC3.1.3: Given the current `main`, when CI runs, then every step passes.
- AC3.1.4: Given the workflow file, when its `permissions` block is read, then it grants only `contents: read`.

### F3.2 Rule unit tests
- [ ] Add `prometheus/alert_rules_test.yml` with `promtool test rules` fixtures for each of the four rules
- [ ] Cover the case that broke: a healthy host must not fire the memory rule
- [ ] Run it in CI

**Acceptance criteria**
- AC3.2.1: Given the fixtures, when `promtool test rules` runs, then all cases pass.
- AC3.2.2: Given a fixture with healthy memory values, when the memory rule is evaluated, then no alert is produced.
- AC3.2.3: Given the pre-Sprint-2 memory rule, when the fixtures run against it, then they fail — proving the tests would have caught G-002.

### F3.3 Secret scanning
- [ ] Add a secret-scan step that fails the build on a committed credential (S3.3, closing S0.3 mechanically)
- [ ] Assert it catches a planted test credential, then remove the plant

**Acceptance criteria**
- AC3.3.1: Given a commit containing a Gmail-app-password-shaped string, when CI runs, then the job fails.
- AC3.3.2: Given the current `main`, when the secret scan runs, then it passes.

### F3.4 Housekeeping
- [ ] Remove the obsolete `version:` key from `docker-compose.yml` (G-010)
- [ ] Add a `.markdownlint.json` or an ignore rule, so the IDE stops flagging the docs on style-only rules

**Acceptance criteria**
- AC3.4.1: Given the key is removed, when any `docker compose` command runs, then no obsolete-version warning is printed.
- AC3.4.2: Given the lint config, when `docs/` is opened in the editor, then no style-only warnings are reported.

### Progress notes

## Sprint 4: Real targets, pinned images, retention and restore
**Definition of done:** the stack monitors something the user actually cares about, on pinned
image versions, with a retention policy that was chosen rather than defaulted, and a restore
that has been performed at least once.

**Needs from the user:** the list of hosts and URLs worth monitoring, a decision on
`windows_exporter` (see AC4.1.1), and a retention period.

### F4.1 Decide what is actually being monitored
- [ ] Settle I-010: node-exporter reports the WSL2 VM, not Windows. The user confirmed the stack runs only on this Windows workstation, so decide between adding `windows_exporter` for real host metrics, or accepting that the VM is what is measured
- [ ] If `windows_exporter` is added, bind it to loopback and add a scrape job for it (S4.4)
- [ ] Replace the demo blackbox targets with URLs the user cares about, keeping one demo failure (D-004)

**Acceptance criteria**
- AC4.1.1: Given the decision is made, when `docs/Decisions.md` is read, then a dated decision records what is monitored and what is knowingly not.
- AC4.1.2: Given `windows_exporter` is in scope, when `node_cpu_seconds_total` and the Windows CPU metric are compared against Task Manager, then the Windows figures match within normal sampling error.
- AC4.1.3: Given the real blackbox targets, when the targets API is queried, then each intended URL appears and probes successfully.

### F4.2 Pin the image versions
- [ ] Replace every `:latest` with an explicit version for all five images (G-008, S0.9)
- [ ] Record the pinned versions and the date in `docs/Decisions.md`
- [ ] Add a scheduled CI job that reports when a newer version exists, so pinning does not become staleness (S4.1)

**Acceptance criteria**
- AC4.2.1: Given `docker-compose.yml`, when it is grepped for `:latest`, then there are no matches.
- AC4.2.2: Given a fresh `docker compose pull` a month later, when the image IDs are compared, then they are unchanged.
- AC4.2.3: Given a newer upstream release exists, when the scheduled job runs, then it reports which images are behind.

### F4.3 Choose a retention period
- [ ] Set `--storage.tsdb.retention.time` explicitly instead of relying on the 15d default (G-009)
- [ ] Record the disk cost of the chosen period

**Acceptance criteria**
- AC4.3.1: Given the flag is set, when the Prometheus runtime-info API is queried, then `storageRetention` equals the chosen value.
- AC4.3.2: Given the chosen retention, when the TSDB directory size is measured after a week, then the projected full-retention size is recorded in the handoff.

### F4.4 Back up and prove a restore
- [ ] A documented command to back up the `prometheus_data` and `grafana_data` volumes
- [ ] Document where backups are written and who can read them (S4.2)
- [ ] Perform a restore into a scratch volume and confirm the data is really there (S4.3)

**Acceptance criteria**
- AC4.4.1: Given the backup command, when it is run, then an archive of both volumes exists.
- AC4.4.2: Given the archive, when it is restored into a scratch stack, then Grafana shows the dashboard and Prometheus answers a query for a date inside the backed-up range. *(manual)*
- AC4.4.3: Given the restore drill, when `docs/Handoff.md` is read, then it records the date it was performed and how long it took.

### Progress notes

## Sprint 5: Go-live and runbook
**Definition of done:** someone who is not the author can start, verify, diagnose and recover
this stack from the runbook alone, and a forgotten secret cannot pass as configured.

**Needs from the user:** a reviewer to follow the runbook on a clean checkout without help.

### F5.1 The runbook
- [ ] `docs/Go_live_checklist.md`: every step a command with its expected result and a "done (date, name)" column
- [ ] Cover first start, verifying each service, rotating the Grafana password, changing the SMTP secret, adding a target, restoring a backup
- [ ] A diagnosis section for the failures already seen: Prometheus exiting on a bad rule file, Alertmanager exiting on bad YAML, a port already in use, Grafana showing a welcome page, `MSYS_NO_PATHCONV` on Git Bash

**Acceptance criteria**
- AC5.1.1: Given a clean checkout and the runbook, when a reviewer who has not seen this project follows it, then the stack comes up with no questions asked of the author. *(manual)*
- AC5.1.2: Given each runbook step, when it is read, then it states an exact command and an expected result, not a description.
- AC5.1.3: Given each failure in the diagnosis section, when it is deliberately reproduced, then the documented symptom matches what actually appears.

### F5.2 Make the loopback assumption self-defending
- [ ] Put the assumption as a comment beside every `ports:` entry, not only in the docs (S5.1)
- [ ] Add a startup check, or a CI check, that fails if a port is bound to `0.0.0.0`

**Acceptance criteria**
- AC5.2.1: Given a change that binds a port to `0.0.0.0`, when the check runs, then it fails and names the service.
- AC5.2.2: Given the current config, when the check runs, then it passes.

### F5.3 Make a forgotten secret fail loudly
- [ ] A startup check that refuses to run on a placeholder value, so "remember to set X" becomes something the tooling enforces (S5.2)

**Acceptance criteria**
- AC5.3.1: Given the SMTP secret still holds a placeholder, when the stack starts, then the check fails with a message naming the setting.
- AC5.3.2: Given every secret is set to a real value, when the stack starts, then the check passes.

### Progress notes

## Sprint 6: Container monitoring
**Definition of done:** Grafana shows per-container CPU, memory, restarts and network for every
container on this host, and an alert fires when a container restart-loops or is OOM-killed.
Adding it has not widened the stack's network exposure.

**Why it is a separate sprint:** nothing in Sprints 0–5 monitors containers at all. Verified on
2026-11-16 — of 624 metric names in Prometheus, zero begin with `container_`, `docker_` or
`engine_`, while 11 containers were running on the host. node-exporter measures a *host* and has
no concept of Docker; blackbox probes URLs from outside. This is a scope change from "monitor a
Linux server" to "monitor this Docker host", recorded as D-012.

**Needs from the user:** nothing, but see D-012 — most of the 11 containers belong to unrelated
projects (Forgejo, Gitea, deploykit). Confirm they should be in scope.

**Runtime facts confirmed on this host, 2026-11-16** (the plan depends on them):
Docker Desktop, kernel `6.18.58.1-microsoft-standard-WSL2`, **cgroup v2** with the `cpuset cpu
io memory hugetlb pids rdma` controllers on the unified hierarchy. `/var/run/docker.sock` is
mountable and `/dev/kmsg` exists. cAdvisor needs all three, and cgroup v2 is the reason F6.2
verifies which metrics actually arrive instead of assuming the documented set.

### F6.1 Add cAdvisor as a sixth service
- [ ] Add `gcr.io/cadvisor/cadvisor` to `docker-compose.yml` on the `monitoring` network, pinned to a version (not `latest`, per F4.2)
- [ ] Mount what it needs read-only: `/`, `/var/run`, `/sys`, `/var/lib/docker`, and `/dev/disk`
- [ ] Do **not** publish its port — Prometheus reaches it over the Compose network, exactly as with node-exporter and blackbox after Sprint 1
- [ ] Set a memory and CPU limit; cAdvisor is the heaviest component in this stack and will happily use a whole core on a busy host
- [ ] Set `--housekeeping_interval` and disable collectors not in use, to keep that cost down

**Acceptance criteria**
- AC6.1.1: Given the stack is up, when `docker compose ps` is read, then cAdvisor is `Up` and has no published host port.
- AC6.1.2: Given cAdvisor is running, when Prometheus queries it by container name over the `monitoring` network, then its `/metrics` endpoint responds.
- AC6.1.3: Given the CPU and memory limits, when the stack has been running for an hour on this host, then cAdvisor's own `container_memory_working_set_bytes` and CPU rate are within the limits set.
- AC6.1.4: Given `docker-compose.yml`, when it is grepped for `cadvisor.*latest`, then there is no match.

### F6.2 Scrape it, and verify what cgroup v2 actually provides
- [ ] Add a `cadvisor` scrape job to `prometheus/prometheus.yml`
- [ ] Confirm which `container_*` metric families actually appear on cgroup v2, and write the list into the handoff. Several per-container disk-I/O metrics that cAdvisor documents are absent or empty under cgroup v2, and a dashboard built on the documented set will show silently empty panels
- [ ] Add a `relabel_configs` rule dropping the noisiest unused series if the TSDB growth is material against the F4.3 retention budget

**Acceptance criteria**
- AC6.2.1: Given the scrape job, when `/api/v1/targets` is queried, then the `cadvisor` target is `up`.
- AC6.2.2: Given cAdvisor is scraped, when `count(count by (name) (container_memory_working_set_bytes{name!=""}))` is queried, then the result equals the number of running containers on the host.
- AC6.2.3: Given cgroup v2, when each metric family the Sprint 6 dashboard and alerts depend on is queried, then every one returns series — and any that does not is recorded in the handoff as unavailable on this runtime, with the panel or alert removed rather than left empty.
- AC6.2.4: Given the new series, when the TSDB size is measured a week later, then the increase is recorded against the retention budget from AC4.3.2.

### F6.3 Dashboard and container alerts
- [ ] Provision a container dashboard under `grafana/provisioning/dashboards/` (Grafana dashboard 14282 is a reasonable base), following the panel and state rules in `docs/UI_guidelines.md`
- [ ] Alert on a container restart loop: `increase(container_start_time_seconds[15m])` crossing a threshold, or the equivalent restart counter
- [ ] Alert on a container OOM kill
- [ ] Alert on a container at its memory limit, as a ratio of `container_spec_memory_limit_bytes`, not an absolute byte count — the mistake G-002 made
- [ ] Exclude containers that are expected to exit, so stopped deploykit containers do not alert forever (the D-004 trap again)

**Acceptance criteria**
- AC6.3.1: Given the dashboard is provisioned, when a fresh Grafana container starts, then it is listed by `GET /api/search?type=dash-db` and its panels return data.
- AC6.3.2: Given a container is deliberately restarted three times in five minutes, when the rules are evaluated, then the restart-loop alert fires.
- AC6.3.3: Given a test container is OOM-killed by running it under a tight memory limit, when the rules are evaluated, then the OOM alert fires and names that container.
- AC6.3.4: Given a healthy host with containers that are expected to be exited, when the rules are evaluated, then no container alert is firing.
- AC6.3.5: Given the memory-limit alert, when a container has no limit set, then the rule does not fire with a divide-by-zero or absent-value artefact.

### F6.4 Contain the Docker socket exposure
- [ ] Decide between mounting `/var/run/docker.sock:ro` directly and putting a read-only socket proxy in front of it
- [ ] Whichever is chosen, record it in `docs/Decisions.md` with the reasoning, because this is the single largest privilege in the stack
- [ ] Confirm the socket is not reachable from anywhere except cAdvisor

**Acceptance criteria**
- AC6.4.1: Given the choice is made, when `docs/Decisions.md` is read, then a dated decision records it and states what an attacker who reached the socket could do.
- AC6.4.2: Given cAdvisor is running, when the compose file is read, then no service other than cAdvisor (or its proxy) mounts the Docker socket.
- AC6.4.3: Given a socket proxy is used, when a write operation is attempted through it, then it is refused while cAdvisor keeps working.
- AC6.4.4: Given the stack is up, when the loopback check from AC5.2.1 runs, then it still passes — adding cAdvisor has not published a new port.

### Progress notes

---

## Known gaps carried out of Sprint 0
| ID | Gap | Where | Severity | Planned |
|---|---|---|---|---|
| G-001 | Alertmanager SMTP has placeholder credentials; every notification fails with Gmail 535 and retries every 30s | `alertmanager/alertmanager.yml` | High | Sprint 2 |
| G-002 | `HostMemoryIsUnderutilized` compares a byte count to the literal `80`, so it is always true and fires permanently | `prometheus/alert_rules.yml` | High | Sprint 2 |
| G-003 | No CI: nothing validates the YAML before a commit, which is how the two Sprint 0 parse errors shipped | repo | Medium | Sprint 3 |
| G-004 | All five service ports are published on `0.0.0.0`, with no auth or TLS on Prometheus, Alertmanager, node-exporter or blackbox | `docker-compose.yml` | High | Sprint 1 |
| G-005 | Grafana still on `admin`/`admin`; `.env` and `config` hold placeholder credentials and are referenced by nothing | `.env`, `config` | High | Sprint 1 |
| G-006 | `SSL_Expiry` description says 200 days, the expression tests 60 | `prometheus/alert_rules.yml` | Low | Sprint 2 |
| G-007 | On Docker Desktop, node-exporter measures the WSL2 VM, not the Windows host | runtime | Medium | Sprint 4 |
| G-008 | All images pinned to `latest`; a rebuild can change versions silently | `docker-compose.yml` | Medium | Sprint 4 |
| G-009 | 15d default retention, with no documented backup or restore of the TSDB | `docker-compose.yml` | Medium | Sprint 4 |
| G-010 | The `version:` key in `docker-compose.yml` is obsolete and warns on every command | `docker-compose.yml` | Low | Sprint 3 |
