# Test Scenarios: Monitoring with Prometheus and Grafana

This project has no application code, so there is no unit test suite. Its mechanical checks are
the upstream config validators (`promtool`, `amtool`, `docker compose config`) plus API
assertions against the running stack. Until Sprint 3 wires these into CI they are run by hand
with the commands in `docs/Implementation.md` ("How to run").

Status recorded 2026-11-16 against commit `d052b8e`.

## Sprint 0.1 — Compose stack and networking
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T0.1.1 | AC0.1.1 | integration | `docker compose up -d` then `docker compose ps` | five containers `Up` | ✅ |
| T0.1.2 | AC0.1.2 | integration | curl `/-/ready` on 9090 and 9093, `/metrics` on 9100, `/-/healthy` on 9115, `/api/health` on 3001 | all HTTP 200 | ✅ |
| T0.1.3 | AC0.1.3 | integration | read `scrapeUrl` of each active target from `/api/v1/targets` | service names resolve, no target errors on DNS | ✅ |
| T0.1.4 | AC0.1.4 | static | `docker compose config --quiet` | exit 0 (warns about the obsolete `version:` key, G-010) | ✅ |

## Sprint 0.2 — Host metrics collection
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T0.2.1 | AC0.2.1 | integration | `/api/v1/targets` filtered to jobs `node` and `prometheus` | both health `up` | ✅ |
| T0.2.2 | AC0.2.2 | integration | query `node_uname_info` | at least 1 series; observed 1 (`job="node"`, `instance="node-exporter:9100"`) | ✅ |
| T0.2.3 | AC0.2.3 | integration | query `node_filesystem_size_bytes` and inspect `mountpoint` labels | no mountpoint under `/sys`, `/proc`, `/dev`, `/host` | ⬜ not yet run |

## Sprint 0.3 — Grafana provisioning
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T0.3.1 | AC0.3.1 | integration | `GET /api/datasources` as admin | one Prometheus datasource, url `http://prometheus:9090`, uid `PBFA97CFB590B2093`, default | ✅ |
| T0.3.2 | AC0.3.2 | integration | `GET /api/search?type=dash-db` | "Node Exporter Full" at `/d/rYdddlPWk/node-exporter-full` | ✅ |
| T0.3.3 | AC0.3.3 | integration | `POST /api/ds/query` with `node_load1` against the provisioned uid | status 200 with numeric data frames | ✅ |
| T0.3.4 | AC0.3.4 | integration | edit a dashboard in the UI, `docker compose down` then `up -d`, reopen | the edit is still there | ⬜ not yet run |

## Sprint 0.4 — Alert rules and routing
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T0.4.1 | AC0.4.1 | static | `promtool check rules /etc/prometheus/alert_rules.yml` | "SUCCESS: 4 rules found", exit 0 | ✅ |
| T0.4.2 | AC0.4.2 | static | `amtool check-config /config/alertmanager.yml` | SUCCESS, 1 receiver, 0 inhibit rules | ✅ |
| T0.4.3 | AC0.4.3 | integration | `/api/v1/alerts` after the `dummy_node` target has been down 15s | `InstanceDown` state `firing` for `localhost:1234` | ✅ |
| T0.4.4 | AC0.4.4 | integration | `GET :9093/api/v2/alerts` | the firing Prometheus alerts also listed in Alertmanager | ⬜ not yet run — but Alertmanager is now scraped, and its `alertmanager_notifications_failed_total{integration="email"}` shows non-zero failures, which proves alerts are reaching it |
| T0.4.5 | AC0.4.5 | manual | let an alert fire and check the on-call inbox | email arrives | ❌ fails: Gmail `535 BadCredentials` in `docker logs alertmgr` (G-001) |
| T0.4.6 | G-002 | static | assert `HostMemoryIsUnderutilized` does not fire on a healthy host | rule should not be firing | ✅ **passes since 2026-11-16** — rewritten as a ratio with `for: 1w` (D-015); state is now `pending`, not firing |

