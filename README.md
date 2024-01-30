# :ear_of_rice: GERSTE (GERman-Secure-Timesync-Execution)

<img src="https://i.ibb.co/DbXkYy3/barley-field-8230-960-720.jpg" width="300" height="200">

![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black) ![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white) <br>
![Badge License](https://img.shields.io/badge/License-GPL3-015d93.svg?style=for-the-badge&labelColor=blue)

This tiny bash script updates your system- and hardware clock. It uses  `wget`  (optionally through  `torsocks` ) to obtain the header of a given domain (without downloading the website), after that it `grep`s the timestamp and, based on whether it's summer- or wintertime, it automatically updates the systemtime correctly with `date`. By default, `gerste` sends traffic through clearnet (to use `tor` &rarr; see below: :rocket: [Usage](https://github.com/paranoidpeter/gerste#rocket-usage)).

This script may be useful for other countries¹ since not only Germany changes clocktime twice a year. Without keeping this in mind, the first impulse for a good name was `gerste` (maybe because of the association to beer?).

¹ all countries in the CET/CEST-Timezone. Otherwise change the timezone if needed (see below: :gear: [Configuration](https://github.com/paranoidpeter/gerste#gear-configuration)).

I got inspired by [secure-time-sync](https://github.com/Obscurix/Obscurix/blob/master/airootfs/usr/lib/obscurix/secure-time-sync) to write this script.

## :hammer_and_wrench: Preparation

1. The executing user needs root access (or sudo/doas)
2. Make sure that `/etc/localtime` is set correctly

```bash
  > ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
```

3. Install dependencies

```bash
  > pacman -S wget shuf date
```

4. **Optional:** Install and enable dependencies for torsocks
```bash
  > pacman -S tor torsock
  > systemctl enable tor.service
```

## :cd: Installation

### Install to use in terminal

```bash
  > git clone https://github.com/paranoidpeter/gerste/
  > cd gerste
  > sudo chmod 755 gerste.sh
  > sudo cp gerste.sh /usr/local/bin/gerste
```

*(Make sure this step is done before enable automatic timesync options below)* <br>
### Enabling automatic timesync on network connection (NetworkManager)

#### Create a NetworkManager dispatch script

```bash
  > nano /etc/NetworkManager/dispatcher.d/01-gerste
```

```bash
#!/bin/bash
case "$2" in
  up)
    /usr/local/bin/gerste
    ;;
esac
```

> [!NOTE]
> This dispatch script executes once after network is up. *(For further information or to change behavior see: [NetworkManager-dispatcher(8)](https://man.archlinux.org/man/NetworkManager-dispatcher.8))*

#### Enable the NetworkManager dispatch script

```bash
  > chmod 744 /etc/NetworkManager/dispatcher.d/01-gerste
  > chown root:root /etc/NetworkManager/dispatcher.d/01-gerste
  > systemctl restart NetworkManager
```

### Enable automatic timesync every X minutes (systemd timer)

#### Create gerste.timer (i.e. every 5min)

```bash
  > nano /usr/lib/systemd/system/gerste.timer
  > chmod 640 /usr/lib/systemd/system/gerste.timer
```

```
[Unit]
Description=Run gerste every 5min

[Timer]
OnCalendar=*:0,5,10,15,20,25,30,35,40,45,50,55
Persistent=true

[Install]
WantedBy=timers.target
```

#### Create gerste.service

```bash
  > nano /usr/lib/systemd/system/gerste.service
  > chmod 640 /usr/lib/systemd/system/gerste.service
```

```
[Unit]
Description=Run gerste for automatic timesync
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gerste
# Some Sandboxing:
ProtectProc=invisible
ProcSubset=pid
PrivateTmp=yes
ProtectHostname=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
```

#### Enable gerste.timer

```bash
  > systemctl daemon-reload
  > systemctl enable --now gerste.timer
```

## :gear: Configuration

Open the script with nano:

```bash
  > nano /usr/local/bin/gerste
```

You can:

1. Add or delete URLs which `wget` will trigger:<br/>
:exclamation: **IMPORTANT** :exclamation: Different web servers can give different datestamps, your systemtime **can** differ more than 10 seconds on every execution. By default only 1 url is given to avoid such a behaviour.<br/>
1.1. Change the value of `server_urls=( example.onion )` or `server_urls=( example.org )` and make sure **at least one url** is configured. `server_urls` is a space separated list.<br/>

2. Use another timezone:<br />3\.1. Change the value in if-statement below `### CHECK FOR WINTERTIME` from `CET` to your preference. **It needs to be your winter-time-zone to keep functionality**.

## :rocket: Usage
After installation you can simply type:
```bash
  > gerste
```
> [!NOTE]
> Run without root privileges is possible. You will be prompted for sudo or doas password since changing systemtime is not supported for unprivileged users.

#### Command overview:

```bash
Use gerste WITHOUT tor:
  > gerste

Use gerste WITH tor:
  > gerste -t 
  > gerste --tor

Get current version:
  > gerste -v
  > gerste --version
```

## :beetle: Debugging

#### Enable debugging with "-d" or "--debug" parameter

```bash
  > gerste -d
  > gerste --debug
```
If you need a more verbose debugging output you can add simple debug lines in script &rarr; debug "text"

## :interrobang: Why

I've started this script because of a random article which claims ntp as an insecure protocol. However, since I'm affected by the "summer-winter-time-switching-model" the most public scripts like this won't work for me out of the box. So, I've decided to write my own script with some extras.

## :envelope: Contact

Mail: peterparanoid@proton.me
