# Decisions

D-001 to D-006 are recorded retroactively from the code and git history (2023-08-26 onward);
nobody wrote them down at the time, and the reasoning is inferred from the configuration and
the README. Treat the "Why" lines on those as reconstruction, not testimony.

## D-001 Stack and hosting (2023-08-26) *(recorded retroactively)*
**Decision:** Prometheus for metric storage and rule evaluation, node-exporter for host
metrics, blackbox-exporter for website probing, Alertmanager for notification routing, Grafana
for dashboards. All as containers on a single host.
**Why:** The standard open-source metrics stack. Pull-based scraping needs no agent
configuration per target, and every component is a single static binary with a config file.
**Rejected alternatives:** A hosted service (Datadog, Grafana Cloud) — cost, and the project is
a teaching article. The TICK or ELK stacks — heavier, and logs are not in scope.
**Status:** Active

## D-002 Docker Compose rather than binaries or Kubernetes (2023-08-26) *(recorded retroactively)*
**Decision:** Ship one `docker-compose.yml` with all five services on a user-defined bridge
network, rather than installing binaries with systemd units.
**Why:** Service discovery by container name means the configs can hardcode `prometheus:9090`
and `node-exporter:9100` and work unchanged on any host. One command to start and stop.
**Rejected alternatives:** Distribution packages and systemd — the README says binaries work
too but are more setup. Kubernetes — disproportionate for one host.
**Status:** Active

## D-003 Provisioning as code for Grafana (2023-08-26) *(recorded retroactively)*
**Decision:** Define the Grafana datasource and dashboard as files under
`grafana/provisioning/`, mounted into the container, instead of clicking them in the UI.
**Why:** A recreated container comes back with the datasource and dashboard already present.
The dashboard JSON is reviewable in git.
**Rejected alternatives:** Manual setup, or the Grafana HTTP API from a script — neither
survives a container rebuild without extra work.
**Status:** Active

## D-004 A deliberately-down target and a deliberately-failing probe (2023-08-26) *(recorded retroactively)*
**Decision:** Keep the `dummy_node` scrape job pointed at `localhost:1234` and the blackbox
target `http://example.com:8080`, both of which always fail.
**Why:** They make `InstanceDown` and `BlackboxProbeHttpFailure` fire on a fresh install, so a
reader of the article sees the alerting path work without breaking anything real.
**Rejected alternatives:** Documenting how to simulate a failure instead — more steps for the reader.
**Consequence to respect:** Two alerts are *expected* to be firing at all times. Anyone judging
the health of this stack by "are there alerts" will be misled, and so will the on-call once
notifications work. Revisit in Sprint 2.
**Status:** Active

## D-005 Gmail SMTP for notifications (2023-08-26) *(recorded retroactively)*
**Decision:** A single Alertmanager receiver sending email through `smtp.gmail.com:587`.
**Why:** Zero infrastructure; everyone has a Gmail account; an app password is enough.
**Rejected alternatives:** Slack, Telegram or PagerDuty webhooks — each needs an account and a
token, and email is the lowest common denominator for an article.
**Consequence to respect:** Gmail requires an app password, not the account password, and
rejects anything else with `535`. The committed values are placeholders, so delivery has never
worked (G-001).
**Status:** Active

## D-006 Alert thresholds and intervals as written (2023-08-26) *(recorded retroactively)*
**Decision:** 30s scrape interval, 15s `for:` windows, `repeat_interval: 30s`.
**Why:** Fast feedback while following along with the article.
**Consequence to respect:** These are demonstration values, not production ones. A 30s repeat
interval means a firing alert re-notifies twice a minute.
**Status:** Active — to be superseded in Sprint 2.

## D-007 Grafana on host port 3001 (2026-11-16)
**Decision:** Publish Grafana as `3001:3000` instead of `3000:3000`.
**Why:** Port 3000 on this machine is held by an unrelated Forgejo container, so the Grafana
container could not bind and the stack came up without a usable dashboard.
**Rejected alternatives:** Stopping Forgejo — it is another live service. Leaving 3000 and
documenting the clash — the stack simply fails to start.
**Consequence to respect:** This differs from upstream and from every URL in the README and the
article. It is local to this fork.
**Status:** Active

## D-008 Fork rather than contribute upstream (2026-11-16)
**Decision:** Push to `maysaraadmin/Monitoring_With_Prometheus-and-Grafana` with the original
kept as the `upstream` remote. No pull request opened.
**Why:** Only read access on the original repo. Two of the four Sprint 0 fixes are genuine
upstream bugs, but the port change and the home-dashboard setting are local preferences, so a
clean PR would need the commit split first.
**Rejected alternatives:** A new standalone repo — loses the ability to `git fetch upstream`.
**Status:** Active

