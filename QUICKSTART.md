# Quickstart

Zero to an SSH session with no open ports, on a Catalyst 9000 switch.

## What you need first

- Two atSigns: one for the switch (e.g. `@mydevice`) and one for you as the
  manager (e.g. `@manager`) — get them at [noports.com](https://noports.com)
- The manager atSign activated on your own machine, with the NoPorts client
  installed ([client install guide](https://docs.noports.com))
- A Catalyst 9000 switch with:
  - **DNA Advantage** licensing
  - a **Cisco-certified SSD** for app hosting (USB 3.0 SSD / `usbflash1:`
    on Catalyst 9300; M2 SATA on 9400/9500H/9600) — internal flash and
    front-panel USB sticks are not supported
  - IOS-XE with native Docker app support (16.12.1+ on Cat9300; a recent
    17.x train is recommended)
- `noports-iosxe.tar` from the
  [releases page](https://github.com/atsign-foundation/noports-iosxe/releases),
  or build it yourself (needs only Docker):

  ```bash
  git clone https://github.com/atsign-foundation/noports-iosxe.git
  cd noports-iosxe
  make fetch tar          # build/noports-iosxe.tar
  ```

## 1. Copy the tarball to the switch

Any file-transfer method works, e.g. from the switch:

```text
Switch# copy scp://you@yourhost/noports-iosxe.tar usbflash1:
```

(or stage it on `flash:`/`bootflash:` and install from there — the app
itself always runs from the SSD.)

## 2. Enable IOx and configure the app

```text
Switch# configure terminal
Switch(config)# iox
Switch(config)# app-hosting appid noports
Switch(config-app-hosting)# app-vnic management guest-interface 0
Switch(config-app-hosting-mgmt-gateway)# guest-ipaddress 172.19.0.24 netmask 255.255.255.0
Switch(config-app-hosting-mgmt-gateway)# exit
Switch(config-app-hosting)# app-default-gateway 172.19.0.1 guest-interface 0
Switch(config-app-hosting)# name-server0 8.8.8.8
Switch(config-app-hosting)# app-resource docker
Switch(config-app-hosting-docker)# run-opts 1 "-v $(APP_DATA):/data"
Switch(config-app-hosting-docker)# run-opts 2 "-e DEVICE_ATSIGN=@mydevice -e MANAGER_ATSIGN=@manager -e DEVICE_NAME=cat9k-1"
Switch(config-app-hosting-docker)# run-opts 3 "-e PERMIT_OPEN=172.19.0.1:22,172.19.0.1:57400"
Switch(config-app-hosting-docker)# end
Switch# write memory
```

Adjust for your network:

- `guest-ipaddress` — a free address **on the management interface's
  subnet** (the vNIC is bridged to Mgmt-vrf)
- `app-default-gateway` — the management network gateway
- `name-server0` — a DNS server reachable from the management network
- `PERMIT_OPEN` — the switch's **own management IP** plus each port clients
  may tunnel to (22 = SSH, 57400 = gNMI, 830 = NETCONF). "localhost" would
  be the container, not the switch.
- run-opts changes take effect only after
  `stop` / `deactivate` / `activate` / `start`.

Behind a locked-down management VRF? Add proxy mode **before** onboarding
(see [Restricted egress](README.md#restricted-egress-management-plane-acls)):

```text
run-opts 4 "-e ROOT_SERVER=proxy:proxy0001.atsign.org:443"
```

## 3. Install, activate, start

```text
Switch# app-hosting install appid noports package usbflash1:noports-iosxe.tar
Switch# app-hosting activate appid noports
Switch# app-hosting start appid noports
Switch# show app-hosting list
App id                                   State
---------------------------------------------------------
noports                                  RUNNING
```

The app is now waiting for its keys — the log
(`show app-hosting detail appid noports`, or the container output via
`app-hosting connect appid noports session` then reading the entrypoint
message) shows `awaiting-onboarding`.

## 4. Onboard the switch with APKAM

Enrollment cuts new, scope-limited APKAM keys **on the switch**; the full
atKeys file for the device atSign never leaves your custody.

```bash
# on your machine: generate a one-time passcode for the device atSign
at_activate otp -a @mydevice
```

```text
Switch# app-hosting connect appid noports session
/ # onboard-noports.sh <passcode>
```

```bash
# back on your machine, while the switch waits: approve the enrollment
at_activate approve -a @mydevice --arx noports --drx cat9k-1
```

The entrypoint detects the keys within ~15 seconds and starts sshnpd. The
keys live on the app's persistent data volume (`/data`), so they survive
container restarts and `app-hosting upgrade`.

## 5. Connect — from your machine, anywhere on the internet

```bash
# SSH to the switch management IP through the tunnel:
npt -f @manager -t @mydevice -d cat9k-1 -r 172.19.0.1 -p 22 -l 2222
ssh -p 2222 admin@localhost
```

Bonus — tunnel gNMI without SSH (requires `172.19.0.1:57400` in
`PERMIT_OPEN`, and gNMI enabled on the switch):

```bash
npt -f @manager -t @mydevice -d cat9k-1 -r 172.19.0.1 -p 57400 -l 57400
gnmic -a localhost:57400 -u admin --skip-verify capabilities
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `iox` config rejected / IOx never comes up | `show iox-service` — needs DNA Advantage licensing and, on Cat9300, the USB 3.0 SSD present. `show app-hosting resource` shows what IOx sees. |
| `app-hosting install` fails: storage | Apps run only from Cisco-certified SSD storage (`usbflash1:` on 9300). Internal flash / front-panel USB are not supported. Check `dir usbflash1:` and that the SSD is ext4-formatted. |
| Install fails on the tarball | The tar must be a `docker save` export of a **linux/amd64** image (`make tar` does this). Check `show logging` and `show app-hosting detail appid noports` for the parse error. |
| `DEPLOYED` but activate fails | Resource shortfall — `show app-hosting resource`. Try again after freeing resources, or define a smaller custom profile: `app-resource profile custom` (`cpu`/`memory` under it). |
| App state stuck / cycling (`show app-hosting list`) | Read the container output: `app-hosting connect appid noports session`, the entrypoint logs to stdout (also in `show app-hosting detail appid noports`). Missing env vars exit with a message naming them. |
| Entrypoint says `missing required environment variable` | Add the `run-opts` lines (step 2), then `app-hosting stop` / `deactivate` / `activate` / `start` — run-opts only apply on (re)activation. |
| `awaiting-onboarding` forever after enrollment | Confirm the keys landed on the persistent volume: in the session shell, `ls /data/keys/`. If empty, re-run `onboard-noports.sh`. If the volume mount is missing (`run-opts 1 "-v $(APP_DATA):/data"`), keys were written to the container layer and are lost on restart. |
| Onboard script hangs then fails | Enrollment wasn't approved in time — check from your machine with `at_activate list -a @mydevice -s pending`, approve, re-run. If it never reaches the atServer, test egress from the session shell (e.g. `sshnpd --help` works but the network doesn't): check gateway/DNS config, then use proxy mode. |
| No DNS in the container | `name-server0` missing from the app-hosting config, or the DNS server isn't reachable from the management subnet. |
| Daemon runs but `sshnp`/`npt` can't connect | Client must use the same device name (`-d cat9k-1`), the manager atSign must be in `MANAGER_ATSIGN`, the target `-r <ip> -p <port>` must be listed in `PERMIT_OPEN`, and (behind strict ACLs) the relay chosen with `-r` (client-side flag) must be reachable outbound from the switch. |
| Keys gone after `app-hosting uninstall` | Expected: uninstall removes the app's persistent data. Revoke the old enrollment (`at_activate revoke`) and onboard again after reinstalling. |
| Re-enrolling a device | Delete the key file under `/data/keys/`, revoke the old enrollment (`at_activate revoke`), and run the onboard script again. |

## Manual on-device test plan

CI cannot run IOS-XE (no free image), so these need a real switch — please
report results in an issue:

1. **Install path**: `make fetch tar`, copy to `usbflash1:`, steps 2–3
   above; expect `RUNNING` in `show app-hosting list`.
2. **Env validation**: start with a missing `DEVICE_ATSIGN`; expect the app
   to stop with the missing-env message in the logs.
3. **Onboarding**: step 4; expect keys in `/data/keys/` and sshnpd startup
   in the logs within ~15 s of approval.
4. **Connectivity**: step 5 (SSH and gNMI); expect working tunnels.
5. **Persistence**: `app-hosting stop`/`start`, then
   `deactivate`/`activate`, then `app-hosting upgrade appid noports
   package usbflash1:noports-iosxe.tar` with a new tarball; expect **no
   re-onboarding** — sshnpd starts straight away each time.
6. **Reboot**: reload the switch; expect the app to auto-start and sshnpd
   to come up without touching the CLI.
7. **Proxy mode**: apply a 443-only egress ACL to Mgmt-vrf, set
   `ROOT_SERVER=proxy:proxy0001.atsign.org:443`, re-onboard; expect
   enrollment and daemon traffic to pass, and note the relay caveat in the
   [README](README.md#restricted-egress-management-plane-acls).