## Sprint 0.5 — Blackbox website probing
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T0.5.1 | AC0.5.1 | integration | inspect `instance` labels on the `blackbox` job targets | `instance` is the probed URL, `__address__` is `blackbox:9115` | ✅ |
| T0.5.2 | AC0.5.2 | integration | query `probe_success{instance="https://prometheus.io"}` | 1 | ✅ |
| T0.5.3 | AC0.5.3 | integration | query `probe_ssl_earliest_cert_expiry{instance="https://prometheus.io"}` | a timestamp in the future | ✅ |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T0.S1 | S0.1 | from another host on the LAN, curl `http://<host-ip>:9090/api/v1/query?query=up` | refused | ❌ fails: ports bound `0.0.0.0`, no auth (G-004) |
| T0.S2 | S0.2 | from another host on the LAN, open `http://<host-ip>:3001` and log in with `admin`/`admin` | refused | ❌ fails (G-005) |
| T0.S3 | S0.3 | `git log -p -- alertmanager/alertmanager.yml` and grep for a real password | only placeholders in history | ✅ passes today, but the file is public on the fork — see S0.3 |
| T0.S4 | S0.4 | from another host, curl `http://<host-ip>:9115/probe?target=http://169.254.169.254/&module=http_2xx` | refused | ❌ fails: blackbox is an open relay for outbound probes (G-004) |
| T0.S5 | S0.5 | from another host, POST `http://<host-ip>:9093/api/v2/silences` | refused | ❌ fails: anyone on the LAN can silence alerts (G-004) |
| T0.S6 | S0.6 | from another host on the LAN, curl `http://<host-ip>:9100/metrics` | refused | ❌ fails: port 9100 is published, and only Prometheus needs it (G-004) |
| T0.S7 | S0.7 | query `alertmanager_notifications_failed_total` and assert an alert rule exists that fires on it | a rule covers notification failure | ✅ **passes since 2026-11-16** — an `alertmanager` scrape job was added (the metric was never collected before, so no rule *could* have worked) plus `AlertmanagerNotificationsFailing`. Verified the metric arrives and already records `email` failures |

### UI checks
Grafana is third-party UI, so the design-system checks do not apply. What is worth checking on
each dashboard change:
- The home dashboard loads with data, not "No data" or "Datasource not found".
- The `job` and `node` template dropdowns populate.
- Panels render at 1280px and at 375px by device emulation (Grafana rows reflow, they do not scroll horizontally).
- Grafana dark theme, which is the default, as well as light.

Rules: every acceptance criterion above has at least one test row, and every High threat in
`docs/Security_issues.md` has at least one security test row. Where a check cannot be automated
it is marked *(manual)* in `docs/Implementation.md` and carries a `T0.x` row here.

---

## Sprint 1 — Secure the stack
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T1.1 | AC1.1.1 | integration | `docker compose ps --format '{{.Ports}}'` and grep for `0.0.0.0` and `::` | no match | ✅ only 127.0.0.1 bindings for 9090, 9093, 3001; 9100 and 9115 not published at all |
| T1.2 | AC1.1.2 | integration | from a second device on the LAN, curl ports 3001, 9090, 9093, 9100, 9115 on this host's LAN IP | all refused or timed out | ⬜ **not run** — no second device available. T1.S1 run instead; this is still the only test that proves the claim from outside |
| T1.3 | AC1.1.3, S1.4 | integration | after unpublishing 9100 and 9115, read `/api/v1/targets` | `node` and `blackbox` targets still `up` | ✅ both `up`; also confirmed by scraping each from inside the Prometheus container |
| T1.4 | AC1.1.4 | integration | on this host, curl `http://localhost:3001/api/health` | HTTP 200 | ✅ |
| T1.5 | AC1.2.1 | integration | `curl -XPOST http://localhost:9090/-/reload` with the lifecycle flag removed | refused without reloading | ✅ returns **403**, not the 405/404 the plan guessed. AC corrected in place |
| T1.6 | AC1.2.2 | integration | change the scrape interval, `docker compose restart prometheus`, read `/api/v1/status/config` | the new value is in effect | ⚠️ partial: restart-based reload exercised and `promtool check config` passes after it, but no interval change was made, so the full round trip is unproven |
| T1.7 | AC1.3.1 | integration | `curl -u admin:admin http://localhost:3001/api/datasources` | 401 | ✅ **after** the API password change. Failed first with 200, confirming S1.2 |
| T1.8 | AC1.3.2 | integration | same call with the chosen password | 200 | ✅ |
| T1.9 | AC1.3.3 | integration | fetch the login page and grep for a sign-up link | no link present | ✅ `disableUserSignUp: true` in the frontend settings |
| T1.10 | AC1.3.4 | static | `git status --short` with `.env.local` present and populated | `.env.local` is not listed | ✅ neither `.env.local` nor `secrets/` appears |
| T1.11 | AC1.4.1 | static | `git ls-files \| grep -E '^(\.env\|config)$'` | no match | ✅ |
| T1.12 | AC1.4.2 | static | `amtool check-config /config/alertmanager.yml` with `auth_password_file` in use | SUCCESS | ✅ |
| T1.13 | AC1.4.3 | integration | start Alertmanager with the secret file missing | exits with an error naming the missing file, rather than starting unauthenticated | ❌ **ran and failed.** Alertmanager started normally and `amtool check-config` reported SUCCESS with the file absent — it reads the file at notify time. Not fixable in Alertmanager; see I-011 and F5.3 |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T1.S1 | S1.1 | assert the bind address from outside the container (`docker compose ps`, plus `netstat` on the host), not by reading the YAML | every listener on 127.0.0.1 only | ✅ host `netstat` shows exactly three LISTENING sockets, all `127.0.0.1` (3001, 9090, 9093). 9100 and 9115 absent |
| T1.S2 | S1.2 | with the existing Grafana volume in place, set the new password and then attempt `admin`/`admin` | rejected — proving the env var took effect rather than being ignored on an initialised database | ✅ and it earned its place: `admin`/`admin` returned **200** with the env var set, so the env var alone was not enough |
| T1.S3 | S1.3 | `git ls-files` after adding `.gitignore` but before `git rm --cached` | the test must FAIL at that point, proving ignoring alone does not untrack; then passes after `git rm --cached` | ✅ ran in that order: `.env` and `config` were still tracked after `.gitignore` alone, then untracked |