## D-009 Config validators as the test suite (2026-11-16)
**Decision:** Treat `promtool check config`, `promtool check rules`, `amtool check-config` and
`docker compose config` as this project's tests, run inside the running containers, plus HTTP
assertions against the service APIs. No new test framework or language runtime is introduced.
**Why:** There is no application code to unit test. The two bugs that actually broke this stack
were YAML parse errors, which `promtool` and `amtool` both catch. The tools ship inside the
images already, so there is nothing to install.
**Rejected alternatives:** A Python or Go test harness with a YAML library — it would
re-implement validation that the upstream binaries already do better. `promtool test rules`
with unit-test fixtures — worth adding in Sprint 3 once the rule expressions are corrected, but
it tests rule logic, not config validity.
**Status:** Active

## D-010 Deployment context: one NAT'd Windows workstation (2026-11-16)
**Decision:** Treat this stack as running only on a single Windows workstation behind NAT, with
no port forwarding and no public IP. Security severities are rated against that, and the target
state is loopback-only bindings rather than TLS and authentication in front of each service.
**Why:** Confirmed by the user. It is the difference between nine findings that need fixing this
week and nine that need fixing as ordinary hygiene. Rating them as if they were internet-facing
would be wrong in the other direction: it inflates the work and teaches the reader to ignore
severities.
**What it does not excuse:** two findings are unaffected by network position and keep their
original rating — S0.3, because the fork is a public GitHub repo, and S0.7, because monitoring
that cannot report its own failure is broken regardless of who can reach it.
**Rejected alternatives:** A reverse proxy with TLS and basic auth in front of all five services
— correct for a server, disproportionate for loopback-only on one machine, and it adds a
component to maintain. Leaving the VPS-based severities in place — they would be inaccurate, and
inaccurate severities are worse than none.
**Consequence to respect:** This is the assumption the whole security plan rests on. If the stack
ever moves to a host with a public IP, or a port is published for convenience, **supersede this
decision first** and re-rate the findings — the original VPS ratings are kept in brackets in
`docs/Security_issues.md` for exactly that. Sprint 5 makes the assumption self-defending (S5.1)
rather than relying on anyone remembering it.
**Status:** Active

## D-011 What this stack actually measures (2026-11-16)
**Decision:** Open question, deliberately not settled. Recorded now so it is not forgotten.
**The problem:** node-exporter reads `/proc` and `/sys`, which inside Docker Desktop belong to
the WSL2 virtual machine, not to Windows. So the "Node Exporter Full" dashboard describes a
Linux VM nobody cares about, while the user's actual machine is unmonitored. The numbers look
plausible, which is what makes it a trap — they simply do not refer to the host.
**Options:** Add `windows_exporter` on the host and scrape it for real Windows metrics; or accept
that the VM is what is measured and treat this as a learning stack; or move the whole thing to a
Linux server where node-exporter is correct by construction.
**Why it is not decided here:** It changes what the project is for, which is the user's call, not
an executor's. Planned as F4.1 with AC4.1.1 so Sprint 4 cannot close without an answer.
**Status:** Open — blocks F4.1

## D-012 Container monitoring is in scope, as Sprint 6 (2026-11-16)
**Decision:** Add per-container monitoring with cAdvisor, planned as Sprint 6. The stack's
purpose widens from "monitor a Linux server" to "monitor this Docker host, including the
containers on it".
**Why:** The user asked whether the stack monitors all Docker containers. It monitors none.
Verified the same day: of 624 metric names in Prometheus, zero begin with `container_`,
`docker_` or `engine_`, while 11 containers were running. node-exporter measures a host and has
no concept of Docker; blackbox probes URLs from outside. Nothing in Sprints 0–5 closed this, so
it needed its own sprint rather than a line in an existing one.
**Rejected alternatives:**
- *The Docker daemon's own `/metrics` endpoint.* Far lighter and needs no socket mount, but it reports daemon-level metrics, not per-container CPU and memory, so it does not answer "which container is eating the machine". It is still worth enabling later as a cheap addition.
- *Doing it inside Sprint 1.* Tempting, since both touch exposure, but it would mix adding a privilege with removing several, and Sprint 1's value is that it only ever subtracts access.
- *Not doing it.* The user has 11 containers across several projects on one workstation and no visibility into any of them.
**Consequence to respect:** cAdvisor needs the Docker socket, which is **root on the host** — a
larger privilege than everything else in this stack combined, and `:ro` on the mount does not
restrict the API (S6.1). Sprint 6 must not publish a port (AC6.1.1, AC6.4.4) and must decide
between the raw socket and a read-only proxy (F6.4). Six of the 11 containers belong to
unrelated projects; monitoring them means this repo holds an inventory of them.
**Status:** Active — Sprint 6 planned, nothing built

