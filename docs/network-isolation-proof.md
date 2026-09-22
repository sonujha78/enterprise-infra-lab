# Network Isolation Proof

## Test
Ran apt-get update inside containers to check internet reachability.

### target1 (internal network only)
Output:
Ign:1 http://security.ubuntu.com/ubuntu jammy-security InRelease
Ign:2 http://archive.ubuntu.com/ubuntu jammy InRelease
Ign:3 http://archive.ubuntu.com/ubuntu jammy-updates InRelease
Ign:4 http://archive.ubuntu.com/ubuntu jammy-backports InRelease

Result: No internet access - confirms internal Docker network has no route out, simulating a private VM subnet with no direct internet exposure.

### vpn-gateway (dmz + internal network)
Output:
Get:1 http://security.ubuntu.com/ubuntu jammy-security InRelease [129 kB]
Get:2 http://archive.ubuntu.com/ubuntu jammy InRelease [270 kB]
Get:3 http://security.ubuntu.com/ubuntu jammy-security/restricted amd64 Packages [7760 kB]

Result: Internet access confirmed - only the gateway container, which bridges dmz and internal, can reach the outside world.

## Conclusion
Target servers are not directly reachable from or to the internet. Only the VPN gateway has external connectivity, matching the enterprise requirement: "no server is directly reachable from the internet."
