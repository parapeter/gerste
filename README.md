# :watch: GERSTE (GERman-Secure-Timesync-Execution)

<img src="https://i.ibb.co/DbXkYy3/barley-field-8230-960-720.jpg" width="300" height="200">

This tiny bash-script updates your systemtime. It uses `wget` through `torsocks` to obtain the header response of a given domain (without downloading the website), after that it `grep`'s the timestamp and, based on whether it's summer- or wintertime, this script automatically updates the systemtime correctly with `date`. By default `gerste` sends traffic through `tor`, but you can run without (see below: :gear: [Configuration](https://github.com/paranoidpeter/gerste#gear-configuration)). This script may be useful for other countries¹ since not only Germany changes clocktime twice a year. Without keeping this in mind, the first impulse for a good name was `gerste` (maybe because of the association to beer?).

¹ all countries in CET- or CEST-Timezone. Otherwise change timezone if needed (see below: :gear: [Configuration](https://github.com/paranoidpeter/gerste#gear-configuration)).

This script was highly inspired by [secure-time-sync](https://github.com/Obscurix/Obscurix/blob/master/airootfs/usr/lib/obscurix/secure-time-sync).

## :hammer_and_wrench: Preparation

1. Make sure your user is configured to use sudo or doas (if not root)
2. Make sure /etc/localtime is set correctly

```bash
  > ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
```

3. Install and enable dependencies

```bash
  > pacman -S wget tor torsocks shuf date
  > systemctl enable tor.service
```

## :cd: Installation

#### Install to use in terminal:

```bash
  > git clone https://github.com/paranoidpeter/gerste/XX
  > cd gerste
  > sudo chmod 755 gerste.sh
  > sudo cp gerste.sh /usr/local/bin/gerste
```

#### Enable automatic timesync (systemd)

Create gerste.timer:

```bash
  > nano /usr/lib/systemd/system/gerste.timer
```

```
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

```
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
  > systemctl daemon-reload
  > systemctl enable --now gerste.timer
```

#### Create pacman hook:

> [!IMPORTANT]
> This hook will execute after downloading so it's useless maybe.

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


## :rocket: Usage
After installation you can simply type:
```bash
  > gerste
```
> [!NOTE]
> Run without root privileges is possible. You will prompted for sudo or doas password since changing systemtime is not supported for unprivileged users.


## :gear: Configuration
Open the script with a texteditor:

```bash
  > sudo nano /usr/local/bin/gerste
```

You can:

1. Add or delete urls which `wget` will access:<br/>1\.1. Change the values of `server_urls=( archlinux.org [...] )` and make sure **at least one url** is configured
2. Using this script **without** `tor`:<br />2\.1. Comment the last three if-statements below `### CHECK DEPENDENCIES` which  contains `tor`, `torsocks` and `tor.service` <br />2\.2. Change lines after `### URL HANDLING`. Uncomment line below `# No Tor` and comment line below `# Tor (default)`<br />2\.3. Change lines after `### GET TIME VIA CURL`. Uncomment line below `# No Tor` and comment line below `# Tor (default)`<br />2\.4. Make sure all tor-urls are removed from `server_urls=( archlinux.org [...] )`
3. Use another timezone:<br />3\.1. Change the value in if-statement below `### CHECK FOR WINTERTIME` from `CET` to your preference.

## :interrobang: Why

I've started this script because of an article which claims ntp as an insecure protocoll and well... why not. However, since I'm affected by the "summer-winter-time-switching-model" the most public scripts like this won't work for me out of the box. So, I've decided to write my own script with some extra stuff.

## :envelope: Contact

Mail: peterparanoid@proton.me
