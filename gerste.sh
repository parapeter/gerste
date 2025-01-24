#!/bin/bash
#
#      Name    : gerste (GERman-Secure-Time-Editor)
#      Version : 0.5.1
#      License : GNU General Public License v3.0 (https://www.gnu.org/licenses/gpl-3.0)
#      GitHub  : https://github.com/parapeter/gerste
#      Author  : parapeter <parapeter-git@proton.me>
#
#      Copyright (c) 2024 parapeter
#
#      This program is free software: you can redistribute it and/or modify
#      it under the terms of the GNU General Public License as published by
#      the Free Software Foundation, either version 3 of the License, or
#      (at your option) any later version.
#
#      This program is distributed in the hope that it will be useful,
#      but WITHOUT ANY WARRANTY; without even the implied warranty of
#      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#      GNU General Public License for more details.
#
#      You should have received a copy of the GNU General Public License
#      along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
### GENERAL ###
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

readonly VERSION="0.5.1"
readonly CONF_PATH="/etc/gerste.conf"

### HELPERS ###
function print_info() {
    local message="${1:-}"
    [[ -z "$message" ]] && error "missing parameter"
    echo "[ ${0} ] info: ${message}"
    logger "[ ${0} ] info: ${message}"
}

function error() {
    local message="${1:-}"
    [[ -z "$message" ]] && exit 1
    echo "[ ${0} ] error: ${message}"
    logger -p user.err "[ ${0} ] error: ${message}"
    exit 1
}

function random_from_array() {
    local -a array=("$@")
    local array_length=${#array[@]}

    if [[ ${array_length} -eq 1 ]]; then
        echo "${array[0]}"
    else
        local random_index=$((RANDOM % array_length))
        echo "${array[${random_index}]}"
    fi
}

function check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        error "you need root access"
    fi
}

### PARAMETER HANDLING ###
function parse_parameters() {
    for parameter in "$@"; do
        case "$parameter" in
            -t|--tor)
                tor_enabled=true
                ;;
            -d|--dry-run)
                dry_run_enabled=true
                ;;
            -v|--version)
                echo "${0}-${VERSION}"
                exit 0
                ;;
            *)
                error "invalid parameter: ${parameter}"
                ;;
        esac
    done
}

### DEPENDENCIES ###
function check_dependencies() {
    # Check if dependencies are installed
    local dependencies=( curl date grep )
    for dependency in "${dependencies[@]}"; do
        is_command_installed "$dependency"
    done

    # Check if config file is present
    if [[ ! -f "$CONF_PATH" ]]; then
        error "could not find $CONF_PATH"
    fi

    # Check if /etc/localtime is set
    if [[ ! -e /etc/localtime ]]; then
        error "could not find /etc/localtime"
    fi

    # Check if ca-certificates are present
    if [[ ! -f /etc/ssl/certs/ca-certificates.crt ]]; then
        error "could not find /etc/ssl/certs/ca-certificates.crt"
    fi

    # Check if tor is running (option -t/--tor)
    local tor_enabled=${tor_enabled:-false}
    if [[ "$tor_enabled" == "true" && -z $(pgrep -x tor) ]]; then
        error "no tor process found"
    fi
}

function is_command_installed() {
    local command_name="${1:-}"
    [[ -z "$command_name" ]] && error "missing parameter"
    if ! command -v "$command_name" &> /dev/null; then
        error "${command_name} needs to be installed"
    fi
}

### PREPARE URL ###
function load_urls() {
    local -a urls
    local tor_enabled=${tor_enabled:-false}
    
    if [[ "$tor_enabled" == "true" ]]; then
        readarray -t urls < <(awk '/^\[TOR-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' "$CONF_PATH") # Line by line after [TOR-URLS] until next line start with "["
    else
        readarray -t urls < <(awk '/^\[HTTPS-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' "$CONF_PATH") # Line by line after [HTTPS-URLS] until next line start with "["
    fi
    
    echo "${urls[@]}"
}