## Sprint 2 — Correct the alert rules and deliver notifications
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T2.1 | AC2.1.1 | integration | on a healthy host, read `/api/v1/alerts` | the memory rule is not firing | ⬜ |
| T2.2 | AC2.1.2 | unit | `promtool test rules` fixture with memory below the threshold | the rule fires | ⬜ |
| T2.3 | AC2.1.3 | static | compare the rule's description text with its expression | the stated threshold and window match the expression | ⬜ |
| T2.4 | AC2.1.4 | unit | fixture with two node-exporter instances | the rule produces an alert per instance without being edited | ⬜ |
| T2.5 | AC2.2.1 | integration | read `/api/v1/alerts` with a plain-http blackbox target configured | no SSL-expiry alert for the non-TLS target | ⬜ |
| T2.6 | AC2.2.2 | static | compare the SSL rule's description with its expression | both state the same number of days | ⬜ |
| T2.7 | AC2.3.1, S2.3 | integration | on a healthy stack, read every firing alert | each carries the demo label, so nothing fires unexplained | ⬜ |
| T2.8 | AC2.3.2 | manual | read a demo alert notification | it states the target fails by design | ⬜ |
| T2.9 | AC2.4.1 | integration | `docker logs alertmgr \| grep 'Notify attempt failed'` after an alert fires | no match | ⬜ |
| T2.10 | AC2.4.2 | manual | let an alert fire, check the on-call inbox | the email arrives | ⬜ *(manual)* |
| T2.11 | AC2.4.3 | integration | keep an alert firing for an hour and count notifications | at most one in the hour | ⬜ |
| T2.12 | AC2.5.1 | integration | set the SMTP password deliberately wrong, wait 5 minutes | the notification-failure alert is firing | ⬜ |
| T2.13 | AC2.5.2 | integration | read `/api/v1/alerts` on a healthy stack | the dead-man's-switch alert is firing | ⬜ |
| T2.14 | AC2.5.3 | manual | stop Prometheus and run the external check | the switch's absence is reported | ⬜ *(manual — needs something outside this stack)* |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T2.S1 | S2.1 | after configuring the real app password, `git ls-files` and `git diff --cached` for the secret value | the password appears in no tracked file | ⬜ |
| T2.S2 | S2.2 | assert the check reaches the control it claims: break the credentials on purpose and confirm the failure alert fires, rather than only confirming that a good email sends | the failure path is proven, not assumed | ⬜ |

