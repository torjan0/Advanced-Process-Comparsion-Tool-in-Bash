#!/bin/bash
###############################################################################
# process_compare.sh - Advanced Process Comparison Tool (Overdrive Mode)
#
# Description:
#   This advanced script analyzes processes via the /proc filesystem,
#   extracting extended information (command, memory usage, CPU ticks, state,
#   nice, start time, and owner). It supports multiple filters (by memory, CPU,
#   command substring, and user), sorting by a selected field, interactive
#   selection of process pairs, and multiple output formats (text, JSON, CSV,
#   HTML). It can also run in auto–refresh (monitoring) mode, optionally in
#   parallel using GNU parallel, and can send desktop notifications (alerts)
#   when the best pair changes.
#
# Usage:
#   process_compare.sh [OPTIONS]
#
# (See the usage message below for details.)
#
# Author: Your Name
# Date: YYYY-MM-DD
#
# Requirements:
#   - Bash (v4+)
#   - GNU getopt (for enhanced option parsing)
#   - Linux /proc filesystem; optionally GNU parallel and notify-send.
###############################################################################

# ---------------------------
# Default configuration values
# ---------------------------
MIN_MEM=0
MAX_MEM=""
CMD_FILTER=""
MIN_CPU=0
FILTER_USER=""

SORT_FIELD="pid"         # Options: pid, cmd, mem, cpu, state, nice, start, user
SORT_ORDER="asc"         # asc or desc

OUTPUT_FORMAT="text"     # Options: text, json, csv, html

INTERACTIVE=0            # 1: interactive selection mode
REFRESH=0                # In seconds; 0 means no auto-refresh
LIST_ALL=0               # 1: list all matching processes
SUMMARY=0                # 1: show summary statistics
ALERT=0                  # 1: send desktop notifications on best pair change
PARALLEL=0               # 1: run scanning in parallel (if GNU parallel available)
VERBOSE=0
LOG_FILE=""
OUTPUT_FILE=""

# ---------------------------
# Terminal colors (if supported)
# ---------------------------
if [ -t 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

# ---------------------------
# Debug logging function
# ---------------------------
log() {
    if [ "$VERBOSE" -eq 1 ]; then
        local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*"
        echo -e "${YELLOW}${msg}${RESET}" >&2
        [ -n "$LOG_FILE" ] && echo -e "$msg" >> "$LOG_FILE"
    fi
}

# ---------------------------
# Usage / Help message
# ---------------------------
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -m, --min-memory <kB>       Minimum memory usage (in kB) for filtering (default: 0)
  -M, --max-memory <kB>       Maximum memory usage (in kB) for filtering (default: no limit)
  -c, --cmd-filter <string>   Substring to filter process command (default: match all)
  -C, --min-cpu <ticks>       Minimum CPU ticks for filtering (default: 0)
  -u, --user <username/UID>   Filter processes by owner (username or UID)

  -s, --sort <field>          Sort matching processes by field:
                              pid, cmd, mem, cpu, state, nice, start, user
                              (default: pid)
  -O, --order <asc|desc>      Sort order (default: asc)

  -o, --output-format <fmt>   Output format: text (default), json, csv, html
      --csv                 Alias for --output-format csv
      --html                Alias for --output-format html

  -I, --interactive         Enable interactive mode to manually select process pair
  -r, --refresh <seconds>   Refresh interval (in seconds) for monitoring mode (default: off)
  -p, --parallel            Run process scanning in parallel (requires GNU parallel)
  -a, --all                 List all matching processes (in addition to best pair)
  -S, --summary             Display summary statistics (total count, average memory/CPU)

  -A, --alert               Enable desktop notifications (using notify-send) when the best pair changes
  -l, --log-file <filename> Log debug messages to the specified file
  -v, --verbose             Enable verbose (debug) logging
  -f, --file <output_file>  Write output to the specified file
  -h, --help                Display this help message and exit

Examples:
  $0 --min-memory 10000 --cmd-filter ssh
  $0 -m 5000 -c apache -u www-data --sort mem -O desc --all --summary
  $0 --refresh 10 --parallel --alert --html

EOF
    exit 1
}

