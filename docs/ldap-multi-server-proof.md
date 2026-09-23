# Proof: One LDAP identity works across multiple servers

This is the core LDAP requirement: a user created once in LDAP can SSH into any target server, with no separate local account needed on each machine.

## Setup
- target1 and target2 both configured as independent sssd/LDAP clients, pointing at the same ldap-server (10.20.0.20).
- Neither target has alice, bob, or carol in its local /etc/passwd - both resolve these users purely via LDAP.

## Test: alice logs into both servers with the same password

target1:
```
$ sshpass -p "Alice@123" ssh alice@10.20.0.41 "whoami && id"
alice
uid=10001(alice) gid=10001 groups=10001,20001(admins)
```

target2:
```
$ sshpass -p "Alice@123" ssh alice@10.20.0.42 "whoami && id && echo 'Alice@123' | sudo -S whoami"
alice
uid=10001(alice) gid=10001 groups=10001,20001(admins)
[sudo] password for alice: root
```

## Test: carol logs into target2

```
$ sshpass -p "Carol@123" ssh carol@10.20.0.42 "whoami && id"
carol
uid=10003(carol) gid=10003 groups=10003,20002(developers)
```

## Conclusion
- Same UID, GID, and group membership resolved identically on both target1 and target2, sourced from the single LDAP directory.
- alice's admins group membership grants sudo on both servers, using the per-server /etc/sudoers.d/ldap-admins rule (%admins ALL=(ALL:ALL) ALL) applied identically on each target.
- No per-server user provisioning was required - centralized authentication achieved.
