# OpenLDAP Setup

## Server
- Container: ldap-server (Ubuntu 22.04)
- Package: slapd + ldap-utils
- Base DN: dc=example,dc=local
- Admin DN: cn=admin,dc=example,dc=local

## Directory Structure
- ou=People,dc=example,dc=local
- ou=Groups,dc=example,dc=local

## Test Users (under ou=People)
- alice (uid=alice) - member of admins group
- bob (uid=bob) - member of developers group
- carol (uid=carol) - member of developers group

## Groups (under ou=Groups)
- admins (gidNumber 20001) - memberUid: alice
- developers (gidNumber 20002) - memberUid: bob, carol

## Notes
- slapd does not auto-start under Docker (no systemd); started manually via
  "service slapd start" after container boot.
- Root password was reset via ldapmodify with SASL EXTERNAL auth (ldapi socket)
  because the debconf-preseeded password during slapd install did not take
  effect as expected.
- Bootstrap LDIF: ldap/bootstrap/01-structure.ldif
- User passwords set individually via ldappasswd (not committed to git).

## Verification
ldapsearch against the base DN returned all 8 entries (2 OUs, 3 users,
2 groups) successfully - see terminal output for full result.
