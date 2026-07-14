# NoPorts sshnpd for Cisco IOS-XE Application Hosting (IOx).
#
# Build context is the repo root; run ./scripts/fetch-sshnpd.sh (or
# `make fetch`) first to stage the pinned release binaries in build/.
#
# Why not FROM atsigncompany/sshnpd? That image is built FROM scratch with
# only sshnpd inside: no shell for `app-hosting connect appid noports
# session`, no at_activate for on-box APKAM enrollment, and its entrypoint
# expects atKeys to already exist. On a switch we need an interactive
# onboarding flow, so this image is debian:bookworm-slim (the release
# binaries are glibc x86_64 and do not run on musl/Alpine) plus a small
# entrypoint that maps IOx run-opts environment variables to sshnpd flags.
FROM debian:bookworm-slim

# Take whatever ca-certificates bookworm currently ships; pinning a point
# release breaks the build on every debian update.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pinned NoPorts release binaries, staged by scripts/fetch-sshnpd.sh
COPY build/sshnpd build/at_activate build/srv /usr/local/bin/
COPY docker/entrypoint.sh docker/onboard-noports.sh /usr/local/bin/

RUN chmod 0755 /usr/local/bin/sshnpd /usr/local/bin/at_activate /usr/local/bin/srv \
    /usr/local/bin/entrypoint.sh /usr/local/bin/onboard-noports.sh \
    && mkdir -p /data

# /data is expected to be the IOx persistent app-data directory, mounted
# with:  run-opts 1 "-v $(APP_DATA):/data"
# Keys and atProtocol storage live there so they survive restart/upgrade.
VOLUME ["/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
