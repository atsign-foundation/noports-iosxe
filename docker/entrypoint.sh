#!/usr/bin/env bash
# Entrypoint for the NoPorts IOx container on Cisco IOS-XE.
#
# Configuration arrives as environment variables set with docker run-opts
# in the app-hosting config (they persist in the switch running-config):
#
#   app-hosting appid noports
#    app-resource docker
#     run-opts 1 "-v $(APP_DATA):/data"
#     run-opts 2 "-e DEVICE_ATSIGN=@mydevice -e MANAGER_ATSIGN=@manager"
#     run-opts 3 "-e DEVICE_NAME=cat9k-1"
#
# Required:  DEVICE_ATSIGN  DEVICE_NAME
#            plus at least one of MANAGER_ATSIGN / POLICY_ATSIGN
# Optional:  POLICY_ATSIGN  (atSign of a NoPorts Policy Service that decides
#                            access requests centrally — the right choice
#                            for large fleets; if both are set, atSigns in
#                            MANAGER_ATSIGN bypass the policy check)
#            DEVICE_GROUP   (device group name, sent to the policy service
#                            with each request so rules can target groups,
#                            e.g. access-switches)
#            ROOT_SERVER    (e.g. proxy:proxy0001.atsign.org:443)
#            PERMIT_OPEN    (comma-separated host:port list the clients may
#                            request, e.g. 172.19.0.1:22,172.19.0.1:57400)
#            SSHPUBLICKEY   (true/false: accept ssh public keys from clients)
#            EXTRA_ARGS     (extra sshnpd flags, appended verbatim)
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
KEYS_DIR="${DATA_DIR}/keys"

log() { echo "noports: $*"; }

MISSING=""
for VAR in DEVICE_ATSIGN DEVICE_NAME; do
    if [ -z "${!VAR:-}" ]; then
        MISSING="${MISSING} ${VAR}"
    fi
done
if [ -z "${MANAGER_ATSIGN:-}" ] && [ -z "${POLICY_ATSIGN:-}" ]; then
    MISSING="${MISSING} MANAGER_ATSIGN-or-POLICY_ATSIGN"
fi
if [ -n "$MISSING" ]; then
    log "ERROR: missing required environment variable(s):${MISSING}" >&2
    log "Set them with docker run-opts in the app-hosting config, e.g.:" >&2
    log '  app-hosting appid noports' >&2
    log '   app-resource docker' >&2
    # shellcheck disable=SC2016 # $(APP_DATA) is literal IOS-XE CLI syntax
    log '    run-opts 1 "-v $(APP_DATA):/data"' >&2
    log '    run-opts 2 "-e DEVICE_ATSIGN=@mydevice -e MANAGER_ATSIGN=@manager -e DEVICE_NAME=cat9k-1"' >&2
    log "then: app-hosting stop / deactivate / activate / start appid noports" >&2
    exit 1
fi

# All sshnpd/at_activate state (atKeys, atProtocol storage) lives under
# /data, which the app-hosting config maps to the IOx persistent app-data
# directory — so device identity survives container restart and upgrade.
export HOME="$DATA_DIR"
mkdir -p "$KEYS_DIR"
KEY_FILE="${KEY_FILE:-${KEYS_DIR}/${DEVICE_ATSIGN}_key.atKeys}"

# Snapshot the config for onboard-noports.sh, so the onboarding session
# works even if `app-hosting connect` does not inherit this environment.
{
    echo "DEVICE_ATSIGN='${DEVICE_ATSIGN}'"
    echo "DEVICE_NAME='${DEVICE_NAME}'"
    echo "ROOT_SERVER='${ROOT_SERVER:-}'"
    echo "KEY_FILE='${KEY_FILE}'"
} > "${DATA_DIR}/noports.env"

if [ ! -f "$KEY_FILE" ]; then
    log "waiting for atKeys: ${KEY_FILE} not found (state: awaiting-onboarding)"
    log "Onboard this device with APKAM enrollment:"
    log "  1. on an admin machine:   at_activate otp -a ${DEVICE_ATSIGN}"
    log "  2. on the switch:         app-hosting connect appid noports session"
    log "     in the container:      onboard-noports.sh <passcode>"
    log "  3. on the admin machine:  at_activate approve -a ${DEVICE_ATSIGN} --arx noports --drx ${DEVICE_NAME}"
    while [ ! -f "$KEY_FILE" ]; do
        sleep 15
        log "still waiting for ${KEY_FILE} ..."
    done
    log "atKeys found; starting sshnpd"
fi

ARGS=(
    --key-file "$KEY_FILE"
    --atsign "$DEVICE_ATSIGN"
    --device "$DEVICE_NAME"
)
if [ -n "${MANAGER_ATSIGN:-}" ]; then
    ARGS+=(--managers "$MANAGER_ATSIGN")
fi
if [ -n "${POLICY_ATSIGN:-}" ]; then
    ARGS+=(--policy-manager "$POLICY_ATSIGN")
fi
if [ -n "${DEVICE_GROUP:-}" ]; then
    ARGS+=(--device-group "$DEVICE_GROUP")
fi
if [ -n "${ROOT_SERVER:-}" ]; then
    ARGS+=(--root-server "$ROOT_SERVER")
fi
if [ -n "${PERMIT_OPEN:-}" ]; then
    ARGS+=(--permit-open "$PERMIT_OPEN")
fi
if [ "${SSHPUBLICKEY:-false}" = "true" ]; then
    ARGS+=(--sshpublickey)
fi
if [ -n "${EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206 # EXTRA_ARGS is intentionally word-split
    ARGS+=(${EXTRA_ARGS})
fi

log "starting sshnpd for ${DEVICE_ATSIGN} (device ${DEVICE_NAME}, managers ${MANAGER_ATSIGN:-<none>}, policy ${POLICY_ATSIGN:-<none>})"
exec /usr/local/bin/sshnpd "${ARGS[@]}"
