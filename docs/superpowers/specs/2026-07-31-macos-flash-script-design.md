# macOS Flash Script Design

**Date:** 2026-07-31
**Status:** Approved (design)
**Goal:** An interactive command to flash one Corne half's firmware from the Nix
build output on macOS, invoked once per side (`flash left`, `flash right`).

## Context

- `nix build` produces `result/zmk_left.uf2` and `result/zmk_right.uf2` (symlinks
  into the Nix store).
- The existing `zmk-nix` `.#flash` app is **Linux-only** (`meta.platforms =
  platforms.linux`); it uses `lsblk`, `findmnt`, and `udisksctl`, none of which
  exist on macOS. `nix run .#flash` therefore refuses to evaluate on darwin.
- On macOS, a nice!nano in bootloader mode auto-mounts as `/Volumes/NICENANO`
  with an `INFO_UF2.TXT` containing `Board-ID: nRF52840-nicenano`.
- Flashing quirk (observed): the board reboots the instant the last UF2 block is
  written, so `cp` reports `Input/output error` even on success. The real success
  signal is the volume disappearing.

## Decision

Two tracks:

1. **Local script now** — add a macOS flash command to this repo so flashing works
   today, invoked once per side.
2. **Upstream PR after** — contribute macOS support to `lilyinstarlight/zmk-nix`
   by making `nix/flash.nix` cross-platform (separate effort; see that track's
   own notes). Merge timing is the maintainer's call, so it must not block track 1.

Naming: replace this repo's broken `.#flash` with our working macOS script, so
`nix run .#flash left` is the natural command and `.#flash` actually works here.
(Personal macOS fork — losing the Linux-only app locally is fine.)

## Local script behavior

**Invocation:** `nix run .#flash left` / `nix run .#flash right` (also a committed
`flash.sh` the app wraps, so it is readable/editable and runnable directly).

**Argument:** exactly one of `left` | `right`. Anything else → usage + exit 1.

**Flow:**
1. Resolve firmware: read `result/zmk_<side>.uf2`. If `result` is missing, tell
   the user to run `nix build` first and exit 1. (Flash-existing-result only; no
   auto-build — keeps the script simple and fast.)
2. Prompt: "Put the <SIDE> half into bootloader mode (double-tap reset), then
   press Enter…"
3. Poll for the bootloader volume (timeout ~30s): a `/Volumes/*` entry whose
   `INFO_UF2.TXT` contains `nRF52840-nicenano`. Robust to volume-name changes and
   avoids flashing an unrelated `NICENANO`-named disk.
4. Copy `result/zmk_<side>.uf2` to the volume. Treat the reboot-induced I/O error
   as success **iff** the volume disappears afterward; otherwise report failure.
5. Confirm: "<SIDE> half flashed ✓".

**Non-goals (local script):** flashing both halves in one run, `settings_reset`,
Linux support (that is the upstream track).

## Files

- Create: `flash.sh` — the macOS flash script (bash).
- Modify: `flake.nix` — replace the `flash` package with an app wrapping
  `flash.sh` via `writeShellApplication` (so it is on `PATH` with deps), exposed
  under `apps.<system>.flash` and/or `packages.<system>.flash`.
- Modify: `BUILDING-nix.md` — update flash instructions to `nix run .#flash <side>`.

## Success criteria

1. `nix run .#flash left` flashes the left half from `result/` and confirms.
2. `nix run .#flash right` flashes the right half.
3. The reboot I/O error does not produce a false failure.
4. Missing `result` gives a clear "run nix build first" message.

## Upstream track (prep only, separate)

Make `nix/flash.nix` cross-platform: `meta.platforms = platforms.unix`;
`runtimeInputs` gated with `lib.optionals stdenv.hostPlatform.isLinux [util-linux]`;
branch on `stdenv.hostPlatform.isDarwin` for the `/Volumes` + `INFO_UF2.TXT` flow
while keeping the Linux `lsblk`/`udisksctl` path byte-for-byte unchanged. Same
`$@`/`firmware.parts` argument handling on both. Fork, test, open PR.
