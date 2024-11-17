{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { ... }@inputs:
    let
      forEachShellSystem = f: lib.genAttrs shellSystems (system: f system);
      forEachSupportedSystem = f: lib.genAttrs supportedSystems (system: f system);
      imageName = "minecraft-backup";
      imageTag = "latest";
      lib = inputs.nixpkgs.lib;

      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      shellSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      mkDockerImage =
        pkgs: targetSystem:
        let
          archSuffix = if targetSystem == "x86_64-linux" then "amd64" else "arm64";

          backup_world = { pkgs }: pkgs.writeShellScriptBin ''minecraft_backup'' ''
            set -euo pipefail
            ${pkgs.coreutils}/bin/mkdir -p $BACKUP_PATH
            while true; do
              ${pkgs.coreutils}/bin/sleep $BACKUP_INTERVAL
              ${pkgs.rdiff-backup}/bin/rdiff-backup --api-version 201 --new backup $WORLD_PATH $BACKUP_PATH
              set +e
              ${pkgs.rdiff-backup}/bin/rdiff-backup --api-version 201 --new remove increments --older-than ''${KEEP_BACKUPS}B $BACKUP_PATH
              set -e
            done
          '';

          container_packages = { pkgs }: with pkgs; [
            (backup_world { inherit pkgs; })
            coreutils
            dockerTools.binSh
            dockerTools.caCertificates
            ps
            rdiff-backup
            yazi
          ];
        in
        pkgs.dockerTools.buildImage {
          name = imageName;
          tag = "${imageTag}-${archSuffix}";
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = container_packages { inherit pkgs; };
            pathsToLink = [ "/bin" ];
          };
        };
    in
    {
      packages = forEachSupportedSystem (
        system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };

          buildForLinux =
            targetSystem:
            if system == targetSystem then
              mkDockerImage pkgs targetSystem
            else
              mkDockerImage
                (import inputs.nixpkgs {
                  localSystem = system;
                  crossSystem = targetSystem;
                })
                targetSystem;
        in
        {
          "amd64" = buildForLinux "x86_64-linux";
          "arm64" = buildForLinux "aarch64-linux";
        }
      );

      devShells = forEachShellSystem (system:
        (
          let
            pkgs = import inputs.nixpkgs {
              inherit system;
            };
          in
          {
            "default" = pkgs.mkShellNoCC {
              packages = [
                pkgs.just
                pkgs.nix-fast-build
                pkgs.rdiff-backup
              ];
            };
          }
        ));

      apps = forEachSupportedSystem (system: {
        default = {
          type = "app";
          program = toString (
            inputs.nixpkgs.legacyPackages.${system}.writeScript "build-multi-arch" ''
              #!${inputs.nixpkgs.legacyPackages.${system}.bash}/bin/bash
              set -e
              echo "Building x86_64-linux image..."
              nix build .#amd64 --out-link result-${system}-amd64
              echo "Building aarch64-linux image..."
              nix build .#arm64 --out-link result-${system}-arm64
            ''
          );
        };
      });
    };
}
