#!/usr/bin/env bash

##
# Varialbes
##
DOWNLOAD_FILE="/tmp/tmux_net_speed.download"
UPLOAD_FILE="/tmp/tmux_net_speed.upload"

get_tmux_option() {
    local option=$1
    local default_value=$2
    local option_value="$(tmux show-option -gqv "$option")"

    if [[ -z "$option_value" ]]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

set_tmux_option() {
    local option=$1
    local value=$2
    tmux set-option -gq "$option" "$value"
}

format_speed()
{
    local vel=$1

    # Consts
    local THOUSAND=1024
    local MILLION=1048576

    local vel_kb=$(( vel / THOUSAND ))
    local vel_mb=$(( vel / MILLION ))

    if [[ $vel_mb != 0 ]] ; then
        echo -n "$vel_mb MB/s"
    elif [[ $vel_kb != 0 ]] ; then
        echo -n "$vel_kb KB/s";
    else
        echo -n "$vel B/s";
    fi
}

get_velocity()
{
    local new_value=$1
    local old_value=$2

    local interval=$(get_tmux_option 'status-interval' 5)
    format_speed $(( ( new_value - old_value ) / interval ))
}

# Current time in nanoseconds. BSD date does not support %N and prints it
# literally, in which case fall back to seconds.
now_ns()
{
    local now=$(date +%s%N 2>/dev/null)

    if [[ "$now" == *N ]] ; then
        echo $(( ${now%N} * 1000000000 ))
    else
        echo "$now"
    fi
}

# State files hold "<total bytes> <unix time in ns> <speed in B/s>".
# Older versions stored only the total bytes, which reads back as
# "<bytes> 0 0".
read_state()
{
    local path="$1"
    local bytes=0
    local ts=0
    local speed=0

    if [[ -r "$path" ]] ; then
        read -r bytes ts speed < "$path"
    fi

    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    [[ "$speed" =~ ^[0-9]+$ ]] || speed=0

    echo "$bytes $ts $speed"
}

write_state()
{
    local path="$1"
    local bytes="$2"
    local ts="$3"
    local speed="$4"

    # Write then rename so a concurrent reader never sees a partial file
    local tmp=$(mktemp "${path}.XXXXXX")
    echo "$bytes $ts $speed" > "$tmp" && mv -f "$tmp" "$path"
}

# Reads the current counters, updates the state file and prints the speed.
# The state file is shared by every session and client, so the elapsed time
# comes from the file instead of assuming it equals status-interval. When
# another client refreshed the status line just before us, its delta is
# already consumed, so reuse the speed it calculated instead of reporting a
# near-zero delta.
update_speed()
{
    local file="$1"
    local column="$2"

    local now=$(now_ns)
    local bytes ts speed
    read -r bytes ts speed <<< "$(read_state "$file")"

    # No usable baseline yet (first run, or a state file of the old format)
    if [[ "$ts" -eq 0 ]] ; then
        write_state "$file" "$(sum_speed $column)" "$now" 0
        format_speed 0
        return
    fi

    local interval=$(get_tmux_option 'status-interval' 5)
    local min_ns=$(( interval * 500000000 ))
    (( min_ns < 500000000 )) && min_ns=500000000

    local elapsed=$(( now - ts ))
    if (( elapsed < min_ns )) ; then
        format_speed "$speed"
        return
    fi

    local new_bytes=$(sum_speed $column)
    local delta=$(( new_bytes - bytes ))
    # Counters start over when an interface is recreated
    (( delta < 0 )) && delta=0

    local elapsed_ms=$(( elapsed / 1000000 ))
    (( elapsed_ms < 1 )) && elapsed_ms=1
    local vel=$(( delta * 1000 / elapsed_ms ))

    write_state "$file" "$new_bytes" "$now" "$vel"
    format_speed "$vel"
}

get_interfaces()
{
    local interfaces=$(get_tmux_option @net_speed_interfaces "")

    if [[ -z "$interfaces" ]] ; then
        if is_osx
        then
            interfaces=$(netstat -i | tail +2 | sed -E 's/ +/ /g' | cut -d ' ' -f 1 | sort -u | grep "en")
        elif is_freebsd
        then
            interfaces=$(ifconfig -l)
        else
            for interface in /sys/class/net/*; do
                interfaces+=$(echo $(basename $interface) " ");
            done
        fi
    fi

    # Do not quote the variable. This way will handle trailing whitespace
    echo -n $interfaces
}

sum_speed()
{
    local column=$1

    declare -a interfaces=$(get_interfaces)

    local line=""
    local val=0
    for intf in ${interfaces[@]} ; do
        line=$(get_speed $intf)
        speed="$(echo -n $line | cut -d' ' -f $column)"
        let val+=${speed:=0}
    done

    echo $val
}

get_speed()
{
    local interface=$1

    if is_osx
    then
        line="$(netstat -b -i -I "$interface" | tail +2 | sed -E 's/ +/ /g' | cut -d ' ' -f 1,7,10 | uniq )" 
        down=$(echo -n $line | cut -d ' ' -f 2)
        up=$(echo -n $line | cut -d ' ' -f 3)
        echo "$down 0 0 0 0 0 0 0 $up"
    elif is_freebsd
    then
        # Only use the <Link#n> row, the address rows are subsets of it
        netstat -b -i -n -I "$interface" | awk '$3 ~ /^<Link/ { printf "%s 0 0 0 0 0 0 0 %s\n", $8, $11; exit }'
    else
        echo $(cat /proc/net/dev | grep "$interface" | cut -d':' -f 2)
    fi
}

is_osx() {
    [ $(uname) == "Darwin" ]
}

is_freebsd() {
    [ $(uname) == FreeBSD ]
}

is_cygwin() {
    command -v WMIC > /dev/null
}

command_exists() {
    local command="$1"
    type "$command" >/dev/null 2>&1
}
