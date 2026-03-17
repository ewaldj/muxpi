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
VERSION="0.44"
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
CONFIG_FILE=""
if [[ -z "$CONFIG_FILE" ]]; then
    if [[ ! -f "$DEFAULTCONFIGFILE" ]]; then
        echo "Creating example configuration file: $DEFAULTCONFIGFILE"
        sleep 2 
        cat > "$DEFAULTCONFIGFILE" <<'EOF'
# Filename: muxperf.conf
# -----------------------------------------------------------------------------
# Example Configuration file for muxperf.sh, defining one command per line to be
# executed in parallel tmux panes for network-performance testing,
# with all output timestamped and logged.
# -----------------------------------------------------------------------------
# Created by Ewald Jeitler — https://www.jeitler.guru
# -----------------------------------------------------------------------------

# Starts an iperf3 server on port 5201 with 1-second reports and exits after one client session. 
iperf3 -s -p 5201 -i 1 -1 

# Starts an iperf3 server on port 5202 with a 1-second reporting interval.
iperf3 -s -p 5202 -i 1

# Starts an iperf3 server on port 5203 with a 5-second reporting interval.
iperf3 -s -p 5203 -i 5 

# Runs an iperf3 client connecting to 127.0.0.1(localhost) on port 5201 using TCP.
iperf3 -c 127.0.0.1 -p 5201 

# Runs an iperf3 UDP client to localhost on port 5202 with 1000-byte datagrams and 1 Mbit/s bandwidth, and DSCP EF. 
iperf3 -c 127.0.0.1 -u -p 5202 -l 1000 -b 1m -S 46 

# Runs an iperf3 UDP client to localhost on port 5203 with 500-byte datagrams and 2 Mbit/s bandwidth, and DSCP EF. 
iperf3 -c 127.0.0.1 -u -p 5203 -l 500 -b 2m -S 18 

# Runs ten pings to 127.0.0.1 
ping -c 10 127.0.0.1 

#   +-----------------------------------------------------------------+
#   |                         QOS CHEAT SHEET                         |
#   +---------+-----------+-----------+-------------------------------+
#   | Class   | DSCP Name | DSCP Dec  | Description                   |
#   +---------+-----------+-----------+-------------------------------+
#   | CS0     | CS0       | 0         | Best Effort                   |
#   | CS1     | CS1       | 8         | Lower Effort / Background     |
#   | AF11    | AF11      | 10        | Assured Forwarding 1 (low)    |
#   | AF12    | AF12      | 12        | Assured Forwarding 1 (med)    |
#   | AF13    | AF13      | 14        | Assured Forwarding 1 (high)   |
#   | CS2     | CS2       | 16        | OAM / Bulk Data               |
#   | AF21    | AF21      | 18        | Assured Forwarding 2 (low)    |
#   | AF22    | AF22      | 20        | Assured Forwarding 2 (med)    |
#   | AF23    | AF23      | 22        | Assured Forwarding 2 (high)   |
#   | CS3     | CS3       | 24        | Signaling / Critical Apps     |
#   | AF31    | AF31      | 26        | Assured Forwarding 3 (low)    |
#   | AF32    | AF32      | 28        | Assured Forwarding 3 (med)    |
#   | AF33    | AF33      | 30        | Assured Forwarding 3 (high)   |
#   | CS4     | CS4       | 32        | Real-Time Apps                |
#   | AF41    | AF41      | 34        | Assured Forwarding 4 (low)    |
#   | AF42    | AF42      | 36        | Assured Forwarding 4 (med)    |
#   | AF43    | AF43      | 38        | Assured Forwarding 4 (high)   |
#   | CS5     | CS5       | 40        | Interactive Multimedia        |
#   | EF      | EF        | 46        | Expedited Forwarding (VoIP)   |
#   | CS6     | CS6       | 48        | Network Control               |
#   | CS7     | CS7       | 56        | Reserved / Highest Priority   |
#   +---------+-----------+-----------+-------------------------------+

EOF

echo
echo "# -----------------------------------------------------------------------------"
echo "A sample configuration file has been created."
echo "Helpful instructions and usage notes are included in the .conf file."
echo "The following content has been written to it:"
echo "# -----------------------------------------------------------------------------"
cat "$DEFAULTCONFIGFILE"
echo "# -----------------------------------------------------------------------------"
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
