#!/bin/bash

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# muxpi.sh by ewald@jeitler.cc 2026 https://www.jeitler.guru
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# codename: muxpi  (Measurement Utility eXtreme for raspberry P) 
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# I hope you enjoy measuring, logging, and experimenting with this script. – Ewald
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# When I wrote this code, only god and
# I knew how it worked.
# Now, only god knows it!
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

DEFAULTCONFIGFILE="muxpi.conf"
SCRIPTNAME="muxpi.sh" 
VERSION="0.45"
LOGDIR="./muxpi-logs"
PREAMBLELOGFILENAME="muxpi"

# --- create uniq tmux session id  ---------------------------------------------
generate_free_session() {
    while true; do
        rand=$(( (RANDOM % 999) + 1 ))
        session="MUXPI${rand}"
        if ! tmux has-session -t "$session" 2>/dev/null; then
            echo "$session"
            return 0
        fi
    done
}

# --- line parse  --------------------------------------------------------------
parse_line() {
    line="$1"
    lineno="$2"
    is_first="$3"

    PORT=""
    ROLE=""
    FIRSTCMD=""

    # firstcmd
    if [ "$is_first" -eq 1 ]; then
        FIRSTCMD=1
    else
        FIRSTCMD=0
    fi

    case "$line" in
        *iperf*|*iperf3*)
            printf "%s" "$line" | grep -q " -s" && ROLE="server"
            printf "%s" "$line" | grep -q " -c" && ROLE="client"

            PORT=$(printf "%s" "$line" | awk '
                {
                    for (i=1; i<=NF; i++) {
                        if ($i == "-p") {
                            print $(i+1)
                            exit
                        }
                    }
                }
            ')

            [ -z "$PORT" ] && PORT=5201
            ;;
        *)
            PORT="$lineno"
            ROLE="ocmd"
            ;;
    esac
}
# --- check tmux  --------------------------------------------------------------
check_tmux() {
    if command -v tmux >/dev/null 2>&1; then
        return 0
    fi
    printf "\nERROR: tmux is not installed.\n" >&2
    printf "Please install tmux first. For example on Debian:\n" >&2
    printf "    sudo apt install tmux\n\n" >&2
    exit 1
}

# --- determine how to run the cmd with unbuffered output -----------------------
detect_run_cmd() {
    local cmd="$1"

    # macos: stdbuf/gstdbuf unusable → use script
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "script -q /dev/null $cmd"
        return
    fi

    # linux: use stdbuf if available
    if command -v stdbuf >/dev/null 2>&1; then
        echo "stdbuf -oL -eL $cmd"
        return
    fi

    # fallback: no buffering tool
    echo "$cmd"
}

# --- main ---------------------------------------------------------------------

check_tmux

# --- parse options ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|-H|--help|--Help|-help|-Help)
            echo "Usage: $SCRIPTNAME [-c configfilename]"
            echo "       $SCRIPTNAME [-h] [-v|--version]" 
            exit 1 
            ;;
        -v|-V|--version|--Version)
            echo "$SCRIPTNAME version $VERSION - https://www.jeitler.guru"
            exit 1 
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- no config file provided --------------------------------------------------
# CONFIG_FILE=""
if [[ -z "$CONFIG_FILE" ]]; then
    if [[ ! -f "$DEFAULTCONFIGFILE" ]]; then
        echo "Creating example configuration file: $DEFAULTCONFIGFILE"
        sleep 2 
        cat > "$DEFAULTCONFIGFILE" <<'EOF'
# -----------------------------------------------------------------------------
# Example Configuration file for muxperf.sh, defining one command per line to be
# executed in parallel tmux panes for network-performance testing,
# with all output timestamped and logged.
# -----------------------------------------------------------------------------
# Created by Ewald Jeitler — https://www.jeitler.guru
# -----------------------------------------------------------------------------

# LOCAL TEST - IPERF3 
iperf3  -s -p 5201 -i 1 
iperf3  -c 127.0.0.1 -p 5201 

iperf3  -s -p 5202 -i 1 
iperf3  -c 127.0.0.1 -p 5202 

# LOCAL TEST - MAU SEND / MAU RECV 
mau-send -p 5055 --pps 10 -d 239.1.1.10 --sync-port 5066 --dscp 16
mau-recv -p 5055 -g 239.1.1.10 -sc 1  --sender-ip 127.0.0.1 --sync-port 5066 
mau-recv -p 5055 -g 239.1.1.10 --sender-ip 127.0.0.1 --sync-port 5066 

