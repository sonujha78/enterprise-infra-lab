# Nagios vs Zabbix — Honest Comparison

This is based on actually setting up both tools side by side to monitor the same two target servers (ping, SSH, disk space, CPU load), not just reading feature lists.

## 1. Which was easier to configure for a new host?

**Zabbix was noticeably easier.** Adding target1 and target2 was: install zabbix-agent, set Server/ServerActive/Hostname in one config file, then create the host in the web UI and attach the "Linux by Zabbix agent" template. The template already ships with dozens of checks (CPU, memory, disk, network) - no need to write check definitions by hand.

Nagios required manually writing host and service `.cfg` blocks (host_name, address, check_command, use template) for every host/service combination, defining a custom `check_nrpe_1arg` command ourselves since it isn't there by default, and separately installing + configuring `nagios-nrpe-server` on every target with `allowed_hosts` and custom `command[...]` lines in `nrpe.cfg`. It works, but it's a lot more manual wiring for the same result.

## 2. Which gives better historical trending/graphing?

**Zabbix, by a wide margin.** Zabbix stores time-series history/trends in its database from day one and gives you graphs out of the box for every numeric item, plus a modern dashboard (widgets, top-hosts-by-CPU, geomap, etc.) with no extra setup.

Nagios Core's web UI is fundamentally a real-time status board (CGI pages), not a trending tool. Graphing isn't built in - PNP4Nagios or similar has to be added separately to get anything like Zabbix's graphs. Out of the box, Nagios tells you "is it OK right now and for how long," not "how has this metric moved over the last week."

## 3. Which has a better alerting/escalation model?

**Zabbix's model is more flexible; Nagios's is simpler.** Nagios alerting is check-result-driven: a service's state (OK/WARNING/CRITICAL) changes, contacts/contact groups get notified per host or service, with escalation via notification periods and intervals. It's straightforward and battle-tested.

Zabbix separates data collection (items) from alerting (triggers, which are expressions over item data) from what happens next (actions, which can filter by severity/tag/host group and run different operations at different steps - e.g., email at step 1, run a script at step 3). This is more powerful for larger, more nuanced environments, but it's also more concepts to learn (items -> triggers -> actions vs. Nagios's more direct service-check -> notify).

## 4. When would you pick one over the other in a real job?

**Nagios** still makes sense when: the environment is small/simple, the team already has Nagios expertise and config files in place, or the priority is a lightweight, plugin-based tool with a huge, mature ecosystem of existing check plugins (`check_*` scripts) for almost anything. It's also common in older/regulated environments (banks, government) that adopted it years ago and have no strong reason to migrate.

**Zabbix** is the better choice when: you're starting fresh, you want built-in trending/graphing without bolting on extra tools, you'll be managing many hosts (auto-discovery + templates scale much better than hand-written `.cfg` files), or the team wants a modern web UI for both monitoring and light configuration work without editing config files by hand.

In this lab specifically: Zabbix took less manual configuration once the server itself was running, and its dashboard/graphing was immediately useful. Nagios took more up-front config work per host but the resulting setup was easy to reason about and debug (plain text files, no database needed for the core monitoring engine itself — only the web frontend files are static).

## 5. What we actually hit while building both

- Both Nagios and Zabbix (like every other service in this Docker-based lab) needed to be started manually, since the containers have no systemd/init - `service X start` after every container restart, or packages reinstalled entirely if a container was recreated.
- Nagios's CGI pages initially downloaded as files instead of rendering, because Apache's `cgi` module wasn't enabled and a leftover default vhost was competing for port 80.
- Zabbix's web installer needs a `mysqld.sock` directory that PHP-FPM (running as `www-data`) can actually traverse - the default `/var/run/mysqld` permissions (700) blocked this until it was loosened.
- Zabbix's nginx config defaults to port 8080, which conveniently avoided a port clash with Nagios's Apache instance on port 80, letting both run on the same monitoring server at once.
- The Zabbix agent shipped in target1/target2's default Ubuntu repo was an older major version (5.0) than the Zabbix server (6.4), but passive/active checks still worked fine across that gap.
