#!/bin/bash
set -e
echo "=========================================="
echo "FULL REBUILD - this will take 15-20 minutes"
echo "=========================================="

cd ~/enterprise-infra-lab

# ---------- 1. Routes + DNS ----------
echo "=== [1/8] Routes + DNS ==="
T1PID=$(docker inspect -f '{{.State.Pid}}' target1)
T2PID=$(docker inspect -f '{{.State.Pid}}' target2)
MPID=$(docker inspect -f '{{.State.Pid}}' monitoring-server)
LPID=$(docker inspect -f '{{.State.Pid}}' ldap-server)
sudo nsenter -t $T1PID -n ip route add default via 10.20.0.10 2>/dev/null || true
sudo nsenter -t $T2PID -n ip route add default via 10.20.0.10 2>/dev/null || true
sudo nsenter -t $MPID  -n ip route add default via 10.20.0.10 2>/dev/null || true
sudo nsenter -t $LPID  -n ip route add default via 10.20.0.10 2>/dev/null || true
for T in target1 target2 monitoring-server ldap-server; do
  docker exec $T sh -c "echo 'nameserver 1.1.1.1' > /etc/resolv.conf"
done

# ---------- 2. vpn-gateway: NAT + tun + OpenVPN ----------
echo "=== [2/8] vpn-gateway: NAT, iptables, OpenVPN ==="
docker exec vpn-gateway apt-get update
docker exec vpn-gateway apt-get install -y iptables openvpn easy-rsa iproute2
docker exec vpn-gateway iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE

docker exec vpn-gateway bash -c "cp -r /usr/share/easy-rsa /etc/openvpn/easy-rsa" 2>/dev/null || true
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && ./easyrsa init-pki"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 ./easyrsa build-ca nopass"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 ./easyrsa gen-req server nopass"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 ./easyrsa sign-req server server"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && ./easyrsa gen-dh"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && openvpn --genkey secret pki/ta.key"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 EASYRSA_REQ_CN=alice ./easyrsa gen-req alice nopass"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 ./easyrsa sign-req client alice"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 EASYRSA_REQ_CN=bob ./easyrsa gen-req bob nopass"
docker exec vpn-gateway bash -c "cd /etc/openvpn/easy-rsa && EASYRSA_BATCH=1 ./easyrsa sign-req client bob"

cat > /tmp/server.conf << 'EOF'
port 1194
proto udp
dev tun
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem
tls-auth /etc/openvpn/easy-rsa/pki/ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
push "route 10.20.0.0 255.255.255.0"
keepalive 10 120
cipher AES-256-CBC
persist-key
persist-tun
status /var/log/openvpn-status.log
verb 3
EOF
docker cp /tmp/server.conf vpn-gateway:/etc/openvpn/server.conf

docker exec vpn-gateway mkdir -p /dev/net
docker exec vpn-gateway mknod /dev/net/tun c 10 200 2>/dev/null || true
docker exec vpn-gateway chmod 600 /dev/net/tun
docker exec vpn-gateway openvpn --config /etc/openvpn/server.conf --daemon --log /var/log/openvpn.log

docker exec vpn-gateway bash -c "cat /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/easy-rsa/pki/issued/alice.crt /etc/openvpn/easy-rsa/pki/private/alice.key /etc/openvpn/easy-rsa/pki/ta.key" > /tmp/alice_parts.txt
docker cp vpn-gateway:/etc/openvpn/easy-rsa/pki/ca.crt /tmp/ca.crt
docker cp vpn-gateway:/etc/openvpn/easy-rsa/pki/issued/alice.crt /tmp/alice.crt
docker cp vpn-gateway:/etc/openvpn/easy-rsa/pki/private/alice.key /tmp/alice.key
docker cp vpn-gateway:/etc/openvpn/easy-rsa/pki/ta.key /tmp/ta.key
{
  echo "client"
  echo "dev tun"
  echo "proto udp"
  echo "remote 10.10.0.10 1194"
  echo "resolv-retry infinite"
  echo "nobind"
  echo "persist-key"
  echo "persist-tun"
  echo "remote-cert-tls server"
  echo "cipher AES-256-CBC"
  echo "verb 3"
  echo "<ca>"; cat /tmp/ca.crt; echo "</ca>"
  echo "<cert>"; openssl x509 -in /tmp/alice.crt; echo "</cert>"
  echo "<key>"; cat /tmp/alice.key; echo "</key>"
  echo "<tls-auth>"; cat /tmp/ta.key; echo "</tls-auth>"
  echo "key-direction 1"
} > ~/enterprise-infra-lab/vpn/clients/alice.ovpn

