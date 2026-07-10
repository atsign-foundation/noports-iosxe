#!/usr/bin/env bash
# Container-level smoke test for the NoPorts IOx image.
#
# No free IOS-XE image exists, so CI cannot run the app on a real switch
# (see the manual on-device test plan in QUICKSTART.md). This exercises
# everything below the IOx layer:
#   1. entrypoint fails fast, with a helpful message, when env vars are missing
#   2. with test env vars it reaches the awaiting-onboarding (waiting-for-keys)
#      state without crashing
#   3. sshnpd and at_activate execute inside the image (glibc compatibility)
#
# Usage: ./scripts/smoke-test.sh [image]   (default: noports-iosxe:0.0.0-dev)
set -euo pipefail

IMAGE="${1:-noports-iosxe:0.0.0-dev}"
PLATFORM="${PLATFORM:-linux/amd64}"
NAME="noports-iosxe-smoke-$$"

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "=== 1. entrypoint rejects missing env vars ==="
set +e
OUT=$(docker run --rm --platform "$PLATFORM" "$IMAGE" 2>&1)
RC=$?
set -e
echo "$OUT"
[ "$RC" -ne 0 ] || fail "entrypoint exited 0 without required env vars"
echo "$OUT" | grep -q "missing required environment variable" \
    || fail "no missing-env error message"
echo "$OUT" | grep -q "DEVICE_ATSIGN" || fail "message does not name the vars"

echo "=== 2. reaches awaiting-onboarding with test env vars ==="
docker run -d --name "$NAME" --platform "$PLATFORM" \
    -e DEVICE_ATSIGN=@smoke_device \
    -e MANAGER_ATSIGN=@smoke_manager \
    -e DEVICE_NAME=smoke_test \
    -e ROOT_SERVER=proxy:proxy0001.atsign.org:443 \
    "$IMAGE" >/dev/null
for _ in $(seq 1 12); do
    LOGS=$(docker logs "$NAME" 2>&1)
    if echo "$LOGS" | grep -q "awaiting-onboarding"; then
        break
    fi
    sleep 5
done
echo "$LOGS"
echo "$LOGS" | grep -q "awaiting-onboarding" \
    || fail "entrypoint never reached the awaiting-onboarding state"
echo "$LOGS" | grep -q "onboard-noports.sh" \
    || fail "waiting message does not point at the onboarding flow"
[ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = "true" ] \
    || fail "container exited while waiting for keys"

echo "=== 3. packaged binaries execute inside the image ==="
for BIN in sshnpd at_activate; do
    OUT=$(docker exec "$NAME" "/usr/local/bin/$BIN" --help 2>&1 || true)
    echo "$OUT" | head -3
    echo "$OUT" | grep -qiE "atsign|usage" \
        || fail "$BIN did not produce usage output"
done

echo "SMOKE PASS: $IMAGE"