function validate_url() {
    local url="${1:-}"
    local tor_enabled=${tor_enabled:-false}
    [[ -z "$url" ]] && error "missing parameter"

    if [[ "$tor_enabled" == "true" ]]; then
        if [[ ! "$url" =~ \.onion$ ]]; then
            error "invalid onion URL (must end with .onion): ${url}"
        fi
    else
        if [[ ! "$url" =~ ^https:// ]]; then
            error "invalid URL (must start with https://): ${url}"
        fi
    fi
}

### TIME OPERATIONS ###
function fetch_time() {
    local url="${1:-}"
    local tor_enabled=${tor_enabled:-false}
    [[ -z "$url" ]] && error "missing message"

    # Fetch HTTP header response
    if [[ "$tor_enabled" == "true" ]]; then
        if ! response=$(
                curl \
                  --socks5-hostname localhost:9050 \
                  --head \
                  --silent \
                  --no-keepalive \
                  --tlsv1.3 \
                  --junk-session-cookies \
                  --max-redirs 0 \
                  --max-time 10 \
                  --proto =http,https \
                  --referer "" \
                  "$url" 2>&1
                  ); then
            error "could not fetch tor URL: $url"
        fi
    else
        if ! response=$(
                curl \
                  --cacert /etc/ssl/certs/ca-certificates.crt \
                  --head \
                  --silent \
                  --no-keepalive \
                  --tlsv1.3 \
                  --junk-session-cookies \
                  --max-redirs 0 \
                  --max-time 10 \
                  --proto =https \
                  --referer "" \
                  "$url" 2>&1
                  ); then
            error "could not fetch URL: $url"
        fi
    fi

    # Extract time from response
    if ! fetched_time=$(echo "$response" | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]"); then
        error "could not extract time from server response"
    fi

    echo "$fetched_time"
}

function adjust_timezone_offset() {
    local fetched_time="${1:-}"
    [[ -z "$fetched_time" ]] && error "missing parameter"
    
    local offset
    offset=$(date +%z) || error "could not detect timezone offset"

    if [[ $offset =~ ^([+-])([0-9]{2})([0-9]{2})$ ]]; then
        local offset_operator="${BASH_REMATCH[1]}" # Extract "+" or "-" with matching regex
        local offset_hours="${BASH_REMATCH[2]}" # Extract hours offset with matching regex
        local offset_minutes="${BASH_REMATCH[3]}" # Extract minutes offset with matching regex
    else
        error "unknown timezone offset format"
    fi

    local hours
    local minutes
    local seconds
    IFS=':' read -r hours minutes seconds <<< "$fetched_time" # Extract hh:mm:ss into variables

    # Add hours to match current system timezone
    if [[ "$offset_operator" == "+" ]]; then
        hours=$((${hours#0} + ${offset_hours#0})) # Remove leading 0's and add hours offset
        minutes=$((${minutes#0} + ${offset_minutes#0})) # Remove leading 0's and add minutes offset
    elif [[ "$offset_operator" == "-" ]]; then
        hours=$((${hours#0} - ${offset_hours#0})) # Remove leading 0 and subtract hours offset
        minutes=$((${minutes#0} - ${offset_minutes#0})) # Remove leading 0 and subtract minutes offset
    else
        error "unknown offset operator"
    fi

    # Format-Fix for $minutes greater than (or equal to) 60, i.e. 05:84:00 -> 06:24:00
    if [[ $minutes -ge 60 ]]; then
        hours=$((hours + 1))
        minutes=$((minutes % 60))
    fi

    # Format-Fix for $hours greater than (or equal to) 24, i.e. 26:54:00 -> 02:54:00 (or 24:54:00 -> 00:54:00)
    if [[ $hours -ge 24 ]]; then
        hours=$((hours % 24))
    fi

    # Format-Fix for $minutes less than 0, i.e. 04:-20:00 -> 03:40:00
    if [[ $minutes -lt 0 ]]; then
        hours=$((hours - 1))
        minutes=$((minutes + 60))
    fi

    # Format-Fix for $hours less than 0, i.e. -2:54:00 -> 22:54:00
    if [[ $hours -lt 0 ]]; then
        hours=$((hours + 24))
    fi

    # Additional Format-Fixes, i.e. 8:00:00 -> 08:00:00 (or 08:4:00 -> 08:04:00)
    [[ ${#hours} -eq 1 ]] && hours="0${hours}"
    [[ ${#minutes} -eq 1 ]] && minutes="0${minutes}"

    echo "${hours}:${minutes}:${seconds}"
}

function set_system_time() {
    local new_time="${1:-}"
    [[ -z "$new_time" ]] && error "missing parameter"
    local current_time
    current_time=$(date +%H:%M:%S) || error "could not get current time"

    # Validate new_time with date
    date --date "$new_time" &> /dev/null || error "broken timeformat: ${new_time}"

    # Set new time if differs to current systemtime
    if [[ "$new_time" == "$current_time" ]]; then
        print_info "nothing to do here.. time is correct already."
    else
        date --set "$new_time" &> /dev/null || error "cannot set new time: ${new_time}"
        print_info "set systemtime to: ${new_time}"
    fi
}

### MAIN ###
function main() {
    # General
    check_root
    parse_parameters "$@"
    check_dependencies

    # Load URLs
    local -a server_urls
    server_urls=($(load_urls))

    # Select random URL
    local random_url
    random_url=$(random_from_array "${server_urls[@]}")

    # Validate URL
    validate_url "$random_url"

    # Fetch time
    local fetched_time
    fetched_time=$(fetch_time "$random_url")

    # Adjust time
    local adjusted_time
    adjusted_time=$(adjust_timezone_offset "$fetched_time")

    # Set time (or print in dry-run)
    local dry_run_enabled=${dry_run_enabled:-false}
    if [[ "$dry_run_enabled" == "true" ]]; then
        echo "[ gerste ] dry-run: $adjusted_time (from: $random_url)"
    else
        set_system_time "$adjusted_time"
    fi
}
main "$@"