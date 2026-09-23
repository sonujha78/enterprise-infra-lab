# NAT Gateway Setup (vpn-gateway as internal network's internet gateway)

## Problem
Containers on the `internal` Docker network (internal: true) have no route to
the internet by design, simulating private VM subnets with no direct exposure.
However, package installation for LDAP/Nagios/Zabbix/OpenVPN requires internet
access at setup time.

## Solution
vpn-gateway is attached to both `dmz` (internet-facing) and `internal`
(private) networks. It was configured as a NAT router:

1. Enabled IP forwarding inside vpn-gateway via docker-compose sysctls:
   net.ipv4.ip_forward=1

2. Added a MASQUERADE rule on vpn-gateway:
   iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE

3. Added a default route on each internal container pointing to vpn-gateway
   (10.20.0.10), via nsenter into each container's network namespace:
   ip route add default via 10.20.0.10

4. Overrode DNS on each internal container to a public resolver, since
   Docker's embedded DNS (127.0.0.11) cannot resolve external names on an
   internal-only network:
   echo 'nameserver 1.1.1.1' > /etc/resolv.conf

## Verification
- Raw TCP connect test (bypassing DNS) from target1 to 1.1.1.1:80 succeeded,
  confirming NAT/routing works.
- apt-get update succeeded on target1, target2, monitoring-server, and
  ldap-server after the DNS fix.

## Note
This mirrors a real VPN gateway's role: all traffic from the private subnet
is routed and NATed through a single gateway box, and no target server is
directly reachable from or to the public internet.
