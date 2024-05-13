{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    nixpkgsUnstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flakeUtils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgsUnstable, flakeUtils }:
    flakeUtils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgsUnstable = nixpkgsUnstable.legacyPackages.${system};

          # TODO: make dependent on raylib package or make proper logic to have darwin dependencies
          buildInputs = with pkgs; [
            libpulseaudio
            alsa-lib

            mesa
            glfw
            libcxx
            libGL
            glfw

            zig
            zls
          ]
          ++ (with pkgs.xorg; [
            libX11
            libXcursor
            libXrandr
            libXinerama
            libXi
          ]);
        in
        rec {
          # TODO: Make package work
          # packages.default = pkgs.stdenv.mkDerivation
          #   {
          #     name = "plusplusparty";
          #     src = ./.;
          #     inherit buildInputs;
          #
          #     buildPhase = ''
          #       zig build
          #     '';
          #
          #     installPhase = ''
          #       mkdir $out/bin
          #       cp ./zig-out/bin/++party
          #     '';
          #   };

          # TODO: Make nix run work
          # apps.default = {
          #   type = "app";
          #   program = "${packages.default}/bin/++party";
          # };

          devShells.default = pkgs.mkShell { inherit buildInputs; };
        }
      );
}
