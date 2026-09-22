# Enterprise Infra Lab

Hands-on lab replicating traditional enterprise infrastructure:
- Centralized authentication via OpenLDAP
- Secure remote access via OpenVPN
- Dual monitoring stack: Nagios Core + Zabbix

Built using Docker containers (VM-free) on a single Ubuntu host.

## Structure
- `ldap/` — OpenLDAP server config & bootstrap data
- `vpn/` — OpenVPN server + client certs
- `nagios/` — Nagios Core config
- `zabbix/` — Zabbix server/agent config
- `docs/` — Test evidence, screenshots, Nagios vs Zabbix comparison

## Status
🚧 Work in progress — building step by step.
