# Local ZMK Build via Nix (`zmk-nix`) — Design

**Date:** 2026-07-30
**Status:** Approved (design)
**Goal:** Build this Miryoku ZMK config locally on macOS (aarch64-darwin) instead of relying on GitHub Actions, producing flashable `corne_left` / `corne_right` `.uf2` files.

## Context

- This repo is a fork of Miryoku ZMK. It builds firmware via GitHub Actions workflows
  (`.github/workflows/main.yml` + `build-example-*.yml`), which supply the west manifest
  at build time. **There is no `west.yml` checked into the repo tree.**
- User has two Corne shields (left + right), controller `nice_nano_v2`.
- User's latest commit (`ba3f037`) disabled the OLED display
  (`CONFIG_ZMK_DISPLAY=y` → `# CONFIG_ZMK_DISPLAY=n`). Current committed state is
  **plain corne, no display.**
- Miryoku drives the corne OLED via a **kconfig flag** (`CONFIG_ZMK_DISPLAY=y`), not a
  `nice_view_adapter nice_view` shield — confirmed against
  `.github/workflows/build-example-corne-nice_nano-display.yml`.
- Environment: nix-darwin + home-manager. Flakes enabled (`nix 2.34`). Podman not Docker.
  Package management goes through Nix only.

## Prior Art (evaluated)

- **`lilyinstarlight/zmk-nix`** — purpose-built Nix build system for ZMK, split-aware
  (`buildSplitKeyboard`). Captures all west deps as a single fixed-output derivation keyed
  by `zephyrDepsHash`; `nix run .#update` regenerates it. **Chosen.**
- `urob/zmk-config` — nix + direnv + just; nicer ergonomics, heavier setup. Rejected for
  first pass.
- `nix-community/zephyr-nix`, `katyo/zephyr-rtos.nix` — generic Zephyr flakes (Darwin
  support), but we'd hand-write the ZMK split logic. Rejected.

## Decision: adopt `zmk-nix`

Rationale: least code, split-aware, and it answers the hermeticity concern the user raised
— the ~30 transitively-imported Zephyr modules are captured under one `zephyrDepsHash`
(a fixed-output derivation), not hand-pinned. Repinning is `nix run .#update`, not editing
30 inputs.

## Changes to this repo

### 1. `config/west.yml` (new)

zmk-nix requires a west manifest at the source root or `westRoot`. This repo lacks one, so
we add the standard ZMK config-repo manifest, based on the ZMK project manifest matching
Miryoku's CI (Zephyr `v4.1.0+zmk-fixes`), with `self: path: config` so ZMK picks up this
repo's keymaps/conf.

Manifest shape (revisions to be pinned to match Miryoku's expected ZMK version during
implementation):

```yaml
manifest:
  remotes:
    - name: zmkfirmware
      url-base: https://github.com/zmkfirmware
  projects:
    - name: zmk
      remote: zmkfirmware
      revision: <ZMK main/branch rev>
      import: app/west.yml
    - name: zephyr
      remote: zmkfirmware
      revision: v4.1.0+zmk-fixes
      import:
        name-blocklist: [ ci-tools, hal_altera, hal_cypress, hal_infineon,
          hal_microchip, hal_nxp, hal_openisa, hal_silabs, hal_xtensa, hal_st,
          hal_ti, loramac-node, mcuboot, mcumgr, net-tools, openthread, edtt,
          trusted-firmware-m ]
  self:
    path: config
```

### 2. `flake.nix` (new)

Adapted from the zmk-nix template:

- `board = "nice_nano_v2"`
- `shield = "corne_%PART%"` → builds `corne_left` + `corne_right`
- `src` filtered via `sourceFilesBySuffices` to firmware-relevant suffixes (excludes
  `.git`, the stray `zmk.uf2`, `matrix.txt`, docs)
- `zephyrDepsHash` — placeholder initially; **first `nix build` fails and prints the
  correct hash** (standard FOD flow); paste it in and rebuild
- Outputs: `packages.{default,firmware,flash,update}` + `devShells.default`

### 3. `.gitignore` (new)

Repo currently has none. Ignore:
```
result
result-*
zmk.uf2
```
(`matrix.txt` and the root `zmk.uf2` are untracked GH-Actions artifacts.)

## User workflow after this lands

```bash
nix build              # → ./result/ with corne_left.uf2 + corne_right.uf2
nix run .#flash        # put a half in bootloader mode; copies the .uf2
nix run .#update       # later: bump ZMK/deps + refresh zephyrDepsHash
```

No user-visible west workspace — source lives in the Nix store (FOD); build runs in a
sandbox. (The earlier "workspace location" question is therefore moot.)

## Risks / caveats

- **First-build hash failure is expected**, not an error — it's how fixed-output
  derivations surface the real hash. Walk it through during implementation.
- **Darwin toolchain**: zmk-nix uses the Zephyr SDK path. Used on macOS by others, but the
  community flagged possible dynamic-linking issues with Nix-provided Zephyr SDKs. If hit,
  fallback is the `gnuarmemb` route (`gcc-arm-embedded` + `ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb`
  + `GNUARMEMB_TOOLCHAIN_PATH`). **Success = an actual completed build + valid `.uf2`, not
  just flake evaluation.**
- **`west.yml` revision** must match Miryoku's expected ZMK version so local firmware
  matches CI behavior. Cross-check during implementation.

## Repo structure decision

Stay a **fork of Miryoku ZMK** rather than extracting to a standalone `zmk-config`. The
user touches only 4 files (`config/corne.conf`, `miryoku/custom_config.h`,
`miryoku/miryoku_behaviors.dtsi`, `miryoku/miryoku.h`) across 7 commits, but Miryoku's
in-tree "babel" keymap framework is not cleanly packaged as a west-importable ZMK module,
so a full extraction is a separate, non-trivial project. The flake + `west.yml` live in the
fork. Slim-down deferred (see Out of scope).

## Out of scope (future passes)

- OLED display config (`CONFIG_ZMK_DISPLAY=y`) — user's prior attempt hit a wpm-widget
  build error; revisit once builds are fast.
- Extracting to a standalone minimal `zmk-config` repo (Miryoku-as-west-module).
- direnv auto-activation / `just` recipes.
- Full manifest→nix pin generation beyond the single `zephyrDepsHash`.

## Success criteria

1. `nix build` produces `corne_left.uf2` and `corne_right.uf2` on aarch64-darwin.
2. `nix run .#flash` can flash a Corne half in bootloader mode.
3. Firmware behavior matches the user's current committed config (plain corne, display off).