## Examples of possible commands – there are many more possibilities – let your imagination run wild 

# -- IPERF SERVER --
# iperf3 -s -p 5201                                         | Server listen on port 5201 
# iperf3 -s -p 5202                                         | Server listen on port 5202 
# iperf3 -s -p 5203 -i 10                                   | Server listen on port 5202 update interval 10 seconds 

# -- IPERF CLIENT -- 
# iperf3 -c <IP> -p 5201 -t 60 -S 0 -P 2                    | Two TCP stream to <IP> port 5201 / 60 secondes / DSCP: AF11
# iperf3 -c <IP> -p 5202 -t 60 -S 40                        | One TCP stream to <IP> port 5202 / 60 secondes / DSCP: AF11
# iperf3 -c <IP> -p 5203 -t 60 -S 88                        | One TCP stream to <IP> port 5202 / 60 secondes / DSCP: AF23

# IPERF NO DEED FOR A PEER - GENERATE UDP TRAFFIC  
# iperf -c <IP> -u -b 10m -t 60 -S 0                        | UDP stream to <IP> 10 Mbit/s 60 seconds DSCP=BE    
# iperf -c <IP> -u -b 10m -t 60 -S 64                       | UDP stream to <IP> 10 Mbit/s 60 seconds DSCP=CS2 
# iperf -c <IP> -u -b 10m -t 60 -S 184                      | UDP stream to <IP> 10 Mbit/s 60 seconds DSCP=EF 

# -- PING -- 
# ping -c 10 <IP>                                           | ICMP ECHO to <IP> 10 pakets 
# ping -T 184 -c 30 -s 700 <IP>                             | ICMP ECHO to <IP> 30 packets DSCP=EF size 700Byte  (Debian)
# ping -T 88 -c 30 -s 100 <IP>                              | ICMP ECHO to <IP> 30 packets DSCP=AF23 size 100Byte  (Debian)
# ping -z 184 -c 30 -s 700  <IP>                            | ICMP ECHO to <IP> 15 packets DSCP=EF size 700Byte  (OSX)
# ping -z 80 -c 30 -s 700  <IP>                             | ICMP ECHO to <IP> 15 packets DSCP=CS4 size 700Byte  (OSX)

# fping -b 450 -e -l -O 184 -o <IP>                         | FPING to <IP> loop DSCP=EF siz 450Byte 