# ---------- 3. LDAP ----------
echo "=== [3/8] LDAP ==="
docker exec ldap-server bash -c "
debconf-set-selections <<< 'slapd slapd/root_password password Admin@123'
debconf-set-selections <<< 'slapd slapd/root_password_again password Admin@123'
debconf-set-selections <<< 'slapd slapd/domain string example.local'
debconf-set-selections <<< 'slapd shared/organization string ExampleOrg'
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y slapd ldap-utils
"
docker exec ldap-server service slapd start
docker exec ldap-server slappasswd -s "Admin@123" > /tmp/pw_hash.txt
HASH=$(cat /tmp/pw_hash.txt)
cat > /tmp/rootpw.ldif << EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $HASH
EOF
docker cp /tmp/rootpw.ldif ldap-server:/tmp/rootpw.ldif
docker exec ldap-server ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/rootpw.ldif

docker cp ~/enterprise-infra-lab/ldap/bootstrap/01-structure.ldif ldap-server:/tmp/01-structure.ldif
docker exec ldap-server ldapadd -x -D "cn=admin,dc=example,dc=local" -w Admin@123 -f /tmp/01-structure.ldif || true
docker exec ldap-server ldappasswd -x -D "cn=admin,dc=example,dc=local" -w Admin@123 -s "Alice@123" "uid=alice,ou=People,dc=example,dc=local"
docker exec ldap-server ldappasswd -x -D "cn=admin,dc=example,dc=local" -w Admin@123 -s "Bob@123" "uid=bob,ou=People,dc=example,dc=local"
docker exec ldap-server ldappasswd -x -D "cn=admin,dc=example,dc=local" -w Admin@123 -s "Carol@123" "uid=carol,ou=People,dc=example,dc=local"

# ---------- 4. Targets: sssd, sshd, sudoers, NRPE, zabbix-agent, iptables ----------
echo "=== [4/8] target1 & target2 ==="
for T in target1 target2; do
  docker exec $T bash -c "DEBIAN_FRONTEND=noninteractive apt-get update"
  docker exec $T bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server sssd sssd-ldap libnss-sss libpam-sss ldap-utils sudo iptables curl nagios-nrpe-server monitoring-plugins zabbix-agent"

  docker exec $T bash -c "cat > /etc/sssd/sssd.conf << 'EOF'
[sssd]
logger = files
config_file_version = 2
services = nss, pam
domains = example.local

[domain/example.local]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://10.20.0.20
ldap_search_base = dc=example,dc=local
ldap_default_bind_dn = cn=admin,dc=example,dc=local
ldap_default_authtok = Admin@123
cache_credentials = true
enumerate = true
ldap_tls_reqcert = never
ldap_id_use_start_tls = false
ldap_auth_disable_tls_never_use_in_production = true
EOF"
  docker exec $T chmod 600 /etc/sssd/sssd.conf
  docker exec $T sed -i 's/^passwd:.*/passwd:         files sss/' /etc/nsswitch.conf
  docker exec $T sed -i 's/^group:.*/group:          files sss/' /etc/nsswitch.conf
  docker exec $T sed -i 's/^shadow:.*/shadow:         files sss/' /etc/nsswitch.conf
  docker exec $T bash -c "grep -q pam_mkhomedir /etc/pam.d/common-session || echo 'session required pam_mkhomedir.so skel=/etc/skel umask=0022' >> /etc/pam.d/common-session"
  docker exec $T bash -c "echo '%admins ALL=(ALL:ALL) ALL' > /etc/sudoers.d/ldap-admins"
  docker exec $T chmod 440 /etc/sudoers.d/ldap-admins

  docker exec $T sssd -D
  docker exec $T service ssh start

  docker exec $T sed -i 's/^allowed_hosts=.*/allowed_hosts=127.0.0.1,10.20.0.30/' /etc/nagios/nrpe.cfg
  docker exec $T bash -c "grep -q check_disk /etc/nagios/nrpe.cfg || cat >> /etc/nagios/nrpe.cfg << 'EOF'

command[check_disk]=/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /
command[check_load]=/usr/lib/nagios/plugins/check_load -w 5,4,3 -c 10,8,6
command[check_total_procs]=/usr/lib/nagios/plugins/check_procs -w 200 -c 250
EOF"
  docker exec $T /usr/sbin/nrpe -c /etc/nagios/nrpe.cfg -d

  docker exec $T sed -i "s/^# Hostname=.*/Hostname=$T/" /etc/zabbix/zabbix_agentd.conf
  docker exec $T sed -i 's/^Server=127.0.0.1/Server=10.20.0.30/' /etc/zabbix/zabbix_agentd.conf
  docker exec $T sed -i 's/^ServerActive=127.0.0.1/ServerActive=10.20.0.30/' /etc/zabbix/zabbix_agentd.conf
  docker exec $T service zabbix-agent start

  docker exec $T update-alternatives --set iptables /usr/sbin/iptables-legacy
  docker exec $T iptables -A INPUT -p tcp --dport 22 -s 10.8.0.0/24 -j ACCEPT
  docker exec $T iptables -A INPUT -p tcp --dport 22 -j DROP
done

