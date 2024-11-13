#!/bin/bash
#
#      Name    : gerste (GERman-Secure-Time-Editor)
#      Version : 0.4.0
#      License : GNU General Public License v3.0 (https://www.gnu.org/licenses/gpl-3.0)
#      GitHub  : https://github.com/parapeter/gerste
#      Author  : parapeter
#      Mail    : parapeter-git@proton.me
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
### GENERAL
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

readonly VERSION="0.4.0"
readonly SCRIPT_NAME="gerste"
readonly CONF_PATH="/etc/gerste.conf"

### ECHO & LOGGING HELPERS
function info() {
    local message="${1:-"Unknown error"}"
    echo "[ ${SCRIPT_NAME} ] info: ${message}"
    logger "[ ${SCRIPT_NAME} ] info: ${message}"
}

function error() {
    local message="${1:-"Unknown error"}"
    echo "[ ${SCRIPT_NAME} ] error: ${message}"
    logger -p user.err "[ ${SCRIPT_NAME} ] error: ${message}"
    exit 1
}

function check_root() {
    if [[ ${EUID} -ne 0 ]]; then
        error "you need root access"
    fi
}

### PARAMETER HANDLING
tor_enabled=false
function parse_parameters() {
    for parameter in "$@"; do
        case "$parameter" in
            -t|--tor)
                tor_enabled=true
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

### DEPENDENCIES
function check_dependencies() {
    if [[ ! -f "$CONF_PATH" ]]; then
        error "could not find $CONF_PATH"
    fi

    if [[ "$tor_enabled" == "true" ]]; then
        if [[ -z $(pgrep -x tor) ]]; then
            error "no tor process found"
        fi
        local dependencies=( wget date grep torsocks )
    else
        local dependencies=( wget date grep )
    fi

    for dependency in "${dependencies[@]}"; do
        check_command "$dependency"
    done
}

function check_command() {
    local command_name="${1}"
    if ! command -v "$command_name" &> /dev/null; then
        error "${command_name} needs to be installed"
    fi
}

### PREPARE URL
# NOTE: Test new URLs before adding to /etc/gerste.conf -> Expected output format: 12:34:56
#   $ wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "example-url.org" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]""
function load_urls() {
    if [[ "$tor_enabled" == "true" ]]; then
        readarray -t urls < <(awk '/^\[TOR-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' "$CONF_PATH")
    else
        readarray -t urls < <(awk '/^\[HTTPS-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' "$CONF_PATH")
    fi
    
    echo "${urls[@]}"
}

function validate_onion_url() {
    local url="${1:-"Error"}"

    if [[ ! "$url" =~ \.onion$ ]]; then
        error "invalid onion URL (must end with .onion): ${url}"
    fi
}

function validate_https_url() {
    local url="${1:-"Error"}"

    if [[ ! "$url" =~ ^https:// ]]; then
        error "invalid URL (must start with https://): ${url}"
    fi
}

function select_random_url() {
    local -a urls=("$@")

    if [[ ${#urls[@]} -eq 1 ]]; then
        echo "${urls[0]}"
    else
        local random_index=$((RANDOM % ${#urls[@]}))
        echo "${urls[${random_index}]}"
    fi
}

### TIME OPERATIONS
function fetch_time() {
    local url="${1:-"Error"}"

    # Fetch HTTP header response
    if [[ "$tor_enabled" == "true" ]]; then
        if ! response=$(torsocks wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "$url" 2>&1); then
            error "could not fetch tor URL: $url"
        fi
    else
        if ! response=$(wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "$url" 2>&1); then
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
    local time="${1:-"Error"}"
    local timezone
    timezone=$(date +%Z)

    IFS=':' read -r hours minutes seconds <<< "$time" # Extract hh:mm:ss into variables

    # Add hours to match CET/CEST-Timezone
    if [[ "$timezone" == "CET" ]]; then
        hours=$((${hours#0} + 1))
    else
        hours=$((${hours#0} + 2))
    fi

    [[ $hours -eq 24 ]] && hours="00" # Format-Fix (i.e. 24:54:00 -> 00:54:00)
    [[ ${#hours} -eq 1 ]] && hours="0${hours}" # Format-Fix (i.e. 8:00:00 -> 08:00:00)

    echo "${hours}:${minutes}:${seconds}"
}

function set_system_time() {
    local new_time="${1:-"Error"}"
    local current_time
    current_time=$(date +%H:%M:%S)

    # Validate new_time
    if ! date --date "$new_time" &> /dev/null; then
        error "broken timeformat: ${new_time}"
    fi

    # Set new time if differs to current systemtime
    if [[ "$new_time" == "$current_time" ]]; then
        info "nothing to do here.. time is correct already."
    else
        date --set "$new_time" &> /dev/null && info "set systemtime to: ${new_time}"
    fi
}

### MAIN
function main() {
    check_root

    parse_parameters "$@"
    check_dependencies

    local -a server_urls=()
    while IFS='' read -r url; do server_urls+=("$url"); done < <(load_urls) # https://www.shellcheck.net/wiki/SC2207

    local random_url
    random_url=$(select_random_url "${server_urls[@]}")

    if [[ "$tor_enabled" == "true" ]]; then
        validate_onion_url "$random_url"
    else
        validate_https_url "$random_url"
    fi

    local fetched_time
    fetched_time=$(fetch_time "$random_url")

    local adjusted_time
    adjusted_time=$(adjust_for_timezone "$fetched_time")

    set_system_time "$adjusted_time"
}
main "$@"