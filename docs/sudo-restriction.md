# Group-based sudo restriction via LDAP

## Rule
`/etc/sudoers.d/ldap-admins` on target1:

```
%admins ALL=(ALL:ALL) ALL
```

This grants full sudo to any user whose group resolves (via sssd from LDAP) to the `admins` posixGroup (gidNumber 20001).

## Test 1: alice (member of admins)

```
$ sshpass -p "Alice@123" ssh alice@10.20.0.41 "echo 'Alice@123' | sudo -S whoami"
root
```

**Result:** SUCCESS — alice can sudo.

## Test 2: bob (member of developers, not admins)

```
$ sshpass -p "Bob@123" ssh bob@10.20.0.41 "whoami && id"
bob
uid=10002(bob) gid=10002 groups=10002,20002(developers)

$ sshpass -p "Bob@123" ssh bob@10.20.0.41 "echo 'Bob@123' | sudo -S whoami"
[sudo] password for bob: bob is not in the sudoers file. This incident will be reported.
```

**Result:** bob can log in via SSH (LDAP authentication succeeds) but cannot sudo, since he is only in the `developers` LDAP group, not `admins`.

## Conclusion
LDAP group membership correctly and dynamically controls sudo access on the target server, without any local `/etc/sudoers` edits per user — exactly the enterprise requirement: "only users in an admins LDAP group can sudo."
