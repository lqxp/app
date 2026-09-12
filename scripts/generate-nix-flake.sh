#!/usr/bin/env bash
# Generates a standalone QxChat_<version>_flake.nix for NixOS users.
# Binary philosophy: no compilation — the flake fetches the CI-built Tauri
# binaries (QxChat_<version>_linux-<arch>.tar.gz) from release assets and
# injects them into a NixOS ld environment. The wrapper logic lives in
# nix/qxchat.nix; this flake only pins the exact binary hashes.
#
# Usage:
#   $0 <version> <x86_64-sri-hash> <aarch64-sri-hash> [repo] [tag]
#
# Example:
#   $0 1.20.3 sha256-abc... sha256-def...
#
# SRI hashes can be computed locally with:
#   nix hash file --sri QxChat_1.20.3_linux-x86_64.tar.gz
# or without nix:
#   python3 -c "import hashlib,base64,sys; print('sha256-'+base64.b64encode(hashlib.sha256(open(sys.argv[1],'rb').read()).digest()).decode())" <tarball>
#
# NOTE: CI (.github/workflows/build-and-release.yml) generates the published
# flake itself with hashes computed from the freshly built tarballs.
# This helper mirrors that template for local use.

set -euo pipefail

VERSION="${1:-}"
HASH_X86="${2:-}"
HASH_ARM="${3:-}"
REPO="${4:-lqxp/app}"
TAG="${5:-v${VERSION}}"

if [[ -z "$VERSION" || -z "$HASH_X86" || -z "$HASH_ARM" ]]; then
  echo "Usage: $0 <version> <x86_64-sri-hash> <aarch64-sri-hash> [repo] [tag]" >&2
  exit 1
fi

cat <<FLAKE
# QxChat ${VERSION} — NixOS flake (prebuilt binaries, no compilation)
# Fetches the CI-built Tauri binaries from release assets and injects
# them into a NixOS ld environment (patchelf + wrapProgram).
# The wrapper logic lives in nix/qxchat.nix inside qxchat-src;
# this flake only pins the exact binary hashes published alongside it.
#
# Usage (flake.nix):
#
#   {
#     inputs.qxchat.url = "github:${REPO}/releases/download/${TAG}/QxChat_${VERSION}_flake.nix";
#   }
#
# Then in your NixOS module:
#
#   { inputs, ... }: {
#     imports = [ inputs.qxchat.nixosModules.default ];
#     nixpkgs.overlays = [ inputs.qxchat.overlays.default ];
#     programs.qxchat.enable = true;
#   }

{
  description = "QxChat ${VERSION} — NixOS flake (prebuilt)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    qxchat-src = {
      url = "github:${REPO}/${TAG}";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, qxchat-src }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      # SRI hashes of the prebuilt Linux tarballs published
      # alongside this flake as release assets.
      binaryHashes = {
        x86_64-linux = "${HASH_X86}";
        aarch64-linux = "${HASH_ARM}";
      };

      qxchatPackage =
        { system }:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        pkgs.callPackage "\${qxchat-src}/nix/qxchat.nix" {
          version = "${VERSION}";
          inherit binaryHashes;
        };
    in
    {
      nixosModules.default = import "\${qxchat-src}/nix/module.nix";

      overlays.default = final: prev: {
        qxchat = self.packages.\${final.system}.qxchat;
      };

      packages = forAllSystems (
        system:
        {
          default = qxchatPackage { inherit system; };
          qxchat = qxchatPackage { inherit system; };
        }
      );
    };
}
FLAKE
