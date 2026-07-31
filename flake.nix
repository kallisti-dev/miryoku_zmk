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

        # ZMK main uses Zephyr HWMv2: the old flat "nice_nano_v2" is now the
        # "nice_nano" board with the "//zmk" variant (default revision 2.0.0).
        board = "nice_nano//zmk";
        # KeyboardHoarders Corne Mini 2 ships nice!view (e-paper) displays,
        # not OLEDs. They require the nice_view_adapter + nice_view shields
        # stacked on the corne shield (matches the maker's build.yaml).
        shield = "corne_%PART% nice_view_adapter nice_view";

        zephyrDepsHash = "sha256-huutvB9pKI/7oMHB7lDbzoBo0d1THF67AKitYG3GlI0=";

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