## Sprint 3 — CI config validation
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T3.1 | AC3.1.1 | integration | push a branch reintroducing the 3-space `rules:` indent | CI fails and names `alert_rules.yml` | ⬜ |
| T3.2 | AC3.1.2 | integration | push a branch reintroducing the apostrophe in the `to:` value | CI fails and names `alertmanager.yml` | ⬜ |
| T3.3 | AC3.1.3 | integration | run the workflow on current `main` | every step passes | ⬜ |
| T3.4 | AC3.1.4, S3.1 | static | read the workflow's `permissions` block | only `contents: read` | ⬜ |
| T3.5 | AC3.2.1 | unit | `promtool test rules prometheus/alert_rules_test.yml` | all cases pass | ⬜ |
| T3.6 | AC3.2.2 | unit | fixture with healthy memory values | no alert produced | ⬜ |
| T3.7 | AC3.2.3 | unit | run the fixtures against the pre-Sprint-2 rule | they fail, proving the tests would have caught G-002 | ⬜ |
| T3.8 | AC3.3.1 | integration | push a branch with a Gmail-app-password-shaped string | CI fails | ⬜ |
| T3.9 | AC3.3.2 | integration | run the secret scan on current `main` | passes | ⬜ |
| T3.10 | AC3.4.1 | static | run any `docker compose` command after removing `version:` | no obsolete-version warning | ⬜ |
| T3.11 | AC3.4.2 | static | open `docs/` in the editor with the lint config in place | no style-only warnings | ⬜ |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T3.S1 | S3.1 | inspect the workflow triggers and whether any secret is exposed to a fork-originated run | no secret reachable from a fork PR | ⬜ |
| T3.S2 | S3.2 | grep the workflow for action references | every action pinned to a commit SHA, not a floating tag | ⬜ |
| T3.S3 | S3.3 | plant a test credential, confirm the build fails, then remove the plant | the scan blocks it — this is what closes S0.3 mechanically | ⬜ |

## Sprint 4 — Real targets, pinned images, retention and restore
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T4.1 | AC4.1.1 | static | read `docs/Decisions.md` | a dated decision records what is monitored and what is knowingly not | ⬜ |
| T4.2 | AC4.1.2 | integration | compare the Windows CPU and memory metrics against Task Manager | they match within sampling error | ⬜ *(manual; only if `windows_exporter` is adopted)* |
| T4.3 | AC4.1.3 | integration | read `/api/v1/targets` for the real blackbox targets | each intended URL appears and probes successfully | ⬜ |
| T4.4 | AC4.2.1 | static | grep `docker-compose.yml` for `:latest` | no match | ⬜ |
| T4.5 | AC4.2.2 | integration | `docker compose pull` a month later, compare image IDs | unchanged | ⬜ |
| T4.6 | AC4.2.3 | integration | run the scheduled version-check job with a newer release available | it reports which images are behind | ⬜ |
| T4.7 | AC4.3.1 | integration | query `/api/v1/status/runtimeinfo` | `storageRetention` equals the chosen value, not the 15d default | ⬜ |
| T4.8 | AC4.3.2 | integration | measure the TSDB directory size after a week and project forward | the projection is recorded in the handoff | ⬜ |
| T4.9 | AC4.4.1 | integration | run the backup command | an archive of both volumes exists | ⬜ |
| T4.10 | AC4.4.2, S4.3 | manual | restore the archive into a scratch stack, then query a date inside the backed-up range | Grafana shows the dashboard and Prometheus returns the data — proving the archive holds real data, not an empty volume that merely mounts | ⬜ *(manual)* |
| T4.11 | AC4.4.3 | static | read the handoff after the drill | it records the date performed and how long it took | ⬜ |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T4.S1 | S4.1 | check the pinned versions against upstream releases | the scheduled job reports drift, so pinning does not become silent staleness | ⬜ |
| T4.S2 | S4.2 | check where backups are written and who can read them | not in a shared, synced or world-readable folder | ⬜ |
| T4.S4 | S4.4 | if `windows_exporter` is adopted, curl its port from another device on the LAN | refused | ⬜ |

