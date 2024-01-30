#!/bin/bash
#
#      Name    : gerste (GERman Secure Timesync Execution)
#      Version : 0.2.1
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
### ERROR HANDLING
set -E
#
### DEBUGGING HELPER
function debug { [[ ${debug_mode} == true ]] && echo "[ gerste ] debug: ${1}"; }
#
### VERSION INFOS
readonly current_version="0.2.1"
readonly script_name="gerste"


### PARAMETER HANDLING
for parameter in "$@"; do
    case $parameter in
        -d|--debug)
            readonly debug_mode=true
            ;;
        -t|--tor)
            readonly tor=true
            ;;
        -v|--version)
            echo "${script_name}-${current_version}" && exit 0
            ;;
        *)
            echo "[ gerste ] error: illegal parameter $parameter" && exit 1
            ;;
    esac
done


### URL AND DEPENDENCIES CONFIG
#  Test new URLs before adding to server_urls:
#    > (Optional: torsocks) wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "example-url.org" 2>&1 | grep -i "Date:" | grep -o "[0-9][0-9]:[0-9][0-9]:[0-9][0-9]"
#  Expected output format: 
#    12:34:56
#  server_urls is a spaced separated list, you can add as many URLs as you wish. Example URLs:
#    Clearweb Domains  :  torproject.org, ...
#    Onion Domains     :  2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion (Tor-Project), ...
#  Note: You can configure a mixed list (clearweb and onion domains) if tor option is used.
if [[ ${tor} == true ]]; then
    server_urls=( 2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion )
    dependencies=( wget date shuf tor torsocks )
else
    server_urls=( archlinux.org )
    dependencies=( wget date shuf )
fi


### CHECK DEPENDENCIES
# Check installed packages
for dependency in "${dependencies[@]}"; do
    [[ -z $(command -v "${dependency}") ]] && echo "[ gerste ] error: ${dependency} is not installed" && exit 1
done

# If tor check whether tor.service is active
[[ ${tor} == true ]] && [[ $(systemctl is-active tor.service) != "active" ]] && echo "[ gerste ] error: tor is not active" && exit 1
debug "dependencies check passed"


### "RANDOM" URL SELECTION
readonly server_urls_length=$((${#server_urls[@]} - 1))
readonly random_url_selector=$(shuf -i 0-${server_urls_length} -n 1)
readonly random_url=${server_urls[${random_url_selector}]}
debug "selected url: \"${random_url}\""


### GET TIME
# Get new time via wget (with or without torsocks)
if [[ ${tor} == true ]]; then
    readonly wget_time=$(torsocks wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "${random_url}" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]") && debug "wget time WITH torsocks"
else
    readonly wget_time=$(wget -S --spider -t 1 --timeout=10 --max-redirect=0 --no-cookies --delete-after "${random_url}" 2>&1 | grep -i "Date:" | grep -o "[0-2][0-9]:[0-5][0-9]:[0-5][0-9]") && debug "wget time WITHOUT torsocks"
fi
[[ -z ${wget_time} ]] && echo "[ gerste ] error: could not get time from server.. please check network or configured domains" && exit 1
debug "wget_time = ${wget_time}"

# Get current systemtime
readonly current_time=$(date +%H:%M:%S)
debug "current systemtime: ${current_time}"

# Split wget_time into hours, minutes and seconds
IFS=':' read -ra time_array <<< "${wget_time}"
hours=${time_array[0]}
readonly minutes=${time_array[1]}
readonly seconds=${time_array[2]}


### CHECK FOR WINTERTIME
readonly current_timezone=$(date +%Z) && debug "current_timezone = \"${current_timezone}\""
[[ ${current_timezone} == "CET" ]] && readonly wintertime=true || readonly wintertime=false

# Check whether current timezone is set
[[ -z $(date +%Z) ]] && echo "[ gerste ] error: could not get current system timezone" && exit 1
debug "wintertime = \"${wintertime}\""


### INCREMENT "hours" IF wintertime=true
[[ ${wintertime} == true ]] && hours=$((${hours#0} + 1)) && debug "wintertime = ${wget_time} -> ${hours}:${minutes}:${seconds}" # remove leading "0" from hours to avoid some weird errors while incrementing in next line (i.e. "08:00:00" -> "8:00:00")
[[ ${wintertime} == true && ${hours} -eq 24 ]] && hours="00" && debug " > fixed wintertime format to ${hours}:${minutes}:${seconds}" # 24h formatfix (i.e. from "24:56:00" to "00:56:00")
[[ ${#hours} -eq 1 ]] && hours="0${hours}" && debug " > fixed wintertime format to ${hours}:${minutes}:${seconds}" # re-add leading "0" to hours (i.e. from "8:00:00" to "08:00:00")


### CHECK WHETHER wget_time DIFFERS TO CURRENT SYSTEMTIME
[[ ${wget_time} == "${current_time}" ]] && echo "[ gerste ] info: nothing to do here, time is correct already" && exit 0


### VALIDATE DATE FORMAT
date -d "${hours}:${minutes}:${seconds}" &> /dev/null
[[ ${?} -eq 1 ]] && echo "[ gerste ] error: invalid date format ${hours}:${minutes}:${seconds}" && exit 1


### CHECK IF ROOT (OR GET ROOT PERMISSIONS), SET NEW TIME AND EXIT
if [ ${EUID} == 0 ]; then
    debug "executing as root"
    date -s "${hours}:${minutes}:${seconds}" &> /dev/null
else
    [[ -z $(command -v doas) ]] && sudo date -s "${hours}:${minutes}:${seconds}" >> /dev/null || doas date -s "${hours}:${minutes}:${seconds}" >> /dev/null
fi
echo "Systemtime updated to ${hours}:${minutes}:${seconds}"
exit 0