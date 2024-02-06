#!/bin/bash
#
#      Name    : gerste-install
#      Version : 1.1.0
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
set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# Version infos
readonly SCRIPT_NAME="gerste-install"
readonly VERSION="1.1.0"

# Echo helpers
function error { echo "[ ${SCRIPT_NAME} ] error: ${1}"; }
function info { echo "[ ${SCRIPT_NAME} ] info: ${1}"; }

# Parameter handling
uninstall_mode=false
for parameter in "$@"; do
    case "$parameter" in
        -u|--uninstall)
            uninstall_mode=true
            ;;
        -v|--version)
            echo "${SCRIPT_NAME}-${VERSION}" && exit 0
            ;;
        -*)
            echo "[ ${SCRIPT_NAME} ] error: illegal parameter ${parameter}" && exit 1
            ;;
    esac
done

### CHECK FOR ROOT
[[ ${EUID} != 0 ]] && error "no root" && exit 1

### (UN)INSTALL OPERATIONS
# Uninstall with parameter -u/--uninstall
if [[ "$uninstall_mode" == true ]]; then
    rm --force /usr/local/bin/gerste && info "deletion complete" && exit 0
fi

# Search for current version and ask for deletion
if [[ -f /usr/local/bin/gerste ]]; then
    info "found existing version"
    read -rp "[ ${SCRIPT_NAME} ] delete current version? [Y/n]: " ask_for_delete;
    case "$ask_for_delete" in
        [Nn]*)
            mv /usr/local/bin/gerste /usr/local/bin/gerste_backup
            info "created backup of current version at /usr/local/bin/gerste_backup"
            ;;
        *)
            rm --force /usr/local/bin/gerste
            info "deleted current version"
            ;;
    esac
fi

# Install
cp ./gerste.sh /usr/local/bin/gerste &> /dev/null
chmod 755 /usr/local/bin/gerste &> /dev/null # Change permission to: rwxr-xr-x

info "Installation complete! Make sure that /usr/local/bin is in your PATH enviroment"
exit 0