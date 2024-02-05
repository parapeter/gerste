#!/bin/bash
#    
#      Name    : gerste-uninstall
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
set -e

# Version infos and paths
readonly SCRIPT_NAME="gerste-uninstall"

# Echo helpers
function error { echo "[ ${SCRIPT_NAME} ] error: ${1}"; }
function info { echo "[ ${SCRIPT_NAME} ] info: ${1}"; }

# Check root permissions
[[ ${EUID} != 0 ]] && error "no root" && exit 1


### UNINSTALL OPERATION
if [[ -f /usr/local/bin/gerste ]]; then
    rm -f /usr/local/bin/gerste
else
    error "Nothing to do here.." && exit 0
fi

info "Uninstall complete!"
exit 0