## Sprint 5 — Go-live and runbook
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T5.1 | AC5.1.1 | manual | a reviewer who has not seen the project follows the runbook on a clean checkout | the stack comes up with no questions asked of the author | ⬜ *(manual)* |
| T5.2 | AC5.1.2 | static | read every runbook step | each states an exact command and an expected result | ⬜ |
| T5.3 | AC5.1.3 | integration | deliberately reproduce each failure in the diagnosis section | the documented symptom matches what actually appears | ⬜ |
| T5.4 | AC5.2.1, S5.1 | integration | change a port binding to `0.0.0.0` and run the check | it fails and names the service | ⬜ |
| T5.5 | AC5.2.2 | integration | run the check against the current config | passes | ⬜ |
| T5.6 | AC5.3.1, S5.2 | integration | start the stack with the SMTP secret still a placeholder | the check fails with a message naming the setting | ⬜ |
| T5.7 | AC5.3.2 | integration | start the stack with every secret set to a real value | the check passes | ⬜ |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T5.S1 | S5.1 | confirm the loopback assumption is stated beside the `ports:` entries in `docker-compose.yml`, not only in the docs | a comment is present at each binding | ⬜ |
| T5.S2 | S5.2 | confirm the placeholder check cannot be bypassed by leaving the setting absent rather than placeholder | both absent and placeholder values fail | ⬜ |

## Sprint 6 — Container monitoring
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T6.1 | AC6.1.1 | integration | `docker compose ps` with cAdvisor added | cAdvisor `Up`, with no published host port | ⬜ |
| T6.2 | AC6.1.2 | integration | from the Prometheus container, curl cAdvisor's `/metrics` by container name | responds over the `monitoring` network | ⬜ |
| T6.3 | AC6.1.3 | integration | after an hour, query cAdvisor's own CPU rate and working-set memory | both within the configured limits | ⬜ |
| T6.4 | AC6.1.4, S6.4 | static | grep `docker-compose.yml` for `cadvisor.*latest`, and read its CPU/memory limits and housekeeping interval | no `latest`; limits and interval explicitly set | ⬜ |
| T6.5 | AC6.2.1 | integration | read `/api/v1/targets` | the `cadvisor` target is `up` | ⬜ |
| T6.6 | AC6.2.2 | integration | `count(count by (name) (container_memory_working_set_bytes{name!=""}))` against `docker ps \| wc -l` | the two agree | ⬜ |
| T6.7 | AC6.2.3 | integration | query every metric family the Sprint 6 dashboard and alerts rely on, on this cgroup v2 host | each returns series; any that does not is recorded as unavailable and its panel or alert removed, not left silently empty | ⬜ |
| T6.8 | AC6.2.4 | integration | measure TSDB size a week after the cAdvisor job is added | the increase is recorded against the AC4.3.2 retention budget | ⬜ |
| T6.9 | AC6.3.1 | integration | recreate Grafana, then `GET /api/search?type=dash-db` and run a panel query | the container dashboard is listed and its panels return data | ⬜ |
| T6.10 | AC6.3.2 | integration | restart a throwaway container three times in five minutes | the restart-loop alert fires | ⬜ |
| T6.11 | AC6.3.4, S6.5 | integration | on a healthy host that has expected-exited containers, read `/api/v1/alerts` | no container alert is firing — the six exited deploykit containers must not alert forever | ⬜ |
| T6.12 | AC6.3.5 | integration | query the memory-limit rule against a container with no memory limit set | no alert, and no divide-by-zero or absent-value artefact | ⬜ |
| T6.13 | AC6.4.1 | static | read `docs/Decisions.md` | a dated decision records the socket choice and what socket access would let an attacker do | ⬜ |
| T6.14 | AC6.4.2 | static | grep `docker-compose.yml` for `docker.sock` | only cAdvisor, or its proxy, mounts it | ⬜ |
| T6.15 | AC6.4.4 | integration | re-run the AC5.2.1 loopback check after adding cAdvisor | still passes, so Sprint 6 has not undone Sprint 1 | ⬜ |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T6.S1 | S6.1, AC6.4.3 | assert the check reaches the control: through whatever socket access cAdvisor is given, attempt a *write* operation (create a container), and confirm cAdvisor keeps scraping afterwards | refused if a proxy is in use, with cAdvisor still working. If the raw socket is mounted this test will **succeed**, which is the finding, not a pass — `:ro` on a socket mount does not restrict the API | ⬜ |
| T6.S2 | S6.2 | from another device on the LAN, curl cAdvisor's port on this host | refused — the port must not be published at all | ⬜ |
| T6.S3 | S6.3 | read the labels and image tags actually present on this host's 11 containers, then check which land in metric labels | nothing secret reaches the TSDB, the F4.4 backup, or an alert notification | ⬜ |
| T6.S4 | AC6.3.3 | run a test container under a tight memory limit until the kernel OOM-kills it | the OOM alert fires and names that container | ⬜ |

