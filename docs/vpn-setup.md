# OpenVPN Setup and Access Proof

## Architecture
- vpn-gateway runs the OpenVPN server (port 1194/udp) on the `dmz` network (10.10.0.10), and is the only container bridging `dmz` and `internal`.
- PKI built with easy-rsa: CA, server cert, and one client cert per user (alice, bob) - not a shared certificate.
- Server pushes route `10.20.0.0/24` to connected clients, so VPN clients can reach the target servers' private subnet.
- Firewall on target1/target2: `iptables` only ACCEPTs SSH (port 22) from `10.8.0.0/24` (the VPN client subnet), DROPs everything else.

## Certificate generation (per user)
```
./easyrsa gen-req alice nopass   # (with EASYRSA_REQ_CN=alice to avoid default "ChangeMe" CN)
./easyrsa sign-req client alice
./easyrsa gen-req bob nopass
./easyrsa sign-req client bob
```
Each user's `.ovpn` client config bundles their own cert/key, distinct from every other user's.

## Test 1: SSH unreachable without VPN

```
$ timeout 5 sshpass -p "Alice@123" ssh -o ConnectTimeout=3 alice@10.20.0.41 "whoami"
ssh: connect to host 10.20.0.41 port 22: Connection timed out
```

## Test 2: Connect to VPN

```
$ sudo openvpn --config vpn/clients/alice.ovpn --daemon --log /tmp/openvpn-client.log
...
Initialization Sequence Completed
```
Client receives a `tun0` interface (10.8.0.2/24) and a pushed route to `10.20.0.0/24` via the VPN gateway.

## Test 3: SSH reachable after VPN connects

```
$ sshpass -p "Alice@123" ssh alice@10.20.0.41 "whoami && id && hostname"
alice
uid=10001(alice) gid=10001 groups=10001,20001(admins)
target1
```

## Lab-environment caveat
This is a single-host Docker lab, so the host machine already has a direct route to the `internal` Docker bridge network, which would otherwise bypass the VPN tunnel entirely (unlike a real multi-machine deployment, where the VPN would be the only path). To make the client route to the target server through the VPN tunnel as it would in production, a more specific host route was added on the client pointing at the tun0 interface:
```
sudo ip route add 10.20.0.41/32 via 10.8.0.1 dev tun0
```
In a real deployment (separate physical/virtual machines, no shared bridge), this step is unnecessary - the VPN would be the only path to the target servers by construction, which is exactly the property this lab is simulating.

## Conclusion
- SSH is unreachable from outside the VPN (firewall-enforced).
- SSH becomes reachable once connected via a per-user OpenVPN client certificate.
- Combined with the earlier NAT/network-isolation work, this fully satisfies: "no server is directly reachable from the internet" and "only accept SSH from the VPN's internal subnet."
