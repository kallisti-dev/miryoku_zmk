# Local ZMK Build via Nix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build this Miryoku ZMK config locally on macOS via a Nix flake (using `lilyinstarlight/zmk-nix`), producing flashable `corne_left.uf2` / `corne_right.uf2` without GitHub Actions.

**Architecture:** Add a west manifest (`config/west.yml`) so `zmk-nix` can resolve ZMK + Zephyr + modules, then a `flake.nix` consuming `zmk-nix.buildSplitKeyboard` for the Corne (`nice_nano_v2`, `corne_%PART%`, display off — matching the current committed config). West dependencies are captured as one fixed-output derivation keyed by `zephyrDepsHash`; `nix run .#update` regenerates it. Build output lands in `./result/`.

**Tech Stack:** Nix flakes, `lilyinstarlight/zmk-nix`, ZMK/Zephyr west build, macOS (aarch64-darwin).

## Global Constraints

- Platform: **aarch64-darwin** (nix-darwin). Flakes are enabled (`nix 2.34`).
- Package management via **Nix only** — never `brew`/`npm -g`. Containers are **Podman**, but this plan uses native Nix (no container).
- Board: **`nice_nano_v2`**. Shield: **`corne_%PART%`** (→ `corne_left` + `corne_right`).
- Display: **OFF** — use `config/corne.conf` exactly as committed (do NOT re-enable `CONFIG_ZMK_DISPLAY`).
- Repo stays a **fork of Miryoku ZMK**; add files, do not extract/restructure.
- ZMK CI mechanism to mirror (from `.github/workflows/main.yml`): clone `zmkfirmware/zmk` (default branch `main`), `west init -l app` + `west update`, config passed via `-DZMK_CONFIG=<repo>/config`. Our `west.yml` reproduces this: `zmk` project with `import: app/west.yml`, Zephyr pin flowing from ZMK's own manifest, `self: path: config`.
- Work happens on branch `local-nix-build` (already created; design doc already committed there).
- **`zephyrDepsHash` and the exact ZMK commit are DISCOVERED during execution** (a plan cannot hardcode a fixed-output hash). Tasks below capture how.

## File Structure

- Create: `config/west.yml` — west manifest (ZMK + Zephyr import + `self: path: config`).
- Create: `flake.nix` — flake consuming `zmk-nix`, `buildSplitKeyboard` for Corne.
- Create: `.gitignore` — ignore `result`, `result-*`, `zmk.uf2`.

---

### Task 1: Add west manifest

**Files:**
- Create: `config/west.yml`

**Interfaces:**
- Produces: a west manifest at `config/west.yml` with `self: path: config`, consumed by `flake.nix` (Task 2) — `zmk-nix` reads it to fetch ZMK + Zephyr + modules.

- [ ] **Step 1: Pin the current ZMK `main` commit for reproducibility**

Rather than a floating `main` (non-reproducible), resolve `main` to a concrete SHA now:

Run:
```bash
git ls-remote https://github.com/zmkfirmware/zmk main
```
Expected: one line, `<40-char-sha>\trefs/heads/main`. Note the SHA — call it `ZMK_SHA`.

- [ ] **Step 2: Confirm the Zephyr revision ZMK pins**

Run:
```bash
curl -sL "https://raw.githubusercontent.com/zmkfirmware/zmk/main/app/west.yml" | grep -A2 "name: zephyr"
```
Expected: shows `revision: v4.1.0+zmk-fixes` (or whatever ZMK currently pins). Note it — call it `ZEPHYR_REV`. This flows in via `import` and does NOT need to be restated in our manifest, but confirming it documents what we build against.

- [ ] **Step 3: Write `config/west.yml`**

