#!/bin/bash
#
#      Name    : gerste (GERman Secure Time Editor)
#      Version : 0.3.0
#      License : GNU General Public License v3.0 (https://www.gnu.org/licenses/gpl-3.0)
#      GitHub  : https://github.com/paranoidpeter/gerste
#      Author  : paranoidpeter
#      Mail    : peterparanoid@proton.me
#
#      Copyright (c) 2024 paranoidpeter
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

# Check root
if [[ ${EUID} -ne 0 ]]; then
    echo "[ ${SCRIPT_NAME} ] error: root permissions needed"
    exit 1
fi

# Versioninfos
readonly VERSION="0.3.0"
readonly SCRIPT_NAME="gerste"

# Printhelpers
function error {
    echo "[ ${SCRIPT_NAME} ] error: ${1}"
    logger -p user.err "[ ${SCRIPT_NAME} ] error: ${1}"
    exit 1
}

function info {
    echo "[ ${SCRIPT_NAME} ] info: ${1}"
    logger "[ ${SCRIPT_NAME} ] info: ${1}"
}

# Parameter handling
tor_enabled=false
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
            error "illegal parameter: ${parameter}"
            ;;
    esac
done

### DEPENDENCIES AND URLs
# Check if needed dependencies are installed
dependencies=( wget date grep )
for dependency in "${dependencies[@]}"; do
    [[ -z $(command -v "$dependency") ]] && error "${dependency} is not installed"
done

# Set URLs 
# NOTE: Test new URLs before adding to server_urls; Expected output format: 12:34:56
#   > wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "example-url.org" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]""
if [[ "$tor_enabled" == "true" ]]; then
 
    # Check if tor is active and torsocks is installed
    if [[ -z $(pgrep -x tor) ]]; then
        error "no tor process found"
    fi
    if [[ -z $(command -v torsocks) ]]; then
        echo "torsocks is not installed"
    fi

    # Load TOR URLs from /etc/gerste.conf
    readarray -t server_urls < <(awk '/^\[TOR-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' /etc/gerste.conf)

    for url in "${server_urls[@]}"; do
        if ! [[ $url =~ \.onion$ ]]; then
            error "invalid onion URL format: ${url}. URL should end with \".onion\""
        fi
    done

else
    # Load clearweb URLs from /etc/gerste.conf
    readarray -t server_urls < <(awk '/^\[CLEARWEB-URLS\]/{found=1; next} /^\[/{found=0} found && !/^#/ && NF{print}' /etc/gerste.conf)
fi

### "RANDOM" URL SELECTION
if [[ ${#server_urls[@]} -lt 1 ]]; then
    error "no URLs given"
elif [[ ${#server_urls[@]} -eq 1 ]]; then
    random_url=${server_urls[0]} && readonly random_url
else
    random_url_selector=$((RANDOM % ${#server_urls[@]})) && readonly random_url_selector
    random_url=${server_urls[${random_url_selector}]} && readonly random_url
fi

### TIME EXTRACTION
if [[ "$tor_enabled" == "true" ]]; then

    # Get new time via wget (WITH torsocks) + recheck if execution was successful
    if ! fetched_time=$(torsocks wget --server-response --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --no-cache --delete-after --quiet"$random_url" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]") && readonly fetched_time; then
        error "could not resolve URL: ${random_url}"
    fi

else

    # Get new time via wget (WITHOUT torsocks) + recheck if execution was successful
    if ! fetched_time=$(wget --server-response --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --no-cache --delete-after --quiet "$random_url" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]") && readonly fetched_time; then
        error "could not resolve URL: ${random_url}"
    fi

fi

# Get current systemtime to compare later
current_time=$(date +%H:%M:%S) && readonly current_time

# Split fetched_time into hours, minutes and seconds
if [[ $(echo "$fetched_time" | grep -o ":" | wc -l) -ne 2 ]]; then
    error "fetched time format is invalid: ${fetched_time}"
else
    IFS=':' read -ra time_array <<< "$fetched_time"
    hours=${time_array[0]}
    readonly minutes=${time_array[1]}
    readonly seconds=${time_array[2]}
fi

### SUMMER-/WINTERTIME OPERATIONS
# Read current timezone
current_timezone=$(date +%Z) && readonly current_timezone

# Check if timezone matches CET (wintertime)
if [[ ${current_timezone} == "CET" ]]; then
    readonly wintertime=true
else
    readonly wintertime=false
fi

# Increment hours to match CET/CEST-Timezone
if [[ ${wintertime} == "true" ]]; then
    hours=$((${hours#0} + 1)) # remove leading "0" from hours if present and increment by 1 for wintertime(i.e. "07:00:00" -> "8:00:00")
else
    hours=$((${hours#0} + 2)) # remove leading "0" from hours if present and increment by 2 for summertime(i.e. "07:00:00" -> "9:00:00")
fi

# 24h formatfix (i.e. from "24:56:00" to "00:56:00")
if [[ ${hours} -eq 24 ]]; then
    hours="00"
fi

# Re-add leading "0" to hours if missing (i.e. from "9:00:00" to "09:00:00")
if [[ ${#hours} -eq 1 ]]; then
    hours="0${hours}"
fi
readonly hours

### VALIDATE DATE FORMAT
# Check if values are valid and in range
if ! [[ ${hours} =~ ^[0-2][0-9]$ && ${minutes} =~ ^[0-5][0-9]$ && ${seconds} =~ ^[0-5][0-9]$ ]]; then
    error "fetched time is not valid: ${hours}:${minutes}:${seconds}"
fi

if [[ "${hours}" > "24" ]]; then
    error "fetched time is not valid: ${hours}:${minutes}:${seconds}"
fi

# Set new_time
readonly new_time="${hours}:${minutes}:${seconds}"

# Recheck with date command
if ! date --date "$new_time" &> /dev/null; then
    error "broken timeformat: ${new_time}"
fi

### TIME SETTING
# Check if systemtime differs to fetched time
if [[ ${new_time} == "$current_time" ]]; then
    info "nothing to do here.. time is correct already"
    exit 0
else
    # Set new systemtime
    date --set "$new_time" &> /dev/null
    info "systemtime updated to ${new_time}"
    exit 0
fi
exit 1 # Should not end here