# Local builds with Nix

This fork can be built locally with Nix instead of GitHub Actions.

## Requirements

- Nix with flakes enabled (nix-darwin / home-manager already provides this).
- First build downloads the full ZMK + Zephyr west dependencies (~200 MB), so it
  needs a stable network. Subsequent builds are offline (deps are cached in the
  Nix store via a fixed-output derivation).

## Build

    nix build            # -> ./result/zmk_left.uf2 + ./result/zmk_right.uf2

Output is two UF2 images for the Corne halves (nice!nano v2 / nRF52840):

- `result/zmk_left.uf2`  — left half (central)
- `result/zmk_right.uf2` — right half (peripheral)

## Flash (macOS)

Use the interactive flasher, once per half:

    nix build              # if you haven't already
    nix run .#flash left   # double-tap reset on the LEFT half when prompted
    nix run .#flash right  # double-tap reset on the RIGHT half when prompted

The script waits for the nice!nano bootloader volume to appear (identified by its
`INFO_UF2.TXT`, not just the `NICENANO` name), copies the matching
`result/zmk_<side>.uf2`, and confirms once the board reboots. The reboot causes a
harmless `Input/output error` from `cp` — the script treats the volume
disappearing as success, so that error is expected and not a failure.

To flash by hand instead, copy the UF2 onto the bootloader volume:

    cp -L result/zmk_left.uf2 /Volumes/NICENANO/    # after double-tap reset

## Flash (Linux)

This repo's `.#flash` is a macOS script. On Linux, use the zmk-nix flasher
directly:

    nix run github:lilyinstarlight/zmk-nix#flash

## Update ZMK / dependencies

    nix run .#update     # bumps west deps and refreshes zephyrDepsHash

After running update, rebuild and re-flash.

## Notes

- Board target is `nice_nano//zmk` (Zephyr HWMv2; the old flat `nice_nano_v2`
  name was removed on current ZMK `main` — v2 hardware is revision 2.0.0, the
  default). Shield is `corne_%PART%`. Display is OFF, matching `config/corne.conf`.
- The ZMK revision is pinned in `config/west.yml`; Zephyr flows from ZMK's own
  `app/west.yml` import.
- West deps are captured by `zephyrDepsHash` in `flake.nix` (a fixed-output
  derivation). If you change `config/west.yml`, the hash must be regenerated —
  set it to all-zeros, run `nix build`, and paste the `got:` hash it prints.
