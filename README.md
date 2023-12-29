# :watch: GERSTE (GERman-Secure-Timesync-Execution)
<img src="https://i.ibb.co/DbXkYy3/barley-field-8230-960-720.jpg" width="300" height="200">

This tiny script updates the systemtime of your linux machine. It uses ```curl``` to get the header-response of a website, then ```grep``` the time of it and whether it's summer or wintertime the scripts automatically uses ```date -s``` to update the systemtime. By default ```curl``` will use ```tor```. You can it run without ```tor``` (see below: :gear: Configuration). This script may be useful for other countries since not only germany is changing the time once a year, but the first impulse for the name was ```gerste``` without keeping that in mind (maybe because I like beer?).

## :hammer_and_wrench: Preparation
 1. Make sure your user is configured to use sudo or doas (if not root)
 2. Install dependencies:
```bash
  > ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
  > pacman -S curl shuf date tor
  > systemctl enable tor.service
```

## :cd: Installation
#### Install to use it in terminal:
```bash
  > git clone https://github.com/paranoidpeter/gerste/XXX
  > cd gerste
  > sudo chmod 755 gerste.sh
  > sudo cp gerste.sh /usr/local/bin/gerste
```
#### Enable automatic execution (systemd)
Create gerste.timer:
```bash
  > nano /usr/lib/systemd/system/gerste.timer
```
```bash
  [Unit]
  Description=Run gerste every 3min

  [Timer]
  OnCalendar=*:0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57
  Persistent=true

  [Install]
  WantedBy=timers.target
```
Create gerste.service:
```bash
  > nano /usr/lib/systemd/system/gerste.service
```
```bash
  [Unit]
  Description=Run gerste for automatic timesync

  [Service]
  Type=oneshot
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
Enable timer:
```bash
  > systemctl enable gerste.timer
```

#### Create a pacman hook:
```bash
  > nano /etc/pacman.d/hooks/gerste.hook
```
```bash
  [Trigger]
  Operation = Install
  Operation = Upgrade
  Operation = Remove
  Type = Package
  Target = *

  [Action]
  Description = gerste timesyncing
  When = PreTransaction
  Exec = /bin/sh -c '/usr/local/bin/gerste'
  AbortOnFail
```


## :gear: Configuration
You can:
  1. Add or delete urls which ```curl``` will access.<br>
     🠒 Change the values of ```server_urls=( archlinux.org [...] )``` and make sure **at least one url** is configured.<br>
  2. Using this script **without** ```tor```<br>
     🠒 Uncomment Line after "# No Tor" and comment line after "# Tor (default)"<br>
```bash
  > sudo nano /usr/local/bin/gerste
```

## :interrobang: Why
I've started this script because of an article which claims ntp as an insecure protocoll and because of... why not. However, since I'm affected by the "summer-winter-time-switching-model" the most public scripts like this won't work for me out of the box. So I've decided to do it on my own.
