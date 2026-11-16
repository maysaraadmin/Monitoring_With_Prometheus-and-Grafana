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
| T0.4.4 | AC0.4.4 | integration | `GET :9093/api/v2/alerts` | the firing Prometheus alerts also listed in Alertmanager | ⬜ not yet run |
| T0.4.5 | AC0.4.5 | manual | let an alert fire and check the on-call inbox | email arrives | ❌ fails: Gmail `535 BadCredentials` in `docker logs alertmgr` (G-001) |
| T0.4.6 | G-002 | static | assert `HostMemoryIsUnderutilized` does not fire on a healthy host | rule should not be firing | ❌ fails: fires permanently, `node_memory_MemAvailable_bytes` was 14943088640 against a threshold of `80` |

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
| T0.S7 | S0.7 | query `alertmanager_notifications_failed_total` and assert an alert rule exists that fires on it | a rule covers notification failure | ❌ fails: no such rule, so a broken alert channel is invisible |

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
| T1.1 | AC1.1.1 | integration | `docker compose ps --format '{{.Ports}}'` and grep for `0.0.0.0` and `::` | no match | ⬜ |
| T1.2 | AC1.1.2 | integration | from a second device on the LAN, curl ports 3001, 9090, 9093, 9100, 9115 on this host's LAN IP | all refused or timed out | ⬜ *(manual — needs a second device)* |
| T1.3 | AC1.1.3, S1.4 | integration | after unpublishing 9100 and 9115, read `/api/v1/targets` | `node` and `blackbox` targets still `up` | ⬜ |
| T1.4 | AC1.1.4 | integration | on this host, curl `http://localhost:3001/api/health` | HTTP 200 | ⬜ |
| T1.5 | AC1.2.1 | integration | `curl -XPOST http://localhost:9090/-/reload` with the lifecycle flag removed | 405 or 404, and the config is not reloaded | ⬜ |
| T1.6 | AC1.2.2 | integration | change the scrape interval, `docker compose restart prometheus`, read `/api/v1/status/config` | the new value is in effect | ⬜ |
| T1.7 | AC1.3.1 | integration | `curl -u admin:admin http://localhost:3001/api/datasources` | 401 | ⬜ |
| T1.8 | AC1.3.2 | integration | same call with the chosen password | 200 | ⬜ |
| T1.9 | AC1.3.3 | integration | fetch the login page and grep for a sign-up link | no link present | ⬜ |
| T1.10 | AC1.3.4 | static | `git status --short` with `.env.local` present and populated | `.env.local` is not listed | ⬜ |
| T1.11 | AC1.4.1 | static | `git ls-files \| grep -E '^(\.env\|config)$'` | no match | ⬜ |
| T1.12 | AC1.4.2 | static | `amtool check-config /config/alertmanager.yml` with `auth_password_file` in use | SUCCESS | ⬜ |
| T1.13 | AC1.4.3 | integration | start Alertmanager with the secret file missing | exits with an error naming the missing file, rather than starting unauthenticated | ⬜ |

### Security tests
| ID | Covers threat | Scenario | Expected | Status |
|---|---|---|---|---|
| T1.S1 | S1.1 | assert the bind address from outside the container (`docker compose ps`, plus `netstat` on the host), not by reading the YAML | every listener on 127.0.0.1 only | ⬜ |
| T1.S2 | S1.2 | with the existing Grafana volume in place, set the new password and then attempt `admin`/`admin` | rejected — proving the env var took effect rather than being ignored on an initialised database | ⬜ |
| T1.S3 | S1.3 | `git ls-files` after adding `.gitignore` but before `git rm --cached` | the test must FAIL at that point, proving ignoring alone does not untrack; then passes after `git rm --cached` | ⬜ |

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

---

Known exceptions, deliberate: S0.8 (the 30s Gmail retry loop) and S0.9 (`latest` image tags)
are Medium and have no test row — the first is verified by reading `repeat_interval`, the second
needs an image scanner that Sprint 4 introduces.

Verified on 2026-11-16: all 19 acceptance criteria in `docs/Implementation.md` appear here, and
all 7 security test rows map to a threat ID in `docs/Security_issues.md`.
