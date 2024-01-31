#!/bin/bash
#
#      Name    : gerste-install-script
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
### ERROR HANDLING
set -E

### VERSION INFOS
readonly current_version="1.0.0"
readonly script_name="gerste-install"

### CHECK FOR ROOT
[[ ${EUID} != 0 ]] && echo "[ ${script_name} ] no root" && exit 1

### MOVE SCRIPT TO /usr/local/bin
if [[ -d /usr/local/bin ]]; then
    rm -f /usr/local/bin/gerste 
    cp ./gerste.sh /usr/local/bin/gerste >> /dev/null
    chmod 755 /usr/local/bin/gerste
else
    echo "[ ${script_name} ] error: /usr/local/bin does not exist" && exit 1
fi