## Sprint 7 — Monitor remote VPSes
| ID | Covers | Type | Scenario | Expected | Status |
|---|---|---|---|---|---|
| T7.1 | AC7.1.1 | integration | from the Prometheus container, connect to each VPS node-exporter over the private transport | all succeed | ⬜ |
| T7.2 | AC7.1.2 | manual | probe each VPS's port 9100 from an address outside the private path | refused or filtered. **Must be run from off-network** — running it from this host proves nothing, since this host is inside the private path | ⬜ *(manual)* |
| T7.3 | AC7.1.3, S7.2 | integration | force the workstation's public address to change, or reconnect the transport, and wait one scrape interval | scraping resumes with no config edit — this is the test an IP allowlist fails | ⬜ |
| T7.4 | AC7.1.4 | integration | stop the transport and read `/api/v1/targets` | targets report `down` with a connection error, not healthy-with-stale-data | ⬜ |
| T7.5 | AC7.2.1, S7.1 | integration | `ss -tlnp` on each VPS | 9100 bound to the private address only, never `0.0.0.0` or `::` | ⬜ |
| T7.6 | AC7.2.2 | integration | query `node_uname_info` | one series per VPS, each with a distinct `instance` | ⬜ |
| T7.7 | AC7.2.3 | integration | query `node_filesystem_size_bytes` for a VPS | no pseudo-filesystem mountpoints, matching this repo's own flags | ⬜ |
| T7.8 | AC7.2.4 | integration | reboot a VPS and wait | node-exporter is running again with no manual step | ⬜ |
| T7.9 | AC7.3.1 | integration | read `/api/v1/targets` | every VPS `up`, with its identifying labels present | ⬜ |
| T7.10 | AC7.3.2 | integration | open the Node Exporter Full dashboard | the `node` dropdown lists every VPS and panels render for each | ⬜ |
| T7.11 | AC7.3.3 | unit | `promtool test rules` fixture crossing a VPS disk threshold | the alert fires and names that instance | ⬜ |
| T7.12 | AC7.3.4 | unit | fixture with two VPSes of very different disk sizes, both at the same percentage used | both behave identically, proving the threshold is a ratio not an absolute | ⬜ |
| T7.13 | AC7.3.5, AC7.4.2, S7.4 | integration | interrupt one VPS's connectivity for 30 seconds; separately, take a VPS down while the workstation is off | `InstanceDown` does not fire on the blip; and after the workstation returns, nothing claims the server was up during the gap | ⬜ |
| T7.14 | AC7.4.1 | manual | sleep the workstation for an hour, wake it, open the dashboard for that window | the gap reads as a gap, not as a flat line implying idle servers | ⬜ *(manual)* |
| T7.15 | AC7.4.3 | static | read `docs/Decisions.md` | it states what this stack does and does not guarantee about being told a server is down | ⬜ |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T7.S1 | S7.1 | from an unrelated public host, curl `http://<vps-public-ip>:9100/metrics` for every VPS | refused on all of them. Run this **before** adding any scrape job, not after | ⬜ |
| T7.S3 | S7.3 | `git ls-files` and a history grep for transport keys, SSH keys and mesh auth tokens | none tracked; all under the gitignored `secrets/` | ⬜ |
| T7.S5 | S7.5 | list the labels the new targets produce, and check what reaches alert emails and the F4.4 backup | no production detail that was not meant to leave the host | ⬜ |
| T7.S6 | S7.6 | point a scrape job at a test endpoint returning a very large high-cardinality response | `sample_limit`/`label_limit` reject the scrape and Prometheus memory stays flat, rather than the target being able to exhaust the collector | ⬜ |
| T7.S7 | S7.7 | read the committed blackbox target list | it reveals only what the user accepted revealing in a public repo | ⬜ |

---

Known exceptions, deliberate: S0.8 (the 30s Gmail retry loop) and S0.9 (`latest` image tags)
are Medium and have no test row — the first is verified by reading `repeat_interval`, the second
needs an image scanner that Sprint 4 introduces.

Verified on 2026-11-16: all 19 acceptance criteria in `docs/Implementation.md` appear here, and
all 7 security test rows map to a threat ID in `docs/Security_issues.md`.