# ---------------------------
# Parse command-line arguments using GNU getopt
# ---------------------------
PARSED_OPTIONS=$(getopt -n "$0" -o m:M:c:C:u:s:O:o:r:IaSpAl:vf:h --long min-memory:,max-memory:,cmd-filter:,min-cpu:,user:,sort:,order:,output-format:,refresh:,interactive,parallel,all,summary,alert,log-file:,verbose,file:,help,csv,html -- "$@")
if [ $? -ne 0 ]; then
    usage
fi
eval set -- "$PARSED_OPTIONS"
while true; do
    case "$1" in
        -m|--min-memory)
            MIN_MEM="$2"
            shift 2
            ;;
        -M|--max-memory)
            MAX_MEM="$2"
            shift 2
            ;;
        -c|--cmd-filter)
            CMD_FILTER="$2"
            shift 2
            ;;
        -C|--min-cpu)
            MIN_CPU="$2"
            shift 2
            ;;
        -u|--user)
            FILTER_USER="$2"
            shift 2
            ;;
        -s|--sort)
            SORT_FIELD="$2"
            shift 2
            ;;
        -O|--order)
            SORT_ORDER="$2"
            shift 2
            ;;
        -o|--output-format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --csv)
            OUTPUT_FORMAT="csv"
            shift
            ;;
        --html)
            OUTPUT_FORMAT="html"
            shift
            ;;
        -r|--refresh)
            REFRESH="$2"
            shift 2
            ;;
        -I|--interactive)
            INTERACTIVE=1
            shift
            ;;
        -p|--parallel)
            PARALLEL=1
            shift
            ;;
        -a|--all)
            LIST_ALL=1
            shift
            ;;
        -S|--summary)
            SUMMARY=1
            shift
            ;;
        -A|--alert)
            ALERT=1
            shift
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -f|--file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate numeric inputs
if ! [[ "$MIN_MEM" =~ ^[0-9]+$ ]]; then
    echo "Error: --min-memory must be a positive integer." >&2
    usage
fi
if [ -n "$MAX_MEM" ] && ! [[ "$MAX_MEM" =~ ^[0-9]+$ ]]; then
    echo "Error: --max-memory must be a positive integer." >&2
    usage
fi
if ! [[ "$MIN_CPU" =~ ^[0-9]+$ ]]; then
    echo "Error: --min-cpu must be a positive integer." >&2
    usage
fi
if [ "$REFRESH" -gt 0 ] && ! [[ "$REFRESH" =~ ^[0-9]+$ ]]; then
    echo "Error: --refresh must be a positive integer (seconds)." >&2
    usage
fi

log "Options set: MIN_MEM=$MIN_MEM, MAX_MEM=$MAX_MEM, CMD_FILTER='$CMD_FILTER', MIN_CPU=$MIN_CPU, FILTER_USER='$FILTER_USER'"
log "Sorting: SORT_FIELD=$SORT_FIELD, SORT_ORDER=$SORT_ORDER"
log "Output: OUTPUT_FORMAT=$OUTPUT_FORMAT, INTERACTIVE=$INTERACTIVE, REFRESH=$REFRESH, PARALLEL=$PARALLEL, LIST_ALL=$LIST_ALL, SUMMARY=$SUMMARY, ALERT=$ALERT"
log "Log file: $LOG_FILE, Output file: $OUTPUT_FILE"

# ---------------------------
# Global constants: clock ticks and boot time
# ---------------------------
CLK_TCK=$(getconf CLK_TCK)
if [ -z "$CLK_TCK" ]; then
    echo "Error: Could not determine clock ticks per second." >&2
    exit 2
fi
BTIME=$(grep '^btime' /proc/stat | awk '{print $2}')
log "CLK_TCK=$CLK_TCK, BTIME=$BTIME"

# Global variable to store previous best pair for alerts
PREV_BEST_PAIR=""

