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

The `nix run .#flash` helper from zmk-nix is **Linux-only** and will refuse to
evaluate on macOS. On macOS, flash by copying the UF2 onto the bootloader volume:

1. Put one Corne half into bootloader mode (double-tap the reset button). It
   mounts as a disk named `NICENANO`.
2. Copy the matching firmware onto it:

       cp -L result/zmk_left.uf2  /Volumes/NICENANO/     # left half
       # then reset the other half and:
       cp -L result/zmk_right.uf2 /Volumes/NICENANO/     # right half

   The board reboots automatically after the copy completes.

(`cp -L` follows the `result` symlink into the Nix store; a plain drag-and-drop
in Finder works too.)

## Flash (Linux)

On Linux the zmk-nix helper works:

    nix run .#flash

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
