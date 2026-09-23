# LDAP-based SSH Authentication (target1)

## Components
- sssd + sssd-ldap + libnss-sss + libpam-sss (identity + auth broker)
- nsswitch.conf updated: passwd/group/shadow use "files sss"
- PAM common-session: pam_mkhomedir enabled (auto-create home dir on first login)
- sshd running normally, PasswordAuthentication left at default (yes)

## sssd.conf key settings (/etc/sssd/sssd.conf)
- id_provider = ldap, auth_provider = ldap
- ldap_uri = ldap://10.20.0.20 (ldap-server's internal IP)
- ldap_search_base = dc=example,dc=local
- ldap_tls_reqcert = never
- ldap_id_use_start_tls = false
- ldap_auth_disable_tls_never_use_in_production = true

## Key issue and fix
sssd attempts StartTLS during the AUTHENTICATE phase by default, separately
from the id-lookup phase, even with ldap_id_use_start_tls=false. Since the
lab's OpenLDAP server does not support StartTLS (plain LDAP only, as this is
an internal-only lab network already isolated by Docker networking + a
planned VPN layer), authentication failed with:
  "START TLS result: Protocol error(2), unsupported extended operation"
  "Going offline"
Fix: explicitly set ldap_auth_disable_tls_never_use_in_production = true
(lab-only; would not be acceptable in a real production deployment, where
LDAPS or StartTLS with valid certs should be used instead).

## Other gotchas hit during setup
- slapd/sssd/sshd do not auto-start under Docker (no systemd) — started
  manually with `service` or by launching binaries directly.
- sssd can leave zombie/defunct child processes when killed via docker exec;
  a full `docker restart <container>` reliably clears this.
- sssd logs did not appear even with logger=files configured in a couple of
  runs due to stale PID files; deleting /run/sssd.pid before restart fixed it.

## Verification
$ sshpass -p "Alice@123" ssh alice@10.20.0.41 "whoami && id && pwd"
alice
uid=10001(alice) gid=10001 groups=10001,20001(admins)
/home/alice

Alice, who exists only in LDAP (not in target1's local /etc/passwd), was
able to SSH in using her LDAP password, and her group membership (admins)
was correctly resolved.
