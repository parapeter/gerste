#!/bin/bash
#
#      Name    : gerste-install
#      Version : 1.0.0
#      License : GNU General Public License v3.0 (https://www.gnu.org/licenses/gpl-3.0)
#      GitHub  : https://github.com/paranoidpeter/script_name
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
# Error handling
set -E

# Version infos
readonly script_name="gerste-install"

# Echo helpers
function error { echo "[ ${script_name} ] error: ${1}"; }
function info { echo "[ ${script_name} ] info: ${1}"; }

### CHECK FOR ROOT
[[ ${EUID} != 0 ]] && error "no root" && exit 1

### INSTALL OPERATIONS
# Delete current version
if [[ -f /usr/local/bin/gerste ]]; then
    rm -f /usr/local/bin/gerste
    [[ ${?} -eq 1 ]] && error "could not remove current version.. please delete manually and try again" && exit 1
fi

# Check for /usr/local/bin and install
if [[ -d /usr/local/bin ]]; then
    
    cp ./gerste.sh /usr/local/bin/gerste &> /dev/null
    [[ ${?} -eq 1 ]] && error "could not copy to /usr/local/bin.. please copy manually and change permissions" && exit 1
    
    chmod 755 /usr/local/bin/gerste &> /dev/null
    [[ ${?} -eq 1 ]] && error "could not change permissions.. please do it manually for /usr/local/bin/gerste" && exit 1

else
    error "/usr/local/bin does not exist" && exit 1
fi

info "Installation complete! Make sure that /usr/local/bin is in your PATH enviroment"
exit 0