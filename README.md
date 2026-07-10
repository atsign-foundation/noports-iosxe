<!-- pyml disable-num-lines 4 md013,md033-->
<h1><a href="https://atsign.com#gh-light-mode-only">
   <img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a>
<a href="https://atsign.com#gh-dark-mode-only">
   <img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a></h1>

# NoPorts for Cisco IOS-XE

Open with intent - we welcome contributions - we want pull requests and to
hear about issues.

[NoPorts](https://docs.noports.com) on Cisco IOS-XE switches and routers via
[Application Hosting (IOx)](https://developer.cisco.com/app-hosting/): the
NoPorts device daemon (`sshnpd`) runs as a Docker container on the switch,
bridged to the management interface — giving operators SSH (plus, via `npt`,
gNMI/NETCONF/RESTCONF) access to the device with **no inbound listening
ports** on the management plane.

```text
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
Switch(config-app-hosting-docker)# end
Switch# app-hosting install appid noports package usbflash1:noports-iosxe.tar
Switch# app-hosting activate appid noports
Switch# app-hosting start appid noports
```

**New here? Start with the [Quickstart](QUICKSTART.md)** — full CLI
walkthrough from tarball to SSH session.

## Who is this for?

### Network operators

Grab `noports-iosxe.tar` from the
[releases page](https://github.com/atsign-foundation/noports-iosxe/releases),
copy it to the switch, configure app-hosting from the CLI, onboard with a
one-time passcode. You will need NoPorts atSigns for your devices; start at
[noports.com](https://noports.com).

### Contributors

[CONTRIBUTING.md](CONTRIBUTING.md) has the general guidance. Everything in
this repo except the IOx layer itself can be built and tested with nothing
but Docker — see [Development](#development).

## Supported platforms

| Platform | Status | Notes |
|---|---|---|
| Catalyst 9300/9400/9500/9600 | primary target | x86_64 IOx Docker apps; needs Cisco-certified SSD storage (USB 3.0 SSD on 9300, M2 SATA on 9400/9500H/9600) |
| Catalyst 8200/8300 | should work (untested) | x86_64 IOx Docker apps; install from `bootflash:`/`harddisk:` |
| IE3400 and other ARM platforms | not yet | need an arm64 image; the NoPorts release ships arm64 binaries (`ARCH=arm64 make fetch`), untested here |

Cisco requirements (see [References](#references)):

- **DNA Advantage licensing** — required for application hosting on
  Catalyst 9000.
- **Cisco-certified SSD storage** — on Catalyst 9300, apps run only from
  the 120 GB USB 3.0 SSD (`usbflash1:`); internal flash and front-panel
  USB sticks are not supported for app hosting.
- **IOS-XE with native Docker app support** — on Catalyst 9300 since
  IOS-XE 16.12.1; a plain `docker save` tarball installs directly, no
  ioxclient packaging needed (ioxclient remains an optional alternative if
  you want to set package-level defaults such as resource profiles).

## How it works

This repo packages the stock NoPorts release binaries into a small
`debian:bookworm-slim` image (the release binaries are glibc x86_64, so
Alpine/musl is out) and exports it with `docker save` as
`noports-iosxe.tar`, which IOS-XE installs directly.

| Piece | In the image | Purpose |
|---|---|---|
| `sshnpd` | `/usr/local/bin/sshnpd` | Stock NoPorts device daemon (pinned by [SSHNPD_VERSION](SSHNPD_VERSION)) |
| `at_activate` | `/usr/local/bin/at_activate` | APKAM enrollment (cuts keys on the switch) |
| [`entrypoint.sh`](docker/entrypoint.sh) | `/usr/local/bin/entrypoint.sh` | Maps run-opts env vars to sshnpd flags; waits for keys |
| [`onboard-noports.sh`](docker/onboard-noports.sh) | `/usr/local/bin/onboard-noports.sh` | One-time APKAM device enrollment |
| APKAM atKeys + atProtocol storage | `/data` (persistent) | Device identity; survives restart/upgrade |

Why not `FROM atsigncompany/sshnpd` (the official image)? It is built
`FROM scratch`: no shell for `app-hosting connect ... session`, no
`at_activate` for on-box enrollment, and it expects keys to already exist —
none of which fits the IOx workflow. The
[Dockerfile](docker/Dockerfile) documents this choice.

### Configuration: env vars in the app-hosting config

Unlike [NoPorts for SR Linux](https://github.com/atsign-foundation/noports-srlinux),
where NoPorts is modeled in the router's own YANG config tree, **IOS-XE has
no mechanism for third parties to extend its configuration schema** — there
is no YANG/CLI extension point for guest applications. The honest
equivalent on IOS-XE is the app-hosting `run-opts` docker options: they are
part of the switch running-config (so they persist in the startup config
and replay on reboot), but they are opaque strings to IOS, not modeled
leaves — no validation, no telemetry of NoPorts state via gNMI.

| Env var | Required | sshnpd flag | Example |
|---|---|---|---|
| `DEVICE_ATSIGN` | yes | `--atsign` | `@mydevice` |
| `MANAGER_ATSIGN` | yes | `--managers` (comma-separated OK) | `@manager` |
| `DEVICE_NAME` | yes | `--device` | `cat9k-1` |
| `ROOT_SERVER` | no | `--root-server` | `proxy:proxy0001.atsign.org:443` |
| `PERMIT_OPEN` | no | `--permit-open` | `172.19.0.1:22,172.19.0.1:57400` |
| `SSHPUBLICKEY` | no | `--sshpublickey` (if `true`) | `true` |
| `EXTRA_ARGS` | no | appended verbatim | `-v` |

(sshnpd also supports `--config <yaml>`; this integration deliberately uses
flags derived from env vars instead, because run-opts env vars are the
native IOx configuration surface and keep the whole config in
`show running-config`.)

### Networking

`app-vnic management guest-interface 0` bridges the container onto the
switch management interface (Mgmt-vrf): the container gets a Layer 3
address **on the same subnet as the management interface**, with
`app-default-gateway` and `name-server0` providing its gateway and DNS.
All NoPorts traffic is **outbound** from that address — nothing listens.

Because the daemon runs in a container rather than on the switch itself,
"localhost" is the container. Point `PERMIT_OPEN` at the switch's own
management IP to reach IOS services (SSH 22, gNMI 57400, NETCONF 830), and
connect with `npt`/`sshnp` as shown in the [Quickstart](QUICKSTART.md).

### Persistent storage: keys survive restart and upgrade

`run-opts 1 "-v $(APP_DATA):/data"` mounts the app's IOx persistent
app-data directory (on the SSD) at `/data` in the container. The
entrypoint sets `HOME=/data`, so the APKAM atKeys and all atProtocol state
live there. Per Cisco's app-hosting documentation, an app's persistent
data is retained across stop/deactivate cycles and `app-hosting upgrade`;
`app-hosting uninstall` removes it (re-onboard after an uninstall).
**Not yet verified on hardware** — see the test plan in the
[Quickstart](QUICKSTART.md).

## Installation

Grab `noports-iosxe.tar` from the
[releases page](https://github.com/atsign-foundation/noports-iosxe/releases)
(or build it yourself: `make fetch tar`), copy it to the switch storage
(`usbflash1:` on Catalyst 9300), then follow the
[Quickstart](QUICKSTART.md) for the full CLI walkthrough: enable `iox`,
configure the app, `install`/`activate`/`start`, and onboard.

### Onboard the device with APKAM (no atKeys files copied around)

Enrollment cuts new, scope-limited APKAM keys **on the switch**; the full
atKeys file for the device atSign never leaves the administrator's custody.

On the admin machine (any host with an authorized key for `@mydevice`):

```bash
at_activate otp -a @mydevice
```

On the switch, drop into the container and run the onboard script:

```text
Switch# app-hosting connect appid noports session
/ # onboard-noports.sh <passcode>
```

While it waits, approve from the admin machine:

```bash
at_activate approve -a @mydevice --arx noports --drx cat9k-1
```

The entrypoint detects the new keys within ~15 seconds and starts sshnpd —
`show app-hosting detail appid noports` and the app logs show it running.

### Connect from anywhere

```bash
# SSH to the switch management IP via the tunnel:
npt -f @manager -t @mydevice -d cat9k-1 -r 172.19.0.1 -p 22 -l 2222
ssh -p 2222 admin@localhost

# or tunnel gNMI without SSH (requires 172.19.0.1:57400 in PERMIT_OPEN):
npt -f @manager -t @mydevice -d cat9k-1 -r 172.19.0.1 -p 57400 -l 57400
gnmic -a localhost:57400 -u admin --skip-verify capabilities
```

## Restricted egress (management-plane ACLs)

By default the atProtocol dials the atDirectory on `root.atsign.org:64`
and atServers on assorted high ports — typically blocked by management VRF
ACLs. The `proxy:` root-server form skips the directory lookup and sends
**all** atProtocol traffic to one reverse proxy on one port:

```text
run-opts 3 "-e ROOT_SERVER=proxy:proxy0001.atsign.org:443"
```

Both the daemon and APKAM enrollment honor it (set it **before**
onboarding, so enrollment traffic uses it too). Clients use the equivalent
flag, picking a relay with `-r`:

```bash
sshnp -f @manager -r @rv_oc -t @mydevice -d cat9k-1 \
  --root-domain "proxy:proxy0001.atsign.org:443"
```

Note: the proxy covers atProtocol (control-plane) traffic. The session data
path is a separate outbound connection from the switch to the relay chosen
by the client (`-r`), so a 443-only egress policy also needs a relay
reachable on 443.

## Fleet-scale access control: policy atSigns

Listing manager atSigns per switch works for a handful of devices, but at
fleet scale it means touching every device's app-hosting config to grant
or revoke an operator's access. A **policy atSign** centralizes that
decision: the daemon delegates each incoming request to a
[NoPorts Policy Service](https://docs.noports.com) running as that atSign,
which answers allow/deny based on centrally-managed rules.

```text
app-hosting appid noports
 app-resource docker
  run-opts 2 "-e DEVICE_ATSIGN=@mydevice -e POLICY_ATSIGN=@policy_np -e DEVICE_NAME=cat9k-1 -e DEVICE_GROUP=access-switches"
```

At least one of `MANAGER_ATSIGN` / `POLICY_ATSIGN` must be set:

- **`POLICY_ATSIGN` only** — every request is decided by the policy
  service; the switch config never changes as staff or entitlements
  change. NoPorts' `permit-open` default also shifts from
  `localhost:22,localhost:3389` to `*:*`, deferring port restrictions to
  policy.
- **both** — atSigns in `MANAGER_ATSIGN` get direct access (policy is not
  consulted for them); everyone else is checked against the policy
  service. Useful as a break-glass list alongside central control.

`DEVICE_GROUP` is sent to the policy service with each request, so rules
can target groups (e.g. "campus NOC may reach `access-switches` on port
22") instead of individual devices.

## Development

Nothing but Docker needed:

```bash
make fetch    # stage pinned sshnpd + at_activate in build/
make image    # docker build (linux/amd64)
make tar      # docker save > build/noports-iosxe.tar
make lint     # shellcheck + hadolint (via Docker)
make smoke    # run the image, assert the awaiting-onboarding state
make clean
```

There is no free IOS-XE image, so CI cannot exercise the IOx layer; the
smoke test runs the exact container a switch would, and
[QUICKSTART.md](QUICKSTART.md#manual-on-device-test-plan) has the manual
on-device test plan. The pinned sshnpd release lives in
[SSHNPD_VERSION](SSHNPD_VERSION) and is bumped automatically by CI when
NoPorts publishes a new release.

## Roadmap

- **Done:** Docker image with env-driven entrypoint, on-switch APKAM
  enrollment via `app-hosting connect`, proxy-mode (443-only) egress,
  docker-save tarball builds, container smoke test in CI, automated
  upstream sshnpd bumps.
- **Next:** hardware validation on Catalyst 9300 (install, persistence
  across restart/upgrade, Mgmt-vrf egress), Catalyst 8300 validation.
- **Later:** arm64 image for IE3400/IR1101, AppGigabitEthernet
  (front-panel/data-port) deployment variant, fleet onboarding at scale
  (SPP passcodes + `at_activate auto` approval).

## References

CLI syntax and platform requirements in this README were verified against:

- [Cisco Programmability Configuration Guide, IOS XE 17.11.x — Application Hosting](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/prog/configuration/1711/b_1711_programmability_cg/m_1711_prog_app_hosting.html)
  (app-hosting config/lifecycle CLI, `run-opts`, `$(APP_DATA)` volume,
  `app-hosting connect appid ... session`, SSD-only storage rules)
- [Application Hosting on the Cisco Catalyst 9000 Series Switches (white paper)](https://www.cisco.com/c/en/us/products/collateral/switches/catalyst-9300-series-switches/white-paper-c87-742415.html)
  (docker-save deployment without ioxclient, DNA Advantage license
  requirement, per-platform CPU/memory/storage resources)
- [Cisco DevNet: Application Hosting on Catalyst switches](https://developer.cisco.com/docs/app-hosting/)

## Maintainers

Created by Atsign. Original author:
[Colin Constable](https://github.com/cconstab) ([@colin](https://atsign.com)).
Issues and pull requests are welcome — they are triaged weekly.
