.PHONY: fetch image tar lint smoke clean

# Image version tag; the release workflow overrides this from the git tag.
VERSION ?= 0.0.0-dev

IMAGE ?= noports-iosxe:$(VERSION)
# IOx on Catalyst 9000 / Catalyst 8000 runs x86_64 containers.
PLATFORM ?= linux/amd64

# Download the pinned sshnpd release binaries (see SSHNPD_VERSION) into build/
fetch:
	./scripts/fetch-sshnpd.sh

# Build the container image (binaries must be staged in build/ first)
image: build/sshnpd
	docker build --platform $(PLATFORM) -f docker/Dockerfile -t $(IMAGE) .

# Export the image as the docker-save tarball IOS-XE installs directly:
#   app-hosting install appid noports package usbflash1:noports-iosxe.tar
tar: image
	docker save $(IMAGE) -o build/noports-iosxe.tar
	@ls -lh build/noports-iosxe.tar

build/sshnpd:
	./scripts/fetch-sshnpd.sh

# Lint shell scripts and the Dockerfile (all via Docker; no local installs)
lint:
	docker run --rm -v $(CURDIR):/mnt -w /mnt koalaman/shellcheck:stable \
		docker/entrypoint.sh docker/onboard-noports.sh \
		scripts/fetch-sshnpd.sh scripts/smoke-test.sh
	docker run --rm -i hadolint/hadolint < docker/Dockerfile

# Container-level smoke test (mirrors the CI smoke job): the entrypoint must
# reject missing env vars, reach the awaiting-onboarding state with test env
# vars, and both packaged binaries must execute.
smoke: image
	./scripts/smoke-test.sh $(IMAGE)

clean:
	rm -rf build
