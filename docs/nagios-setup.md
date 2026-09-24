# Nagios Core Setup

## Server
- Container: monitoring-server (10.20.0.30)
- Package: nagios4 + nagios-plugins-contrib + monitoring-plugins + nagios-nrpe-plugin
- Web UI: http://10.20.0.30/nagios4/ (login: nagiosadmin)
- Apache CGI module had to be explicitly enabled (a2enmod cgi) for status pages to render instead of downloading

## Remote checks: NRPE
nagios-nrpe-server installed and running on target1 and target2, with:
- allowed_hosts=127.0.0.1,10.20.0.30 (only monitoring-server can query)
- Custom commands defined: check_disk, check_load, check_total_procs
- Nagios server side: check_nrpe_1arg command wraps /usr/lib/nagios/plugins/check_nrpe

## Monitored services (target1, target2)
- PING
- SSH (check_ssh)
- Disk Space (via NRPE, check_disk)
- CPU Load (via NRPE, check_load)

## Note: SSH check shows CRITICAL by design
The SSH service check for target1/target2 shows CRITICAL - Socket timeout, because target1/target2's iptables rules only accept SSH from the VPN client subnet (10.8.0.0/24), and monitoring-server is not on that subnet. This is expected and correct behavior given the security requirements in Section 3 (VPN-gated SSH access) - it is not a monitoring misconfiguration. In a real deployment, the monitoring server would either be reachable via the VPN subnet or have an explicit firewall exception.

## Disk-fill alert test
Filled target1's disk to ~96% usage:

```
dd if=/dev/zero of=/tmp/fillfile bs=1M count=90000
```

Result confirmed via NRPE and the Nagios web UI:

```
DISK CRITICAL - free space: / 8093 MB (4% inode=91%)
```

Nagios correctly transitioned the Disk Space service for target1 from OK to CRITICAL after the scheduled/forced check ran. See screenshot: docs/screenshots/nagios-disk-critical.png
