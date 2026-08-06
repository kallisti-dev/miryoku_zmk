#!/usr/bin/env bash
#
# Flash one Corne half's firmware from the Nix build output, on macOS.
#
# Usage:
#   ./flash.sh left
#   ./flash.sh right
#   nix run .#flash left
#
# Flashes result/zmk_<side>.uf2 (produced by `nix build`) to a nice!nano in
# bootloader mode. Run once per half.

set -euo pipefail

FIRMWARE_DIR="${FLASH_FIRMWARE_DIR:-result}"
MOUNT_TIMEOUT="${FLASH_MOUNT_TIMEOUT:-60}"   # seconds to wait for the bootloader volume
BOARD_ID="nRF52840-nicenano"                 # from the bootloader's INFO_UF2.TXT

die() { echo "error: $*" >&2; exit 1; }

# --- validate argument ------------------------------------------------------

side="${1:-}"
case "$side" in
    left|right) ;;
    "") die "missing side. Usage: $(basename "$0") left|right" ;;
    *)  die "invalid side '$side'. Usage: $(basename "$0") left|right" ;;
esac

SIDE_UPPER="$(printf '%s' "$side" | tr '[:lower:]' '[:upper:]')"

# --- resolve firmware -------------------------------------------------------

uf2="$FIRMWARE_DIR/zmk_${side}.uf2"
if [ ! -e "$uf2" ]; then
    die "firmware not found at '$uf2'. Run 'nix build' first."
fi

# --- find the bootloader volume ---------------------------------------------
#
# A nice!nano in bootloader mode auto-mounts under /Volumes with an
# INFO_UF2.TXT whose Board-ID is nRF52840-nicenano. We match on that rather
# than the volume name, so an unrelated disk named NICENANO is never targeted.

find_bootloader_volume() {
    local vol info
    for vol in /Volumes/*; do
        info="$vol/INFO_UF2.TXT"
        [ -f "$info" ] || continue
        if grep -q "$BOARD_ID" "$info" 2>/dev/null; then
            printf '%s\n' "$vol"
            return 0
        fi
    done
    return 1
}

echo "Put the ${SIDE_UPPER} half into bootloader mode (double-tap the reset button)."
printf 'Press Enter when ready (or Ctrl-C to cancel)... '
read -r _

printf 'Waiting for the bootloader volume '
volume=""
for _ in $(seq "$MOUNT_TIMEOUT"); do
    if volume="$(find_bootloader_volume)"; then
        break
    fi
    printf '.'
    sleep 1
    volume=""
done
echo

[ -n "$volume" ] || die "timed out after ${MOUNT_TIMEOUT}s waiting for a nice!nano bootloader volume. Did you double-tap reset?"

echo "Found bootloader at: $volume"

# --- copy firmware ----------------------------------------------------------
#
# The board reboots the instant the last UF2 block is written, so `cp` often
# reports "Input/output error" even on success. Treat the write as successful
# iff the volume disappears (board rebooted) afterward.

echo "Flashing ${side} firmware..."
cp -L "$uf2" "$volume/" 2>/dev/null || true
sync 2>/dev/null || true

# Wait for the volume to unmount (reboot = success).
for _ in $(seq 15); do
    [ -d "$volume" ] || break
    sleep 1
done

if [ -d "$volume" ]; then
    die "volume '$volume' did not reboot/unmount; flash may have failed. Try again."
fi

echo "${SIDE_UPPER} half flashed ✓"