# ┌───────────────────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────┐
# │  QOS CHEATSHEET                                                       |                          TOS                          │
# ├───────────────────────────────────────────────────────────────────────┼──────────────────────────────────┬──────┬─────────────┤
# │                                                                       │                DSCP              │      |             │
# ├───────────────────────────────────────────────────────────────────────┼────────────────────┬──────┬──────┼──────┤     ECN     │
# │                                                                       │       IPP / COS    │  DP  │  DP  │      │             │
# ├────────────────────────┬─────────┬──────┬──────┬─────┬─────────┬──────┼──────┬──────┬──────┼──────┼──────┼──────┼──────┬──────┤
# │ Application            │ CoS=IPP │  AF  │ DSCP │ ToS │ ToS HEX │  DP  │ Bit0 │ Bit1 │ Bit2 │ Bit3 │ Bit4 │ Bit5 │ Bit6 │ Bit7 │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Best Effort            │    0    │   BE │  0   │  0  │    0    │      │   0  │   0  │   0  │   0  │   0  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Scavenger (Low-Prio)   │    1    │  CS1 │  8   │  32 │    20   │      │   0  │   0  │   1  │   0  │   0  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ High-Throughput Data   │    1    │ AF11 │  10  │  40 │    28   │ Low  │   0  │   0  │   1  │   0  │   1  │   0  │   0  │   0  │
# │ (Transactional)        │    1    │ AF12 │  12  │  48 │    30   │ Med  │   0  │   0  │   1  │   1  │   0  │   0  │   0  │   0  │
# │                        │    1    │ AF13 │  14  │  56 │    38   │ High │   0  │   0  │   1  │   1  │   1  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ OAM / Monitoring       │    2    │  CS2 │  16  │  64 │    40   │      │   0  │   1  │   0  │   0  │   0  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Mission Critical       │    2    │ AF21 │  18  │  72 │    48   │ Low  │   0  │   1  │   0  │   0  │   1  │   0  │   0  │   0  │
# │ (Low-Latency)          │    2    │ AF22 │  20  │  80 │    50   │ Med  │   0  │   1  │   0  │   1  │   0  │   0  │   0  │   0  │
# │                        │    2    │ AF23 │  22  │  88 │    58   │ High │   0  │   1  │   0  │   1  │   1  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Call Control/Auth/ AAA │    3    │  CS3 │  24  │  96 │    60   │      │   0  │   1  │   1  │   0  │   0  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Video Streaming        │    3    │ AF31 │  26  │ 104 │    68   │ Low  │   0  │   1  │   1  │   0  │   1  │   0  │   0  │   0  │
# │                        │    3    │ AF32 │  28  │ 112 │    70   │ Med  │   0  │   1  │   1  │   1  │   0  │   0  │   0  │   0  │
# │                        │    3    │ AF33 │  30  │ 120 │    78   │ High │   0  │   1  │   1  │   1  │   1  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Real-Time Interactive  │    4    │  CS4 │  32  │ 128 │    80   │      │   1  │   0  │   0  │   0  │   0  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Video Conferencing     │    4    │ AF41 │  34  │ 136 │    88   │ Low  │   1  │   0  │   0  │   1  │   0  │   0  │   0  │   0  │
# │                        │    4    │ AF42 │  36  │ 144 │    90   │ Med  │   1  │   0  │   0  │   1  │   0  │   0  │   0  │   0  │
# │                        │    4    │ AF43 │  38  │ 152 │    98   │ High │   1  │   0  │   0  │   1  │   1  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Signaling (SIP/SCCP)   │    5    │  CS5 │  40  │ 160 │    A0   │      │   1  │   0  │   1  │   0  │   0  │   0  │   0  │   0  │
# │ Telephony (VoIP)       |    5    │   EF │  46  │ 184 │    B8   │      │   1  │   0  │   1  │   1  │   0  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Routing/Control        │    6    │  CS6 │  48  │ 192 │    C0   │      │   1  │   1  │   0  │   0  │   0  │   0  │   0  │   0  │
# ├────────────────────────┼─────────┼──────┼──────┼─────┼─────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤
# │ Provider Control       │    7    │  CS7 │  56  │ 224 │    E0   │      │   1  │   1  │   1  │   0  │   0  │   0  │   0  │   0  │
# ├────────────────────────┴─────────┴──────┴──────┴─────┼─────────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┤
# │  DSCP = Differentiated Services Code Point (L3)      |  AF = Assured Forwarding                                               |
# │  ToS = Type of Service  (L3/)                        |  CS = Class Selector                                                   |
# │  IPP = IP Precedence    (L3)                         |  DP = Drop Probability                                                 |
# │  CoS = Class of Service (L2)                         |                                    Version 1.0  by Ewald Jeitler 2026  |
# └──────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────┘
EOF
cat "$DEFAULTCONFIGFILE"
read -r -p "Press Enter to continue..."
    fi
    CONFIG_FILE=$DEFAULTCONFIGFILE
fi

# --- check if provided config file exists -------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file does not exist: $CONFIG_FILE"
    exit 1
fi

while IFS= read -r line; do
    # skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    STREAMS+=("$line")
done < "$CONFIG_FILE"