# ---------- 5. Nagios on monitoring-server ----------
echo "=== [5/8] Nagios ==="
docker exec monitoring-server apt-get update
docker exec monitoring-server bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y nagios4 nagios-plugins-contrib monitoring-plugins nagios-nrpe-plugin curl"
docker exec monitoring-server bash -c "htpasswd -b -c /etc/nagios4/htdigest.users nagiosadmin Admin@123"
docker exec monitoring-server a2enmod cgi
docker exec monitoring-server rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

cp ~/enterprise-infra-lab/docs/../nagios/README.md /tmp/dummy 2>/dev/null || true
cat > /tmp/targets.cfg << 'EOF'
define host {
    use                     linux-server
    host_name               target1
    alias                   Target Server 1
    address                 10.20.0.41
    max_check_attempts      3
    check_period            24x7
    notification_interval   30
    notification_period     24x7
}
define host {
    use                     linux-server
    host_name               target2
    alias                   Target Server 2
    address                 10.20.0.42
    max_check_attempts      3
    check_period            24x7
    notification_interval   30
    notification_period     24x7
}
define service {
    use                     generic-service
    host_name               target1,target2
    service_description     PING
    check_command           check_ping!100.0,20%!500.0,60%
}
define service {
    use                     generic-service
    host_name               target1,target2
    service_description     SSH
    check_command           check_ssh
}
define service {
    use                     generic-service
    host_name               target1,target2
    service_description     Disk Space
    check_command           check_nrpe_1arg!check_disk
}
define service {
    use                     generic-service
    host_name               target1,target2
    service_description     CPU Load
    check_command           check_nrpe_1arg!check_load
}
EOF
docker cp /tmp/targets.cfg monitoring-server:/etc/nagios4/conf.d/targets.cfg

cat > /tmp/nrpe-command.cfg << 'EOF'
define command {
    command_name    check_nrpe_1arg
    command_line    /usr/lib/nagios/plugins/check_nrpe -H $HOSTADDRESS$ -c $ARG1$
}
EOF
docker cp /tmp/nrpe-command.cfg monitoring-server:/etc/nagios4/conf.d/nrpe-command.cfg

docker exec monitoring-server service apache2 start
docker exec monitoring-server service nagios4 start

# ---------- 6. MariaDB + Zabbix server ----------
echo "=== [6/8] MariaDB + Zabbix ==="
docker exec monitoring-server bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server"
docker exec monitoring-server service mariadb start
sleep 3

docker exec monitoring-server curl -o /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb
docker exec monitoring-server dpkg -i /tmp/zabbix-release.deb
docker exec monitoring-server apt-get update
docker exec monitoring-server bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent"

docker exec monitoring-server mysql -e "CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
docker exec monitoring-server mysql -e "CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'Zabbix@123';"
docker exec monitoring-server mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
docker exec monitoring-server mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"

TABLECOUNT=$(docker exec monitoring-server mysql -u zabbix -pZabbix@123 zabbix -e "SHOW TABLES;" 2>/dev/null | wc -l)
if [ "$TABLECOUNT" -lt 5 ]; then
  docker exec monitoring-server bash -c "zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -u zabbix -pZabbix@123 zabbix"
fi

docker exec monitoring-server sed -i 's/^# DBPassword=.*/DBPassword=Zabbix@123/' /etc/zabbix/zabbix_server.conf
docker exec monitoring-server chmod 755 /var/run/mysqld

docker exec monitoring-server apt-get install -y locales
docker exec monitoring-server locale-gen en_US.UTF-8
docker exec monitoring-server update-locale LANG=en_US.UTF-8

docker exec monitoring-server sed -i 's/#        listen          8080;/        listen          8080;/' /etc/zabbix/nginx.conf
docker exec monitoring-server sed -i 's/#        server_name     example.com;/        server_name     _;/' /etc/zabbix/nginx.conf

docker exec monitoring-server service php8.1-fpm start
docker exec monitoring-server service nginx start
docker exec monitoring-server service zabbix-server start
docker exec monitoring-server service zabbix-agent start

# ---------- 7. Verify ----------
echo "=== [7/8] Verifying ==="
sleep 3
docker exec monitoring-server /usr/lib/nagios/plugins/check_nrpe -H 10.20.0.41 -c check_disk
docker exec monitoring-server /usr/lib/nagios/plugins/check_nrpe -H 10.20.0.42 -c check_disk
docker exec monitoring-server service nagios4 status
docker exec monitoring-server service zabbix-server status
docker exec vpn-gateway ps aux | grep openvpn

echo "=== [8/8] DONE ==="
echo "Nagios: http://10.20.0.30/nagios4/  (nagiosadmin / Admin@123)"
echo "Zabbix: http://10.20.0.30:8080/     (Admin / zabbix)"
echo "NOTE: Zabbix web setup wizard (setup.php) needs to be re-run in browser since it's stored in DB already, should skip automatically if DB has data."
