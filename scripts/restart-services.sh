#!/bin/bash
# Run this after `docker compose up -d` if the host/containers were restarted.
# Re-establishes routes, DNS, and starts all manually-managed services
# (this lab's containers have no systemd/supervisor, so nothing auto-starts).

set -e

echo "=== Getting container PIDs ==="
T1PID=$(docker inspect -f '{{.State.Pid}}' target1)
T2PID=$(docker inspect -f '{{.State.Pid}}' target2)
MPID=$(docker inspect -f '{{.State.Pid}}' monitoring-server)
LPID=$(docker inspect -f '{{.State.Pid}}' ldap-server)

echo "=== Adding default routes (internal containers -> vpn-gateway) ==="
sudo nsenter -t $T1PID -n ip route add default via 10.20.0.10 2>/dev/null || true
sudo nsenter -t $T2PID -n ip route add default via 10.20.0.10 2>/dev/null || true
sudo nsenter -t $MPID  -n ip route add default via 10.20.0.10 2>/dev/null || true
sudo nsenter -t $LPID  -n ip route add default via 10.20.0.10 2>/dev/null || true

echo "=== Setting DNS on internal containers ==="
for T in target1 target2 monitoring-server ldap-server; do
  docker exec $T sh -c "echo 'nameserver 1.1.1.1' > /etc/resolv.conf"
done

echo "=== NAT / forwarding on vpn-gateway ==="
docker exec vpn-gateway iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null || true

echo "=== LDAP ==="
docker exec ldap-server service slapd start || true

echo "=== sssd + sshd + NRPE + SSH firewall on targets ==="
for T in target1 target2; do
  docker exec $T sssd -D || true
  docker exec $T service ssh start || true
  docker exec $T /usr/sbin/nrpe -c /etc/nagios/nrpe.cfg -d || true
  docker exec $T update-alternatives --set iptables /usr/sbin/iptables-legacy || true
  docker exec $T iptables -C INPUT -p tcp --dport 22 -s 10.8.0.0/24 -j ACCEPT 2>/dev/null || \
    docker exec $T iptables -A INPUT -p tcp --dport 22 -s 10.8.0.0/24 -j ACCEPT
  docker exec $T iptables -C INPUT -p tcp --dport 22 -j DROP 2>/dev/null || \
    docker exec $T iptables -A INPUT -p tcp --dport 22 -j DROP
done

echo "=== Nagios (Apache + nagios4) ==="
docker exec monitoring-server service apache2 start || true
docker exec monitoring-server service nagios4 start || true

echo "=== OpenVPN server (recreate tun device if missing) ==="
docker exec vpn-gateway mkdir -p /dev/net
docker exec vpn-gateway mknod /dev/net/tun c 10 200 2>/dev/null || true
docker exec vpn-gateway chmod 600 /dev/net/tun
docker exec vpn-gateway pkill -9 openvpn 2>/dev/null || true
sleep 1
docker exec vpn-gateway openvpn --config /etc/openvpn/server.conf --daemon --log /var/log/openvpn.log

echo "=== Done. Verifying ==="
sleep 2
docker exec monitoring-server /usr/lib/nagios/plugins/check_nrpe -H 10.20.0.41 -c check_disk
docker exec monitoring-server /usr/lib/nagios/plugins/check_nrpe -H 10.20.0.42 -c check_disk
docker exec monitoring-server service nagios4 status
docker exec vpn-gateway ps aux | grep openvpn