Substitute `ZMK_SHA` from Step 1 into the revision (keep the human comment noting it's `main` at pin time):

```yaml
manifest:
  remotes:
    - name: zmkfirmware
      url-base: https://github.com/zmkfirmware
  projects:
    - name: zmk
      remote: zmkfirmware
      revision: ZMK_SHA  # zmkfirmware/zmk main, pinned 2026-07-30
      import: app/west.yml
  self:
    path: config
```

Note: we import ZMK's `app/west.yml`, which itself imports Zephyr + modules with ZMK's pins. We do NOT separately list zephyr — that avoids a version-skew bug where our pin disagrees with ZMK's.

- [ ] **Step 4: Validate the YAML parses**

Run:
```bash
nix-shell -p yq --run "yq . config/west.yml"
```
Expected: pretty-printed JSON of the manifest, no parse error. Confirm `manifest.self.path == "config"` and `manifest.projects[0].revision` is the 40-char SHA (not the literal `ZMK_SHA`).

- [ ] **Step 5: Commit**

```bash
git add config/west.yml
git commit -m "build: add west manifest for local zmk-nix builds"
```

---

### Task 2: Add the flake and `.gitignore`

**Files:**
- Create: `flake.nix`
- Create: `.gitignore`

**Interfaces:**
- Consumes: `config/west.yml` (Task 1) via the `config = "config"` default and the `src` tree.
- Produces: `packages.{default,firmware,flash,update}` and `devShells.default`. The `firmware` package builds `corne_left.uf2` + `corne_right.uf2`.

- [ ] **Step 1: Write `.gitignore`**

The repo has none. Create it:

```
# Nix build outputs
result
result-*

# Downloaded / stray firmware artifacts (built firmware lives in ./result)
zmk.uf2
```

- [ ] **Step 2: Write `flake.nix` with a placeholder hash**

`zephyrDepsHash` is a fixed-output hash we cannot know yet. Use the all-zeros SHA-256 sentinel so the first build fails and prints the real hash:

```nix
{
  description = "Miryoku ZMK — local build for Corne (nice_nano_v2)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zmk-nix }: let
    forAllSystems = nixpkgs.lib.genAttrs (nixpkgs.lib.attrNames zmk-nix.packages);
  in {
    packages = forAllSystems (system: rec {
      default = firmware;

      firmware = zmk-nix.legacyPackages.${system}.buildSplitKeyboard {
        name = "miryoku-corne";

        src = nixpkgs.lib.sourceFilesBySuffices self [
          ".board" ".cmake" ".conf" ".defconfig" ".dts" ".dtsi"
          ".h" ".json" ".keymap" ".overlay" ".shield" ".yml" "_defconfig"
        ];

        board = "nice_nano_v2";
        shield = "corne_%PART%";

        zephyrDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

        meta = {
          description = "Miryoku ZMK firmware for Corne";
          license = nixpkgs.lib.licenses.mit;
          platforms = nixpkgs.lib.platforms.all;
        };
      };

      flash = zmk-nix.packages.${system}.flash.override { inherit firmware; };
      update = zmk-nix.packages.${system}.update;
    });

    devShells = forAllSystems (system: {
      default = zmk-nix.devShells.${system}.default;
    });
  };
}
```

Note the added `.h` suffix (vs. the upstream template) — Miryoku's `miryoku/*.h` and `config/*.h` custom-config files must be in the build `src`, or the keymap won't compile.

- [ ] **Step 3: Stage the flake so Nix sees it (flakes ignore untracked files)**

```bash
git add flake.nix .gitignore
```
(No commit yet — we commit after the hash is correct in Task 3. Staging is required because `nix build` on a git repo only sees tracked/staged files.)

- [ ] **Step 4: Verify the flake evaluates**

Run:
```bash
nix flake show 2>&1 | head -30
```
Expected: shows `packages.aarch64-darwin.{default,firmware,flash,update}` and `devShells.aarch64-darwin.default`. If it errors on the `zmk-nix` input, check network / flake registry. Do NOT proceed to build until `flake show` is clean.

- [ ] **Step 5: Commit (with placeholder hash — corrected in Task 3)**

```bash
git commit -m "build: add zmk-nix flake for local Corne builds"
```

---

### Task 3: Resolve the FOD hash and produce firmware

**Files:**
- Modify: `flake.nix` (the `zephyrDepsHash` line)

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces: `./result/corne_left.uf2` and `./result/corne_right.uf2`.

- [ ] **Step 1: Trigger the intentional hash mismatch**

Run:
```bash
nix build .#firmware 2>&1 | tee /tmp/zmk-build-1.log | tail -20
```
Expected: the build of the *zephyr-deps* fixed-output derivation FAILS with a hash mismatch, printing lines like:
```
error: hash mismatch in fixed-output derivation '...zephyr-deps...':
         specified: sha256-AAAA...AAA=
            got:    sha256-<REAL_HASH>=
```
This is EXPECTED — it is how a FOD reveals its real hash. Copy the `got:` value — call it `REAL_HASH`.

If instead it fails *before* fetching deps (e.g. eval error, or `buildSplitKeyboard` not found), stop and fix that — it's a real error, not the hash dance.

- [ ] **Step 2: Paste the real hash into `flake.nix`**

Replace the placeholder line:
```nix
        zephyrDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```
with (using `REAL_HASH` from Step 1):
```nix
        zephyrDepsHash = "sha256-<REAL_HASH>=";
```

- [ ] **Step 3: Stage so Nix sees the change**

```bash
git add flake.nix
```

- [ ] **Step 4: Build for real**

Run:
```bash
nix build .#firmware 2>&1 | tee /tmp/zmk-build-2.log
```
Expected: the deps FOD now matches and the split build proceeds (this compiles both halves; it may take several minutes the first time). Ends with no error and creates a `./result` symlink.

**If the build fails inside the Zephyr/west compile** (not a hash error) — e.g. toolchain dynamic-linking errors flagged in the design's risks — capture the failing output and STOP for review. The fallback (`gnuarmemb` toolchain) is a design-level change, not a plan step; escalate rather than improvise.

- [ ] **Step 5: Verify both `.uf2` files exist and are non-trivial**

Run:
```bash
ls -l result/ && file result/*.uf2
```
Expected: two files — `corne_left.uf2` and `corne_right.uf2` (names may be `zmk.uf2`-prefixed per-part depending on zmk-nix; if so, note the actual names). Each should be a real firmware image (hundreds of KB), not empty. Confirm with:
```bash
du -h result/*.uf2
```
Expected: each on the order of ~200KB–600KB.

- [ ] **Step 6: Commit the corrected hash**

```bash
git commit -m "build: pin resolved zephyrDepsHash for corne firmware"
```

---

### Task 4: Verify the flashing app and document usage

**Files:**
- Modify: `readme.org` (add a short "Local Nix Build" note) OR create `BUILDING-nix.md`

**Interfaces:**
- Consumes: the working `flash` package from Task 2/3.

- [ ] **Step 1: Confirm the flash app is runnable (dry inspection — do NOT flash unprompted)**

Run:
```bash
nix run .#flash -- --help 2>&1 | head -20 || nix eval .#flash.name 2>&1 | head -5
```
Expected: either help text from the flash script, or at minimum the derivation resolves. We are NOT flashing hardware here — flashing requires the user to put a Corne half into bootloader mode. Note in the log whether `--help` is supported.

- [ ] **Step 2: Write the usage note**

Create `BUILDING-nix.md`:

```markdown
# Local builds with Nix

This fork can be built locally with Nix instead of GitHub Actions.

## Requirements
- Nix with flakes enabled (nix-darwin/home-manager already provides this).

## Build

    nix build            # -> ./result/corne_left.uf2 + corne_right.uf2

## Flash

Put one Corne half into bootloader mode (double-tap reset), then:

    nix run .#flash

Repeat for the other half.

## Update ZMK / dependencies

    nix run .#update     # bumps west deps and refreshes zephyrDepsHash

## Notes
- Targets `nice_nano_v2`, shield `corne_%PART%`, display OFF (matches config/corne.conf).
- West deps are captured by `zephyrDepsHash` in flake.nix (a fixed-output derivation).
```

- [ ] **Step 3: Commit**

```bash
git add BUILDING-nix.md
git commit -m "docs: document local Nix build and flash workflow"
```

- [ ] **Step 4: Final verification pass**

Run:
```bash
nix build 2>&1 | tail -5 && ls result/
```
Expected: clean rebuild (fast, cached) and both `.uf2` files present. This confirms the default package works end-to-end.

---

## Self-Review

**Spec coverage:**
- `config/west.yml` → Task 1. ✅
- `flake.nix` (zmk-nix, corne_%PART%, nice_nano_v2, display off, `.h` in src) → Task 2. ✅
- `.gitignore` → Task 2. ✅
- `zephyrDepsHash` discovery + real build + `.uf2` validation → Task 3. ✅
- Flash workflow + user docs → Task 4. ✅
- Darwin toolchain risk (escalate, don't improvise `gnuarmemb`) → Task 3 Step 4. ✅
- Fork-stays-a-fork constraint → Global Constraints; no restructuring tasks. ✅
- First-build-hash-failure-is-expected → Task 3 Steps 1–2. ✅

**Placeholder scan:** The only intentional "placeholder" is the all-zeros `zephyrDepsHash`, which is REQUIRED by the FOD workflow and resolved in Task 3. `ZMK_SHA`/`REAL_HASH` are values discovered by explicit commands, not vague TODOs. No forbidden placeholders.

**Type consistency:** Package attr names (`firmware`, `flash`, `update`, `default`) are consistent across Tasks 2–4. `buildSplitKeyboard` argument names (`board`, `shield`, `src`, `zephyrDepsHash`, `config` default) match the verified zmk-nix API.
