#!/bin/bash
# deploy/package.sh exports the exact Linux build for one architecture (aarch64 or x86_64) into a
# self-contained installer archive, dist/stride-linux-<arch>.tar.gz with its .sha256 beside it.
# The maintainer's mise task and the GitHub release workflow both run it; only explicit release assets enter dist/.
# With STRIDE_IMAGE_TAG set, the runtime image the executable came from is also tagged with that name,
# so the release workflow can publish exactly the image whose binary the archive contains.
set -euo pipefail
umask 077
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=deploy/release.conf
source "$ROOT/deploy/release.conf"
: "${STRIDE_CADDY_VERSION:?deploy/release.conf must pin STRIDE_CADDY_VERSION}"
ARCH=${1:-}
# ELF e_machine values confirm the exported executable really targets the requested architecture.
case "$ARCH" in
    aarch64) PLATFORM=linux/arm64; ELF_MACHINE=b700 ;;
    x86_64) PLATFORM=linux/amd64; ELF_MACHINE=3e00 ;;
    *) printf 'Usage: package.sh aarch64|x86_64\n' >&2; exit 2 ;;
esac
[[ $# -eq 1 ]] || { printf 'Usage: package.sh aarch64|x86_64\n' >&2; exit 2; }
TEMP=$(mktemp -d)
CONTAINER=
cleanup() {
    if [[ -n "$CONTAINER" ]]; then podman rm "$CONTAINER" >/dev/null; fi
    rm -rf -- "$TEMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if command -v sha256sum >/dev/null; then
    hash() { sha256sum "$@"; }
else
    command -v shasum >/dev/null || { printf 'A SHA-256 tool is required. No tools were installed.\n' >&2; exit 1; }
    hash() { shasum -a 256 "$@"; }
fi
CADDY_CACHE="$ROOT/dist/vendor/caddy-$STRIDE_CADDY_VERSION-$ARCH"
[[ -f "$CADDY_CACHE/caddy" && -f "$CADDY_CACHE/LICENSE" ]] || { printf 'Caddy %s is not cached. Explicitly run deploy/fetch-caddy.sh %s first.\n' "$ARCH" "$ARCH" >&2; exit 1; }
podman build --platform "$PLATFORM" --iidfile "$TEMP/image-id" -f "$ROOT/Containerfile" "$ROOT"
if [[ -n "${STRIDE_IMAGE_TAG:-}" ]]; then podman tag "$(cat "$TEMP/image-id")" "$STRIDE_IMAGE_TAG"; fi
CONTAINER=$(podman create --network none "$(cat "$TEMP/image-id")")
NAME="stride-linux-$ARCH"
RELEASE="$TEMP/$NAME"
mkdir -- "$RELEASE"
podman cp "$CONTAINER:/app/stride" "$RELEASE/stride"
machine=$(od -An -tx1 -j18 -N2 -- "$RELEASE/stride" | tr -d ' \n')
[[ "$machine" == "$ELF_MACHINE" ]] || { printf 'Exported stride executable is not %s (ELF e_machine %s). Check the Containerfile base image digests resolve for %s.\n' "$ARCH" "$machine" "$PLATFORM" >&2; exit 1; }
podman rm "$CONTAINER" >/dev/null
CONTAINER=
for asset in install.sh https.sh config.toml garmin-stride.service garmin-stride-https.service; do cp -- "$ROOT/deploy/$asset" "$RELEASE/$asset"; done
cp -- "$CADDY_CACHE/caddy" "$RELEASE/caddy"
cp -- "$CADDY_CACHE/LICENSE" "$RELEASE/CADDY-LICENSE"
cp -- "$ROOT/LICENSE" "$RELEASE/LICENSE"
chmod 0755 "$RELEASE/stride" "$RELEASE/install.sh" "$RELEASE/https.sh" "$RELEASE/caddy"
chmod 0644 "$RELEASE/config.toml" "$RELEASE/garmin-stride.service" "$RELEASE/garmin-stride-https.service" "$RELEASE/CADDY-LICENSE" "$RELEASE/LICENSE"
(cd -- "$RELEASE" && hash stride caddy CADDY-LICENSE LICENSE install.sh https.sh config.toml garmin-stride.service garmin-stride-https.service > SHA256SUMS)
chmod 0644 "$RELEASE/SHA256SUMS"
mkdir -p -- "$ROOT/dist"
ARCHIVE="$NAME.tar.gz"
# --no-xattrs keeps macOS extended attributes out of the archive so GNU tar on the device stays silent.
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$TEMP/$ARCHIVE" -C "$TEMP" "$NAME"
mv -- "$TEMP/$ARCHIVE" "$ROOT/dist/$ARCHIVE"
(cd -- "$ROOT/dist" && hash "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Installer archive: %s/dist/%s\n' "$ROOT" "$ARCHIVE"
