#!/bin/bash
###############################################################################
# F5 BIG-IP — VS + Pool Export to Screen + CSV
# Base : K72255145 working script (your confirmed working version)
# Added: State, Availability, Reason, LB Method, Monitor,
#        Member counts (Up/Down/Enabled/Disabled), Screen display
#
# SAME cut commands as your working script:
#   destination  → cut -d" " -f6
#   pool         → cut -d" " -f6
#   address/IPs  → cut -d" " -f14  (confirmed working on your F5)
#
# USAGE:
#   chmod +x f5_vs_export.sh
#   ./f5_vs_export.sh
#   ./f5_vs_export.sh 2>/dev/null   # suppress progress messages
#
# OUTPUT:
#   Screen + /var/tmp/f5_vs_YYYYMMDD_HHMMSS.csv
###############################################################################

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="/var/tmp/f5_vs_${TIMESTAMP}.csv"

log() { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*" >&2; }

log "Starting F5 VS export..."
log "Output file: $OUTFILE"

# ─── Get all Virtual Servers (your exact working line) ───────────────────────
log "Getting virtual server list..."
VIRTUALS=$(tmsh -q -c "cd / ; list /ltm virtual recursive" \
    | grep "ltm virtual" \
    | awk -F' ' '{print "/"$3}')

VS_TOTAL=$(echo "$VIRTUALS" | grep -c "." || echo 0)
log "Found $VS_TOTAL virtual servers. Processing..."

# ─── Screen Header ────────────────────────────────────────────────────────────
SEP=$(printf '%.0s-' {1..160})
printf "\n%s\n" "$SEP"
printf "%-4s %-30s %-22s %-14s %-11s %-11s %-22s %5s %4s %4s %4s %4s  %s\n" \
    "No." "VS Name" "Destination" "Pool" \
    "State" "Avail" "LB Method" \
    "Total" "Up" "Down" "En" "Dis" "Member IPs"
printf "%s\n" "$SEP"

# ─── CSV Header ───────────────────────────────────────────────────────────────
echo "VS_Name,Partition,Destination,Pool,Admin_State,Availability,Reason,LB_Method,Monitor,Total_Members,Members_Up,Members_Down,Members_Enabled,Members_Disabled,Member_IPs" \
    > "$OUTFILE"

# ─── Main Loop (based on your working script) ─────────────────────────────────
COUNT=0
for VS in $VIRTUALS; do

    (( COUNT++ )) || true

    # Partition and short name
    PARTITION=$(echo "$VS" | cut -d/ -f2)
    VS_SHORT=$(echo  "$VS" | cut -d/ -f3-)

    # ── VS Config (your exact working commands) ───────────────────────────
    VS_CFG=$(tmsh list ltm virtual "$VS" 2>/dev/null)

    # Destination: your working cut -d" " -f6
    DEST=$(echo "$VS_CFG" | grep destination | cut -d" " -f6)

    # Pool: your working cut -d" " -f6
    # Using "^    pool" to avoid matching snat pool line
    POOL=$(echo "$VS_CFG" | grep "^    pool " | cut -d" " -f6)

    # ── VS Operational Status ─────────────────────────────────────────────
    VS_SHOW=$(tmsh show ltm virtual "$VS" 2>/dev/null)

    STATE=$(echo "$VS_SHOW" | awk -F: '/^[[:space:]]+State[[:space:]]*:/{
        gsub(/[[:space:]]/,"",$2); print $2; exit}')

    AVAIL=$(echo "$VS_SHOW" | awk -F: '/Availability[[:space:]]*:/{
        gsub(/[[:space:]]/,"",$2); print $2; exit}')

    REASON=$(echo "$VS_SHOW" | awk -F: '/Reason[[:space:]]*:/{
        sub(/^[[:space:]]*/,"",$2); print $2; exit}')

    # ── Pool Details ──────────────────────────────────────────────────────
    LB_METHOD=""; MONITOR=""; MEMBER_IPS=""
    TOTAL=0; UP=0; DN=0; EN=0; DIS=0

    if [ -n "$POOL" ]; then

        # Pool config — single tmsh call
        POOL_CFG=$(tmsh list ltm pool "$POOL" 2>/dev/null)

        # LB method
        LB_METHOD=$(echo "$POOL_CFG" | awk '/load-balancing-mode/{print $2; exit}')
        [ -z "$LB_METHOD" ] && LB_METHOD="round-robin"

        # Monitor
        MONITOR=$(echo "$POOL_CFG" | awk '$1=="monitor"{print $2; exit}')
        [ -z "$MONITOR" ] && MONITOR="none"

        # Member IPs — YOUR EXACT WORKING COMMAND preserved
        # cut -d" " -f14 works on this F5 (12 leading spaces before "address")
        MEMBER_IPS=$(echo "$POOL_CFG" \
            | grep address \
            | cut -d" " -f14 \
            | tr '\n' ' ' \
            | sed 's/ $//')

        # Total member count
        TOTAL=$(echo "$POOL_CFG" | grep -c "address" || echo 0)

        # Member ports alongside IPs (paired from member name lines)
        # Extract port from "/Partition/node:PORT {" lines
        PORTS=$(echo "$POOL_CFG" \
            | grep -oP '/[^ ]+:[0-9]+(?= \{)' \
            | grep -oP ':[0-9]+' \
            | tr -d ':' \
            | tr '\n' ' ')

        # Combine IP:port pairs for display
        if [ -n "$MEMBER_IPS" ]; then
            IPS_ARRAY=($MEMBER_IPS)
            PORTS_ARRAY=($PORTS)
            PAIRED=""
            for i in "${!IPS_ARRAY[@]}"; do
                PORT="${PORTS_ARRAY[$i]:-?}"
                ENTRY="${IPS_ARRAY[$i]}:${PORT}"
                PAIRED="${PAIRED:+$PAIRED  }${ENTRY}"
            done
            MEMBER_IPS="$PAIRED"
        fi

        # ── Pool Member Operational Status (up/down/enabled/disabled) ────
        POOL_SHOW=$(tmsh show ltm pool "$POOL" members 2>/dev/null)

        UP=$(echo "$POOL_SHOW" | awk '
            /Availability[[:space:]]*:/{
                val=$NF
                if (val=="available") c++
            } END{print c+0}')

        DN=$(echo "$POOL_SHOW" | awk '
            /Availability[[:space:]]*:/{
                val=$NF
                if (val~/offline|unavailable/) c++
            } END{print c+0}')

        EN=$(echo "$POOL_SHOW" | awk '
            /[[:space:]]State[[:space:]]*:/{
                val=$NF
                if (val=="enabled") c++
            } END{print c+0}')

        DIS=$(echo "$POOL_SHOW" | awk '
            /[[:space:]]State[[:space:]]*:/{
                val=$NF
                if (val!="enabled") c++
            } END{print c+0}')
    fi

    # ── Screen Output (real-time, one row per VS) ─────────────────────────
    printf "%-4s %-30s %-22s %-14s %-11s %-11s %-22s %5s %4s %4s %4s %4s  %s\n" \
        "$COUNT" \
        "${VS_SHORT:0:29}" \
        "${DEST:0:21}" \
        "${POOL##*/}" \
        "${STATE:0:10}" \
        "${AVAIL:0:10}" \
        "${LB_METHOD:0:21}" \
        "$TOTAL" "$UP" "$DN" "$EN" "$DIS" \
        "$MEMBER_IPS"

    # ── CSV Output ────────────────────────────────────────────────────────
    # Wrap fields in quotes to handle commas in reason strings
    printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
        "$VS_SHORT"  "$PARTITION"  "$DEST"      "$POOL" \
        "$STATE"     "$AVAIL"      "$REASON" \
        "$LB_METHOD" "$MONITOR" \
        "$TOTAL"     "$UP"         "$DN" \
        "$EN"        "$DIS"        "$MEMBER_IPS" \
        >> "$OUTFILE"

done

printf "%s\n\n" "$SEP"

# ─── Summary ─────────────────────────────────────────────────────────────────
log "================================================"
log "  Total VS exported : $COUNT"
log "  CSV saved to      : $OUTFILE"
log "================================================"
log ""
log "To view file (no SCP needed):"
log "  cat $OUTFILE"
log ""
log "To download via REST API:"
log "  cp $OUTFILE /var/config/rest/downloads/"
log "  curl -sku admin:PASS https://<F5-IP>/mgmt/shared/file-transfer/downloads/f5_vs_${TIMESTAMP}.csv -o f5_export.csv"