## D-013 Config reload by restart, not by the lifecycle API (2026-11-16)
**Decision:** Prometheus runs without `--web.enable-lifecycle`. To apply a config or rule
change, run `docker compose restart prometheus`.
**Why:** The flag exposes `POST /-/reload` to anyone who can reach port 9090, and Prometheus has
no authentication. Sprint 1 bound the port to loopback as well, but the flag was removed too
because defence in depth costs nothing here: a restart of this stack takes about two seconds and
there is no reload workflow that needs the endpoint.
**Verified:** `POST /-/reload` now returns **403**, not the 405 or 404 the plan predicted. The
plan's expected value was wrong and has been corrected in `docs/Implementation.md` (AC1.2.1).
**Consequence to respect:** A restart drops the in-memory state Prometheus has not yet written
to disk, which is seconds of samples, not hours. If Sprint 4 chooses a long retention this is
still safe; the TSDB is on a named volume.
**Rejected alternatives:** Keeping the flag because loopback binding already protects it — true,
but it is one more thing that has to stay true. A `SIGHUP` instead — same effect as a restart,
and less obvious to a reader.
**Status:** Active

## D-014 Monitor remote VPSes, with the collector staying on the workstation (2026-11-16)
**Decision:** The targets are the user's own remote Linux VPSes. Prometheus, Alertmanager and
Grafana stay on this NAT'd Windows workstation. Planned as Sprint 7.
**Why the user chose it:** Nothing new has to be stood up or paid for, and the security posture
Sprint 1 just established for the monitoring host stays valid.
**Why the pull direction is not the problem people expect:** Prometheus dials out. A NAT'd
collector reaching a remote target is the easy direction. The difficulty is entirely at the far
end — port 9100 has to accept a connection from a source address that changes, which is what
makes a firewall IP allowlist the wrong tool here (AC7.1.3) and a mesh VPN or SSH tunnel the
right one (F7.1).
**The limitation the user accepted, stated plainly:** monitoring stops whenever this workstation
sleeps, reboots or is switched off, and the stack cannot tell anyone that it has stopped. So:

- It **can** answer "how have my servers been behaving?" and "what did CPU and disk do last Tuesday?" — with holes wherever the laptop was off.
- It **cannot** be relied on to tell you a server went down, because the most likely time to miss an outage is overnight, which is also when the workstation is least likely to be awake.
- The dead-man's-switch planned in F2.5 cannot cover this. A dead-man's-switch needs an observer that outlives the thing it watches, and here the observer and the watched are the same machine.

Recorded as threat **S7.4**, rated High, because it survives perfectly correct configuration.
It is a misunderstanding rather than a misconfiguration, and the only fix is that someone knows.
**What follows from accepting it:** real downtime paging, if it is wanted, needs something outside
this stack — an external uptime service, which is cheap or free at this scale. AC7.4.3 forces
that to be decided rather than assumed. F7.4 also requires the gap to be visible *in Grafana*,
not only written down here, because the dashboard is what anyone will actually look at.
**Rejected alternatives:**
- *Moving Prometheus onto a VPS.* The technically correct answer: monitoring that runs on a server is awake when the user is not, and it removes S7.4 entirely. Declined for now. It would mean superseding D-010 and restoring the five network findings to their original High ratings, because the host would have a public IP — the work Sprint 1 did would need redoing against a harder threat model. Worth revisiting if the gaps become annoying in practice; that is the signal to come back to this.
- *A firewall allowlist on each VPS instead of a private transport.* Fails on a dynamic source address, and the failure looks like "the servers are down" (S7.2), which is the worst possible way for it to fail.
- *Exposing node-exporter publicly with TLS and basic auth.* Supported by node-exporter, and workable, but it puts an authenticated service on the public internet for every VPS, and port 9100 is indexed by internet-wide scanners. A private transport is less work and strictly better.
- *Pushgateway.* Designed for batch jobs, not for host metrics. It would invert the direction so the VPSes push, which avoids the inbound problem, but it loses the `up` metric — and `up` is the one thing most worth having when a server dies.
**Consequence to respect:** this workstation becomes part of the production trust boundary. The
transport credentials on it grant network reach to every VPS (S7.3). That raises the stakes on
the secrets handling Sprint 1 put in place: `secrets/` is now protecting server access, not just
a mailbox password.
**Status:** Active — Sprint 7 planned, nothing built