# ---------------------------
# Function: get_process_info
# Description:
#   For a given PID, extract extended process information:
#     PID | Command | Memory (VmRSS, kB) | CPU ticks (utime+stime) |
#     State | Nice | Start Time (epoch) | Start Time (formatted) |
#     UID | User
#
#   This version reworks the parsing of /proc/[pid]/stat by:
#     - Reading the entire stat line.
#     - Extracting the command (inside parentheses) and then isolating the
#       remainder of the fields.
#     - Using field numbers that correctly map to utime (original field 14 → rest field 11),
#       stime (field 15 → rest field 12), nice (field 19 → rest field 16), and starttime
#       (field 22 → rest field 19).
# ---------------------------
get_process_info() {
   local pid="$1"
    local proc_dir="/proc/$pid"
    if [[ ! -d "$proc_dir" ]]; then
        return 1
    fi

    # Get the stat line from /proc/[pid]/stat.
    local stat_line
    if [ -r "$proc_dir/stat" ]; then
        stat_line=$(cat "$proc_dir/stat" 2>/dev/null)
    else
        return 1
    fi

    # Field 1 (pid) is the first token.
    local stat_pid
    stat_pid=$(echo "$stat_line" | cut -d' ' -f1)

    # Extract the command (field 2) which is enclosed in parentheses.
    local comm
    comm=$(echo "$stat_line" | sed -E 's/^[0-9]+ \(([^)]*)\).*/\1/')

    # Remove the first two fields (pid and comm) so that the remaining fields
    # can be split into an array.
    local rest
    rest=$(echo "$stat_line" | sed -E 's/^[0-9]+ \([^)]*\) //')

    # Read the rest of the fields into an array.
    read -a fields <<< "$rest"
    # According to proc(5), after removing the first two fields:
    #   fields[0] is Field 3 (state),
    #   fields[11] is Field 14 (utime),
    #   fields[12] is Field 15 (stime),
    #   fields[16] is Field 19 (nice),
    #   fields[19] is Field 22 (starttime).
    local utime stime cpu nice start_ticks
    utime=${fields[11]}
    stime=${fields[12]}
    # If either is empty, default to 0.
    [ -z "$utime" ] && utime=0
    [ -z "$stime" ] && stime=0
    cpu=$((utime + stime))
    nice=${fields[16]}
    [ -z "$nice" ] && nice=0
    start_ticks=${fields[19]}
    [ -z "$start_ticks" ] && start_ticks=0

    # Memory usage: extract VmRSS from /proc/[pid]/status (in kB)
    local mem
    mem=$(grep -i '^VmRSS:' "$proc_dir/status" 2>/dev/null | awk '{print $2}')
    [ -z "$mem" ] && mem=0

    # Process state from /proc/[pid]/status (or you could use fields[0] from stat_line)
    local state
    state=$(grep '^State:' "$proc_dir/status" 2>/dev/null | awk '{print $2}')

    # Convert start_ticks (Field 22) to epoch time.
    local start_epoch
    start_epoch=$(awk -v ticks="$start_ticks" -v clk="$CLK_TCK" -v btime="$BTIME" 'BEGIN { printf "%.0f", btime + ticks/clk }')
    local start_fmt
    start_fmt=$(date -d "@$start_epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)

    # Get UID from /proc/[pid]/status and resolve the username.
    local uid user
    uid=$(grep '^Uid:' "$proc_dir/status" 2>/dev/null | awk '{print $2}')
    user=$(getent passwd "$uid" | cut -d: -f1 2>/dev/null)
    [ -z "$user" ] && user="$uid"

    # Output all the fields separated by a pipe.
    # Order: pid|command|mem|cpu|state|nice|start_epoch|start_fmt|uid|user
    echo "$stat_pid|$comm|$mem|$cpu|$state|$nice|$start_epoch|$start_fmt|$uid|$user"
}

# ---------------------------
# Function: collect_processes
# Description:
#   Scan /proc for numeric directories and collect process info,
#   then filter by MIN_MEM, MAX_MEM, MIN_CPU, CMD_FILTER, and FILTER_USER.
# ---------------------------
collect_processes() {
    local proc_info
    local processes=()

    if [ "$PARALLEL" -eq 1 ] && command -v parallel >/dev/null 2>&1; then
        log "Running in parallel mode."
        # GNU parallel: for each numeric directory, run get_process_info.
        while IFS= read -r line; do
            processes+=("$line")
        done < <(find /proc -maxdepth 1 -type d -regex '/proc/[0-9]+' -print0 | \
                  parallel -0 -n1 bash -c 'get_process_info "$(basename "{}")"')
    else
        for pid_dir in /proc/[0-9]*; do
            local pid
            pid=$(basename "$pid_dir")
            proc_info=$(get_process_info "$pid")
            [ -n "$proc_info" ] && processes+=("$proc_info")
        done
    fi

    # Filter processes according to options.
    local filtered=()
    local pid cmd mem cpu state nice start_epoch start_fmt uid user
    for proc in "${processes[@]}"; do
        IFS='|' read -r pid cmd mem cpu state nice start_epoch start_fmt uid user <<< "$proc"
        # Memory filter.
        if [ "$mem" -lt "$MIN_MEM" ]; then continue; fi
        if [ -n "$MAX_MEM" ] && [ "$mem" -gt "$MAX_MEM" ]; then continue; fi
        # CPU filter.
        if [ "$cpu" -lt "$MIN_CPU" ]; then continue; fi
        # Command filter.
        if [ -n "$CMD_FILTER" ] && [[ "$cmd" != *"$CMD_FILTER"* ]]; then continue; fi
        # User filter.
        if [ -n "$FILTER_USER" ]; then
            if [[ "$FILTER_USER" =~ ^[0-9]+$ ]]; then
                [ "$uid" -ne "$FILTER_USER" ] && continue
            else
                if [[ "${user,,}" != "${FILTER_USER,,}" ]]; then continue; fi
            fi
        fi
        filtered+=("$proc")
    done

    # Output each filtered process on its own line.
    for line in "${filtered[@]}"; do
        echo "$line"
    done
}

# ---------------------------
# Function: sort_processes
# Description:
#   Sort lines (each a pipe-delimited record) by a given field.
#   Field mapping:
#      pid -> 1, cmd -> 2, mem -> 3, cpu -> 4, state -> 5,
#      nice -> 6, start (epoch) -> 7, user -> 10
# ---------------------------
sort_processes() {
    local field="$1"
    local order="$2"
    local col
    case "$field" in
        pid) col=1 ;;
        cmd) col=2 ;;
        mem) col=3 ;;
        cpu) col=4 ;;
        state) col=5 ;;
        nice) col=6 ;;
        start) col=7 ;;
        user) col=10 ;;
        *) col=1 ;;
    esac
    if [ "$order" = "desc" ]; then
        sort -t'|' -k${col}r,${col}r
    else
        sort -t'|' -k${col},${col}
    fi
}

