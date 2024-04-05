#!/bin/bash
#
#      Name    : gerste (GERman Secure Timesync Execution)
#      Version : 0.2.6
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

# Version infos
readonly VERSION="0.2.6"
readonly SCRIPT_NAME="gerste"

# Parameter handling
debug_enabled=false
tor_enabled=false
for parameter in "$@"; do
    case "$parameter" in
        -d|--debug)
            debug_enabled=true
            ;;
        -t|--tor)
            tor_enabled=true
            ;;
        -v|--version)
            echo "${SCRIPT_NAME}-${VERSION}" && exit 0
            ;;
        -*)
            echo "[ ${SCRIPT_NAME} ] error: illegal parameter ${parameter}" && exit 1
            ;;
    esac
done

# Helpers
function error { echo "[ ${SCRIPT_NAME} ] error: ${1}"; }
function info { echo "[ ${SCRIPT_NAME} ] info: ${1}"; }
function debug {
    if [[ "$debug_enabled" == "true" ]]; then
        echo "[ ${SCRIPT_NAME} ] debug: ${1}"
    fi
}

### SETTING DEPENDENCIES AND SET URLs
# NOTE: Test new URLs before adding to server_urls; Expected output format: 12:34:56:
#       > (Optional: torsocks) wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "example-url.org" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]""
if [[ "$tor_enabled" == "true" ]]; then
 
    # Check if tor is active and torsocks is installed
    [[ $(systemctl is-active tor.service) != "active" ]] && error "tor is not active" && exit 1
    [[ -z $(command -v "torsocks") ]] && error "torsocks is not installed" && exit 1

    # You can configure a mixed list (clearweb and onion domains)
    server_urls=( 2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion )

else
    # Only clearweb domains
    server_urls=( archlinux.org )
fi

### CHECK DEPENDENCIES
dependencies=( wget date )
# Check installed packages
for dependency in "${dependencies[@]}"; do
    [[ -z $(command -v "$dependency") ]] && error "${dependency} is not installed" && exit 1
done
debug "dependencies check passed"

### "RANDOM" URL SELECTION
if [[ ${#server_urls[@]} -ne 1 ]]; then
    random_url_selector=$((RANDOM % ${#server_urls[@]})) && readonly random_url_selector
    random_url=${server_urls[${random_url_selector}]} && readonly random_url
else
    random_url=${server_urls[0]} && readonly random_url
fi

### GET TIME
# Get new time via wget (with or without torsocks)
if [[ "$tor_enabled" == "true" ]]; then
    wget_time=$(torsocks wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "$random_url" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]") && readonly wget_time && debug "wget time WITH torsocks"
else
    wget_time=$(wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "$random_url" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]") && readonly wget_time && debug "wget time WITHOUT torsocks"
fi
debug "wget server time = ${wget_time}"

# Get current systemtime
current_time=$(date +%H:%M:%S) && readonly current_time
debug "current systemtime: ${current_time}"

# Split wget_time into hours, minutes and seconds
IFS=':' read -ra time_array <<< "$wget_time"
hours=${time_array[0]}
readonly minutes=${time_array[1]}
readonly seconds=${time_array[2]}

### SUMMER-/WINTERTIME OPERATIONS
# Read current timezone and 
current_timezone=$(date +%Z) && readonly current_timezone
debug "current_timezone = \"${current_timezone}\""

# Check if timezone matches CET (wintertime)
[[ ${current_timezone} == "CET" ]] && readonly wintertime=true || readonly wintertime=false

# Increment hours to match CET/CEST-Timezone
if [[ ${wintertime} == "true" ]]; then
    hours=$((${hours#0} + 1)) # remove leading "0" from hours and increment by 1 (i.e. "07:00:00" -> "8:00:00")
    debug "wintertime = ${wget_time} -> ${hours}:${minutes}:${seconds}"
else
    hours=$((${hours#0} + 2)) # remove leading "0" from hours and increment by 2 (i.e. "07:00:00" -> "9:00:00")
    debug "summertime = ${wget_time} -> ${hours}:${minutes}:${seconds}"
fi

# 24h formatfix (i.e. from "24:56:00" to "00:56:00")
if [[ ${hours} -eq 24 ]]; then
    hours="00"
    debug " > fixed timeformat to ${hours}:${minutes}:${seconds}"
fi

# Re-add leading "0" to hours (i.e. from "9:00:00" to "09:00:00")
if [[ ${#hours} -eq 1 ]]; then
    hours="0${hours}"
    debug " > fixed timeformat to ${hours}:${minutes}:${seconds}"
fi

### CHECK IF new_time DIFFERS TO current_time
new_time="${hours}:${minutes}:${seconds}" && readonly new_time
[[ ${new_time} == "$current_time" ]] && info "nothing to do here.. time is correct already" && exit 0

### VALIDATE DATE FORMAT
date --date "${hours}:${minutes}:${seconds}" &> /dev/null

### CHECK IF ROOT, SET NEW TIME AND EXIT
if [[ ${EUID} -eq 0 ]]; then
    date --set "${hours}:${minutes}:${seconds}" &> /dev/null
    info "systemtime updated to ${hours}:${minutes}:${seconds}"
    exit 0
else
    if [[ -n $(command -v doas) ]]; then
        doas date --set "$new_time" &> /dev/null
        info "systemtime updated to ${new_time}"
    else
        sudo date --set "$new_time" &> /dev/null
        info "systemtime updated to ${new_time}"
    fi
fi
exit 0