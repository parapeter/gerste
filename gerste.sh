#!/bin/bash
#
#      Name    : gerste (GERman-Secure-Time-Editor)
#      Version : 0.5.0
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

readonly VERSION="0.5.0"
readonly SCRIPT_NAME="gerste"
readonly CONF_PATH="/etc/gerste.conf"

tor_enabled=false
dry_run_enabled=false

### HELPERS ###
function print_info() {
    local message="${1:-"ERROR"}"
    echo "[ ${SCRIPT_NAME} ] info: ${message}"
    logger "[ ${SCRIPT_NAME} ] info: ${message}"
}

function error() {
    local message="${1:-"ERROR"}"
    echo "[ ${SCRIPT_NAME} ] error: ${message}"
    logger -p user.err "[ ${SCRIPT_NAME} ] error: ${message}"
    exit 1
}

function check_parameter_error() {
    local parameter="${1:-"ERROR"}"
    if [[ "$parameter" == "ERROR" ]]; then
        error "an error accured while passing parameters"
    fi
}

function random_from_array() {
    local -a array=("$@")

    if [[ ${#array[@]} -eq 1 ]]; then
        echo "${array[0]}"
    else
        local random_index=$((RANDOM % ${#array[@]}))
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
                echo "${SCRIPT_NAME}-${VERSION}"
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
    local dependencies=( curl date grep )

    if [[ ! -f "$CONF_PATH" ]]; then
        error "could not find $CONF_PATH"
    fi

    # Check if tor is running (option -t/--tor)
    if [[ "$tor_enabled" == "true" && -z $(pgrep -x tor) ]]; then
        error "no tor process found"
    fi

    for dependency in "${dependencies[@]}"; do
        is_command_installed "$dependency"
    done
}

function is_command_installed() {
    local command_name="${1:-"ERROR"}"
    check_parameter_error "$command_name"
    if ! command -v "$command_name" &> /dev/null; then
        error "${command_name} needs to be installed"
    fi
}

### PREPARE URL ###
function load_urls() {
    local -a urls
    
    if [[ "$tor_enabled" == "true" ]]; then
        readarray -t urls < <(awk '/^\[TOR-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' "$CONF_PATH") # Line by line after [TOR-URLS] until next line start with "["
    else
        readarray -t urls < <(awk '/^\[HTTPS-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' "$CONF_PATH") # Line by line after [HTTPS-URLS] until next line start with "["
    fi
    
    echo "${urls[@]}"
}

function validate_url() {
    local url="${1:-"ERROR"}"
    check_parameter_error "$url"

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
    local url="${1:-"ERROR"}"
    check_parameter_error "$url"

    # Fetch HTTP header response
    if [[ "$tor_enabled" == "true" ]]; then
        if ! response=$(
                curl \
                  --socks5-hostname localhost:9050 \
                  --head --silent \
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
    if ! date_info=$(echo "$response" | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]"); then
        error "could not extract time from server response"
    fi

    echo "$date_info"
}

function adjust_for_timezone() {
    local time="${1:-"ERROR"}"
    local timezone
    timezone=$(date +%Z) || error "could not get current timezone"
    check_parameter_error "$time"

    IFS=':' read -r hours minutes seconds <<< "$time" # Extract hh:mm:ss into variables

    # Add hours to match CET/CEST-Timezone
    if [[ "$timezone" == "CET" ]]; then
        hours=$((${hours#0} + 1)) # Remove leading 0 and add 1
    else
        hours=$((${hours#0} + 2)) # Remove leading 0 and add 2
    fi

    [[ $hours -eq 24 ]] && hours="00" # Format-Fix (i.e. 24:54:00 -> 00:54:00)
    [[ ${#hours} -eq 1 ]] && hours="0${hours}" # Format-Fix (i.e. 8:00:00 -> 08:00:00)

    echo "${hours}:${minutes}:${seconds}"
}

function set_system_time() {
    local new_time="${1:-"ERROR"}"
    local current_time
    current_time=$(date +%H:%M:%S) || error "could not get current time"
    check_parameter_error "$new_time"

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

    local -a server_urls=($(load_urls))

    local random_url
    random_url=$(random_from_array "${server_urls[@]}")

    # Validate URL
    validate_url "$random_url"

    # Fetch time
    local fetched_time
    fetched_time=$(fetch_time "$random_url")

    # Adjust time
    local adjusted_time
    adjusted_time=$(adjust_for_timezone "$fetched_time")

    # Set time (or print in dry-run)
    if [[ "$dry_run_enabled" == "true" ]]; then
        print_info "(dry-run) $adjusted_time (from: $random_url)"
    else
        set_system_time "$adjusted_time"
    fi
}
main "$@"