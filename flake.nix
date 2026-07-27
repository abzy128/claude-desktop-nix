{
  description = "Nix flake for the Claude desktop app on Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        claude-desktop = final.callPackage ./package.nix { };
      };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
          config.allowUnfree = true;
        };
      in
      {
        packages = {
          default = pkgs.claude-desktop;
          claude-desktop = pkgs.claude-desktop;
        };

        apps.default = {
          type = "app";
          program = "${pkgs.claude-desktop}/bin/claude-desktop";
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ curl jq nixpkgs-fmt ];
        };
      }) // {
      overlays.default = overlay;
    };
}