# --- validate command array ---------------------------------------------------
if [[ ${#STREAMS[@]} -eq 0 ]]; then
    echo "Error: No command entries found in the configuration file."
    exit 1
fi

# --- create log directory -----------------------------------------------------
mkdir -p "$LOGDIR"

# --- start main while ---------------------------------------------------------
lineno=0
first_real_line=1
SESSION=$(generate_free_session)


while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))   # ---  always increase the real line number

    # ---  skip comments and empty lines, but keep lineno unchanged
    if [ -z "$line" ] || printf "%s" "$line" | grep -q "^#"; then
        continue
    fi

    # ---  parse_line receives:
    #      $1 = complete line
    #      $2 = real line number
    #      $3 = 1 if this is the first real command, otherwise 0
    parse_line "$line" "$lineno" "$first_real_line"

    # ---  disable FIRSTCMD after the first real command
    first_real_line=0

    # ---   extract HOST + ARGS
    read -r HOST ARGS <<< "$line"

    # --- create logfile name role port timestamp -------------------------------
    TS=$(date +%H:%M:%S)

    if [ "$ROLE" = "server" ] || [ "$ROLE" = "client" ]; then
    PORT="p_${PORT}"
    elif [ "$ROLE" = "ocmd" ]; then
    PORT="l_${PORT}"
    fi
    
    LOGFILE="${LOGDIR}/${PREAMBLELOGFILENAME}_${PORT}_${ROLE}_$_$(date +%d-%m-%Y_%H-%M-%S).log"

    CMD="$HOST $ARGS" 
    RUN_CMD=$(detect_run_cmd "$CMD")

    printf '%s | #--------------------------------------------------------------------------------------------\n' "$TS" >> "$LOGFILE"
    printf '%s | START CMD \"%s\"\n' "$TS" "$CMD" >> "$LOGFILE"
    printf '%s | #--------------------------------------------------------------------------------------------\n' "$TS" >> "$LOGFILE"

    # --- start tmux  --------------------------------------------------

    if [ "$FIRSTCMD" = "1" ]; then
    tmux new-session -d -s "$SESSION" \
    "tmux set-option history-limit 100000; \
     tmux set-option mouse on; \
     read_one_key() {
       local key
       if [ -n \"\$ZSH_VERSION\" ]; then
         read -k1 key </dev/tty
         printf '%s' \"\$key\"
         return
       fi
       if [ -n \"\$BASH_VERSION\" ]; then
         read -n1 key </dev/tty
         printf '%s' \"\$key\"
         return
       fi
       key=\$(dd bs=1 count=1 2>/dev/null </dev/tty)
       printf '%s' \"\$key\"
     }; \
    
     while :; do \
       printf '===== CMD: %s =====\n\n' \"$CMD\"; \
       $RUN_CMD 2>&1 | while IFS= read -r line; do \
         printf '%s | %s\n' \"\$(date +%H:%M:%S)\" \"\$line\"; \
       done | tee -a \"$LOGFILE\"; \
       echo; \
       echo '>>> [r] repeat   |   [s] shell   |   [any] close'; \
       input=\$(read_one_key); \
       echo; \
       case \"\$input\" in \
         r|R) \
           echo 'Repeating...'; \
           continue ;; \
         s|S) \
           echo 'Interactive mode...'; \
           exec \$SHELL ;; \
         e|E) \
           echo 'Closing...'; \
           break ;; \
         *) \
           echo 'Unknown input – try again...'; \
           break ;; \
       esac; \
     done"
    else
    tmux split-window -t "$SESSION" -v \
    "tmux set-option history-limit 100000; \
     tmux set-option mouse on; \
    
     read_one_key() {
       local key
       if [ -n \"\$ZSH_VERSION\" ]; then
         read -k1 key </dev/tty
         printf '%s' \"\$key\"
         return
       fi
       if [ -n \"\$BASH_VERSION\" ]; then
         read -n1 key </dev/tty
         printf '%s' \"\$key\"
         return
       fi
       key=\$(dd bs=1 count=1 2>/dev/null </dev/tty)
       printf '%s' \"\$key\"
     }; \
    
     while :; do \
       printf '===== CMD: %s =====\n\n' \"$CMD\"; \
       $RUN_CMD 2>&1 | while IFS= read -r line; do \
         printf '%s | %s\n' \"\$(date +%H:%M:%S)\" \"\$line\"; \
       done | tee -a \"$LOGFILE\"; \
       echo; \
       echo '>>> [r] repeat   |   [s] shell   |   [any] close'; \
       input=\$(read_one_key); \
       echo; \
       case \"\$input\" in \
         r|R) \
           echo 'Repeating...'; \
           continue ;; \
         s|S) \
           echo 'Interactive mode...'; \
           exec \$SHELL ;; \
         e|E) \
           echo 'Closing...'; \
           break ;; \
         *) \
           echo 'Unknown input – try again...'; \
           break ;; \
       esac; \
     done"
    tmux select-layout -t "$SESSION" tiled
    fi
done < "$CONFIG_FILE"

tmux attach-session -t "$SESSION"
printf "\n  THX for using $SCRIPTNAME version $VERSION - https://www.jeitler.guru - \n\n"
