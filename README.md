# Monitoring with Prometheus and Grafana
Monitoring Linux Server with Prometheus and Grafana. Node and Blackbox exporter. Alert Manager.

<p align="center">
<img alt="Prometheus" width="270px" src="https://raw.githubusercontent.com/devicons/devicon/develop/icons/prometheus/prometheus-original.svg " style="padding-right:10px ;"/> &nbsp
<img alt="Grafana" width="270px" src="https://raw.githubusercontent.com/devicons/devicon/develop/icons/grafana/grafana-original.svg" style="padding-right:10px;" />
</p>
</br>

# Monitoring your own VPSes

Two independent halves. Do the first one even if you never do the second.

### 1. Site and certificate monitoring — works immediately

Up/down, HTTP status, response time and TLS-expiry alerts for any public URL.
Nothing to install on the server, nothing to open in a firewall: the probe is an
ordinary outbound request, so it works from behind NAT.

```bash
cp prometheus/targets/sites.yml.example prometheus/targets/sites.yml
# edit it: add your URLs
docker compose restart prometheus
```

**Each site then has its own dashboard**, at

```
http://localhost:3001/d/website-monitoring/website-monitoring?var-site=https://yoursite.com
```

Bookmark one URL per site. It is a single templated dashboard, not a file per site, so a new
site appears in the `Site` dropdown as soon as you add it to `sites.yml` — nothing per-site has
to be created. The top of the page also lists every site at once in one table.

Per site you get: status, uptime over the selected range, HTTP code, days until the TLS
certificate expires, an availability timeline, total response time, and a breakdown of where
that time went (DNS, connect, TLS, server processing, transfer) — which is the panel that tells
you *why* a site got slow.

**Want a separate dashboard per site** instead of one with a dropdown? Generate them:

```bash
python scripts/make-site-dashboards.py
docker compose restart grafana
```

That writes one `site-<slug>.json` per site currently being probed, each appearing in Grafana
under its own name, and removes the ones for sites you have stopped probing. Safe to re-run; it
only touches `site-*.json`. The panels are derived from `websites.json`, so edit that one file
and re-run to change them all.

### 2. Host metrics (CPU, memory, disk) — needs one command per server

Prometheus *pulls*, so it must reach each server's node-exporter. Dialling out
from a NAT'd machine is fine; the work is making port 9100 reachable **privately**.
Set up a mesh VPN (Tailscale or WireGuard) between this machine and your servers
first, or use an SSH tunnel. Do **not** open 9100 to the internet — it is
unauthenticated and indexed by internet-wide scanners.

On each VPS, as root:

```bash
curl -fsSL <this-repo>/raw/main/scripts/install-node-exporter.sh -o install-node-exporter.sh
less install-node-exporter.sh      # read it first; it runs as root
bash install-node-exporter.sh 100.101.102.103    # the PRIVATE address to bind
```

The script verifies the download's checksum, installs a hardened systemd unit,
refuses to bind to `0.0.0.0`, and prints the line to add here. Then:

```bash
cp prometheus/targets/vps.yml.example prometheus/targets/vps.yml
# edit it: add each server
docker compose restart prometheus
```

The bundled "Node Exporter Full" dashboard picks up the new servers in its
`node` dropdown with no further work.

Both target files are gitignored, so your server addresses and domain list stay
out of this public repo.

### One limitation, stated plainly

This stack collects only while this machine is awake, and it cannot tell you
when it has stopped. It will answer *"how have my servers been behaving?"*, with
gaps wherever the machine was off. It is **not** reliable for *"page me when a
server goes down"* — the likeliest time to miss an outage is overnight, which is
also when this machine is least likely to be on. For real paging, run an
external uptime service alongside it, or move this stack onto a server.
See `docs/Decisions.md` D-014.

### Access

Grafana http://localhost:3001 · Prometheus http://localhost:9090 · Alertmanager
http://localhost:9093 — all bound to loopback only. node-exporter and blackbox
have no host port; Prometheus reaches them over the Compose network.

The Grafana password lives in `.env.local` (untracked):
`cp .env.local.example .env.local` and set one before first start. If Grafana
rejects a password you know is right, check `docker logs grafana` for
"login for user temporarily blocked" — five failed attempts locks the account for
about five minutes.

Planning, security findings and decisions are in [docs/](docs/).

# Introduction:
Prometheus is a open-source platform for monitoring hardware and services. It collects metrics from the system of any other services that we configured.

## Setup:
In this article we are going to see how to setup monitoring of a linux machine.

I’m going to use Docker to setup this process, however you can install binaries as usual. The docker compose consists of multiple components.

- First setup - Prometheus with Grafan. Viewing Server resources usgae using Node Exporter.
- Second setup - Prometheus alert manager for mail alerts for server usage.
- Third setup - Prometheus Blackbox exporter setup to view and monitor website metrics. Also sendd alerts.
</br>
<h3> <strong> Read the full articles on: </strong> </h3> <a href = "https://medium.com/devops-dev/setup-monitoring-prometheus-and-grafana-2431b26cd757" target ="_blank">

<picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://github.com/sagarkrp/sagarkrp/blob/main/images/Medium-white1x.png" width="160px" height="35px">
   <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/sagarkrp/sagarkrp/main/images/Medium-dark.svg" width="160px" height="35px">
   <img alt="Medium Alternative Theme." src="https://raw.githubusercontent.com/sagarkrp/sagarkrp/main/images/Medium-dark.svg" width="160px" height="35px">
</picture> </a> </br> &nbsp

# Node Exporter Dashboard:
![image](https://github.com/sagarkrp/Prometheus_Grafana/assets/42873729/096fb27b-af85-4fdb-95bd-655c2a77463f)

# Blackbox Dashboard
![blackbox](https://github.com/sagarkrp/Monitoring_With_Prometheus-and-Grafana/assets/42873729/2dbc07a8-bc27-4866-a293-646420df3d44)