# ---------------------------
# Function: find_best_pair
# Description:
#   Among the matching processes, compare each unique pair and return
#   the pair with the smallest combined difference (memory diff + CPU ticks diff).
#   Returns: best_diff|process1_info|process2_info
# ---------------------------
find_best_pair() {
    local best_diff=999999999
    local best_pair1=""
    local best_pair2=""
    local n=${#MATCHED_PROCESSES[@]}
    local i j
    for (( i=0; i<n; i++ )); do
        IFS='|' read -r _ _ mem1 cpu1 _ rest1 <<< "${MATCHED_PROCESSES[$i]}"
        for (( j=i+1; j<n; j++ )); do
            IFS='|' read -r _ _ mem2 cpu2 _ rest2 <<< "${MATCHED_PROCESSES[$j]}"
            local diff_mem=$(( mem1 > mem2 ? mem1 - mem2 : mem2 - mem1 ))
            local diff_cpu=$(( cpu1 > cpu2 ? cpu1 - cpu2 : cpu2 - cpu1 ))
            local diff=$(( diff_mem + diff_cpu ))
            if [ "$diff" -lt "$best_diff" ]; then
                best_diff=$diff
                best_pair1="${MATCHED_PROCESSES[$i]}"
                best_pair2="${MATCHED_PROCESSES[$j]}"
            fi
        done
    done
    echo "$best_diff|$best_pair1|$best_pair2"
}

# ---------------------------
# Function: interactive_select_pair
# Description:
#   In interactive mode, list all matching processes with index numbers and
#   prompt the user to choose two processes manually.
# ---------------------------
interactive_select_pair() {
    echo -e "${BOLD}Matching processes:${RESET}"
    local idx=0
    local pid cmd mem cpu state nice start_epoch start_fmt uid user
    for proc in "${MATCHED_PROCESSES[@]}"; do
        IFS='|' read -r pid cmd mem cpu state nice start_epoch start_fmt uid user <<< "$proc"
        printf "[%d] PID: %s, Command: %.40s, Memory: %s kB, CPU: %s, User: %s, Started: %s\n" \
               "$idx" "$pid" "$cmd" "$mem" "$cpu" "$user" "$start_fmt"
        ((idx++))
    done
    echo -n "Enter index of first process: "
    read -r idx1
    echo -n "Enter index of second process: "
    read -r idx2
    if [ "$idx1" -ge 0 ] && [ "$idx1" -lt "${#MATCHED_PROCESSES[@]}" ] && \
       [ "$idx2" -ge 0 ] && [ "$idx2" -lt "${#MATCHED_PROCESSES[@]}" ]; then
        BEST_PAIR="manual|${MATCHED_PROCESSES[$idx1]}|${MATCHED_PROCESSES[$idx2]}"
    else
        echo "Invalid selection. Falling back to automatic best pair."
        BEST_PAIR=$(find_best_pair)
    fi
}

# ---------------------------
# Function: print_summary
# Description:
#   Compute and display summary statistics: total matching processes,
#   average memory, and average CPU ticks.
# ---------------------------
print_summary() {
    local total=0 sum_mem=0 sum_cpu=0
    local pid cmd mem cpu rest
    for proc in "${MATCHED_PROCESSES[@]}"; do
        IFS='|' read -r pid cmd mem cpu rest <<< "$proc"
        total=$((total + 1))
        sum_mem=$((sum_mem + mem))
        sum_cpu=$((sum_cpu + cpu))
    done
    if [ "$total" -gt 0 ]; then
        local avg_mem avg_cpu
        avg_mem=$(awk -v s="$sum_mem" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        avg_cpu=$(awk -v s="$sum_cpu" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        echo "Summary: Total matching processes: $total, Average Memory: $avg_mem kB, Average CPU Ticks: $avg_cpu"
    fi
}

# ---------------------------
# Output functions for various formats
# ---------------------------
print_results_text() {
    local best_info diff_line
    if [ "$INTERACTIVE" -eq 1 ]; then
        interactive_select_pair
        best_info="$BEST_PAIR"
    else
        best_info=$(find_best_pair)
    fi
    IFS='|' read -r best_diff pair1 pair2 <<< "$best_info"
    echo -e "${BOLD}=============================================${RESET}"
    echo -e "${BOLD} Advanced Process Comparison Report${RESET}"
    echo -e "${BOLD}=============================================${RESET}"
    echo "Filters applied:"
    echo "  Minimum Memory: ${MIN_MEM} kB"
    [ -n "$MAX_MEM" ] && echo "  Maximum Memory: ${MAX_MEM} kB"
    echo "  Minimum CPU Ticks: ${MIN_CPU}"
    [ -n "$CMD_FILTER" ] && echo "  Command contains: '$CMD_FILTER'"
    [ -n "$FILTER_USER" ] && echo "  User: $FILTER_USER"
    echo ""
    echo "Best Process Pair (combined diff = $best_diff):"
    IFS='|' read -r pid1 cmd1 mem1 cpu1 state1 nice1 start_epoch1 start_fmt1 uid1 user1 <<< "$pair1"
    IFS='|' read -r pid2 cmd2 mem2 cpu2 state2 nice2 start_epoch2 start_fmt2 uid2 user2 <<< "$pair2"
    echo "Process 1: PID: $pid1, Command: $cmd1, Memory: ${mem1} kB, CPU: $cpu1, State: $state1, Nice: $nice1, User: $user1, Started: $start_fmt1"
    echo "Process 2: PID: $pid2, Command: $cmd2, Memory: ${mem2} kB, CPU: $cpu2, State: $state2, Nice: $nice2, User: $user2, Started: $start_fmt2"
    echo -e "${BOLD}=============================================${RESET}"
    if [ "$LIST_ALL" -eq 1 ]; then
        echo "All Matching Processes:"
        for proc in "${MATCHED_PROCESSES[@]}"; do
            IFS='|' read -r pid cmd mem cpu state nice start_epoch start_fmt uid user <<< "$proc"
            printf "PID: %s, Command: %.40s, Memory: %s kB, CPU: %s, State: %s, Nice: %s, User: %s, Started: %s\n" \
                   "$pid" "$cmd" "$mem" "$cpu" "$state" "$nice" "$user" "$start_fmt"
        done
        echo -e "${BOLD}=============================================${RESET}"
    fi
    if [ "$SUMMARY" -eq 1 ]; then
        print_summary
        echo -e "${BOLD}=============================================${RESET}"
    fi
}

print_results_json() {
    local best_info
    if [ "$INTERACTIVE" -eq 1 ]; then
        interactive_select_pair
        best_info="$BEST_PAIR"
    else
        best_info=$(find_best_pair)
    fi
    IFS='|' read -r best_diff pair1 pair2 <<< "$best_info"
    IFS='|' read -r pid1 cmd1 mem1 cpu1 state1 nice1 start_epoch1 start_fmt1 uid1 user1 <<< "$pair1"
    IFS='|' read -r pid2 cmd2 mem2 cpu2 state2 nice2 start_epoch2 start_fmt2 uid2 user2 <<< "$pair2"
    cat <<EOF
{
  "filters": {
    "min_memory": $MIN_MEM,
    "max_memory": $( [ -n "$MAX_MEM" ] && echo "$MAX_MEM" || echo "null" ),
    "min_cpu": $MIN_CPU,
    "cmd_filter": "$CMD_FILTER",
    "user": "$FILTER_USER"
  },
  "best_pair": {
    "combined_difference": $best_diff,
    "process1": {
      "pid": $pid1,
      "command": "$cmd1",
      "memory_kB": $mem1,
      "cpu_ticks": $cpu1,
      "state": "$state1",
      "nice": $nice1,
      "start_epoch": $start_epoch1,
      "start_time": "$start_fmt1",
      "uid": $uid1,
      "user": "$user1"
    },
    "process2": {
      "pid": $pid2,
      "command": "$cmd2",
      "memory_kB": $mem2,
      "cpu_ticks": $cpu2,
      "state": "$state2",
      "nice": $nice2,
      "start_epoch": $start_epoch2,
      "start_time": "$start_fmt2",
      "uid": $uid2,
      "user": "$user2"
    }
  },
  "all_matching_processes": [
EOF
    local first=1
    local proc
    for proc in "${MATCHED_PROCESSES[@]}"; do
        IFS='|' read -r pid cmd mem cpu state nice start_epoch start_fmt uid user <<< "$proc"
        if [ $first -eq 0 ]; then echo "    ,"; else first=0; fi
        cat <<EOF
    {
      "pid": $pid,
      "command": "$cmd",
      "memory_kB": $mem,
      "cpu_ticks": $cpu,
      "state": "$state",
      "nice": $nice,
      "start_epoch": $start_epoch,
      "start_time": "$start_fmt",
      "uid": $uid,
      "user": "$user"
    }
EOF
    done
    echo "  ]"
    if [ "$SUMMARY" -eq 1 ]; then
        local total=0 sum_mem=0 sum_cpu=0
        for proc in "${MATCHED_PROCESSES[@]}"; do
            IFS='|' read -r pid cmd mem cpu rest <<< "$proc"
            total=$((total + 1))
            sum_mem=$((sum_mem + mem))
            sum_cpu=$((sum_cpu + cpu))
        done
        local avg_mem avg_cpu
        avg_mem=$(awk -v s="$sum_mem" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        avg_cpu=$(awk -v s="$sum_cpu" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        cat <<EOF
  ,
  "summary": {
    "total_matching_processes": $total,
    "average_memory_kB": $avg_mem,
    "average_cpu_ticks": $avg_cpu
  }
EOF
    fi
    echo "}"
}

print_results_csv() {
    local best_info
    if [ "$INTERACTIVE" -eq 1 ]; then
        interactive_select_pair
        best_info="$BEST_PAIR"
    else
        best_info=$(find_best_pair)
    fi
    IFS='|' read -r best_diff pair1 pair2 <<< "$best_info"
    IFS='|' read -r pid1 cmd1 mem1 cpu1 state1 nice1 start_epoch1 start_fmt1 uid1 user1 <<< "$pair1"
    IFS='|' read -r pid2 cmd2 mem2 cpu2 state2 nice2 start_epoch2 start_fmt2 uid2 user2 <<< "$pair2"
    echo "Type,PID,Command,Memory_kB,CPU_Ticks,State,Nice,Start_Epoch,Start_Time,UID,User"
    echo "Best Pair,${pid1},\"${cmd1}\",${mem1},${cpu1},${state1},${nice1},${start_epoch1},\"${start_fmt1}\",${uid1},${user1}"
    echo "Best Pair,${pid2},\"${cmd2}\",${mem2},${cpu2},${state2},${nice2},${start_epoch2},\"${start_fmt2}\",${uid2},${user2}"
    if [ "$LIST_ALL" -eq 1 ]; then
        echo ""
        echo "All Matching Processes:"
        echo "PID,Command,Memory_kB,CPU_Ticks,State,Nice,Start_Epoch,Start_Time,UID,User"
        for proc in "${MATCHED_PROCESSES[@]}"; do
            IFS='|' read -r pid cmd mem cpu state nice start_epoch start_fmt uid user <<< "$proc"
            echo "${pid},\"${cmd}\",${mem},${cpu},${state},${nice},${start_epoch},\"${start_fmt}\",${uid},${user}"
        done
    fi
    if [ "$SUMMARY" -eq 1 ]; then
        local total=0 sum_mem=0 sum_cpu=0
        for proc in "${MATCHED_PROCESSES[@]}"; do
            IFS='|' read -r pid cmd mem cpu rest <<< "$proc"
            total=$((total + 1))
            sum_mem=$((sum_mem + mem))
            sum_cpu=$((sum_cpu + cpu))
        done
        local avg_mem avg_cpu
        avg_mem=$(awk -v s="$sum_mem" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        avg_cpu=$(awk -v s="$sum_cpu" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        echo ""
        echo "Summary,Total Matching Processes,${total}"
        echo "Summary,Average Memory (kB),${avg_mem}"
        echo "Summary,Average CPU Ticks,${avg_cpu}"
    fi
}

print_results_html() {
    local best_info
    if [ "$INTERACTIVE" -eq 1 ]; then
        interactive_select_pair
        best_info="$BEST_PAIR"
    else
        best_info=$(find_best_pair)
    fi
    IFS='|' read -r best_diff pair1 pair2 <<< "$best_info"
    IFS='|' read -r pid1 cmd1 mem1 cpu1 state1 nice1 start_epoch1 start_fmt1 uid1 user1 <<< "$pair1"
    IFS='|' read -r pid2 cmd2 mem2 cpu2 state2 nice2 start_epoch2 start_fmt2 uid2 user2 <<< "$pair2"
    cat <<EOF
<html>
<head>
  <title> Advanced Process Comparison Report</title>
  <style>
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #aaa; padding: 8px; text-align: left; }
    th { background-color: #ddd; }
  </style>
</head>
<body>
<h2> Advanced Process Comparison Report</h2>
<p>
<strong>Filters applied:</strong><br>
Memory ≥ ${MIN_MEM} kB
EOF
    [ -n "$MAX_MEM" ] && echo " and ≤ ${MAX_MEM} kB<br>"
    echo "CPU Ticks ≥ ${MIN_CPU}<br>"
    [ -n "$CMD_FILTER" ] && echo "Command contains: '$CMD_FILTER'<br>"
    [ -n "$FILTER_USER" ] && echo "User: $FILTER_USER<br>"
    cat <<EOF
</p>
<h3>Best Process Pair (combined diff = $best_diff)</h3>
<table>
  <tr><th>Field</th><th>Process 1</th><th>Process 2</th></tr>
  <tr><td>PID</td><td>$pid1</td><td>$pid2</td></tr>
  <tr><td>Command</td><td>$cmd1</td><td>$cmd2</td></tr>
  <tr><td>Memory (kB)</td><td>$mem1</td><td>$mem2</td></tr>
  <tr><td>CPU Ticks</td><td>$cpu1</td><td>$cpu2</td></tr>
  <tr><td>State</td><td>$state1</td><td>$state2</td></tr>
  <tr><td>Nice</td><td>$nice1</td><td>$nice2</td></tr>
  <tr><td>Start Time</td><td>$start_fmt1</td><td>$start_fmt2</td></tr>
  <tr><td>User</td><td>$user1</td><td>$user2</td></tr>
</table>
EOF
    if [ "$LIST_ALL" -eq 1 ]; then
        echo "<h3>All Matching Processes</h3>"
        echo "<table>"
        echo "<tr><th>PID</th><th>Command</th><th>Memory (kB)</th><th>CPU Ticks</th><th>State</th><th>Nice</th><th>Start Time</th><th>User</th></tr>"
        for proc in "${MATCHED_PROCESSES[@]}"; do
            IFS='|' read -r pid cmd mem cpu state nice start_epoch start_fmt uid user <<< "$proc"
            echo "<tr><td>$pid</td><td>$cmd</td><td>$mem</td><td>$cpu</td><td>$state</td><td>$nice</td><td>$start_fmt</td><td>$user</td></tr>"
        done
        echo "</table>"
    fi
    if [ "$SUMMARY" -eq 1 ]; then
        local total=0 sum_mem=0 sum_cpu=0
        for proc in "${MATCHED_PROCESSES[@]}"; do
            IFS='|' read -r pid cmd mem cpu rest <<< "$proc"
            total=$((total + 1))
            sum_mem=$((sum_mem + mem))
            sum_cpu=$((sum_cpu + cpu))
        done
        local avg_mem avg_cpu
        avg_mem=$(awk -v s="$sum_mem" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        avg_cpu=$(awk -v s="$sum_cpu" -v t="$total" 'BEGIN { printf "%.2f", s/t }')
        cat <<EOF
<h3>Summary</h3>
<p>Total Matching Processes: $total<br>
Average Memory: ${avg_mem} kB<br>
Average CPU Ticks: ${avg_cpu}</p>
EOF
    fi
    echo "</body></html>"
}

# ---------------------------
# Function: output_results
# Description:
#   Dispatch output according to the selected format.
# ---------------------------
output_results() {
    case "$OUTPUT_FORMAT" in
        json) print_results_json ;;
        csv)  print_results_csv  ;;
        html) print_results_html ;;
        *)    print_results_text ;;
    esac
}

# ---------------------------
# Main processing routine: run analysis once (or loop if REFRESH is set)
# ---------------------------
run_analysis() {
    # Collect processes into the global array MATCHED_PROCESSES.
    MATCHED_PROCESSES=()
    # Read newline-separated output into an array.
    mapfile -t MATCHED_PROCESSES < <(collect_processes)
    if [ "${#MATCHED_PROCESSES[@]}" -lt 2 ]; then
        echo "Error: Insufficient processes found matching criteria." >&2
        return 3
    fi

    # If sorting is requested, sort the matching processes.
    MATCHED_PROCESSES=($(printf "%s\n" "${MATCHED_PROCESSES[@]}" | sort_processes "$SORT_FIELD" "$SORT_ORDER"))

    output_results

    # In monitoring mode with alerts, check for changes in best pair.
    if [ "$ALERT" -eq 1 ]; then
        local current_best
        if [ "$INTERACTIVE" -eq 1 ]; then
            current_best="$BEST_PAIR"
        else
            current_best=$(find_best_pair)
        fi
        if [ -n "$PREV_BEST_PAIR" ] && [ "$current_best" != "$PREV_BEST_PAIR" ]; then
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "Process Compare Alert" "New best pair detected. Combined diff: $(echo "$current_best" | cut -d'|' -f1)"
            fi
        fi
        PREV_BEST_PAIR="$current_best"
    fi
}

# ---------------------------
# Main loop: run once or in monitoring mode (auto-refresh)
# ---------------------------
if [ "$REFRESH" -gt 0 ]; then
    while true; do
        if [ -t 1 ]; then clear; fi
        run_analysis
        if [ -n "$OUTPUT_FILE" ]; then
            echo "==== $(date) ====" >> "$OUTPUT_FILE"
            run_analysis >> "$OUTPUT_FILE"
        fi
        sleep "$REFRESH"
    done
else
    if [ -n "$OUTPUT_FILE" ]; then
        run_analysis | tee "$OUTPUT_FILE"
    else
        run_analysis
    fi
fi

exit 0
