{
  description = "Minecraft backup using rdiff-backup";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
        };

      pkgs_arm64 = import inputs.nixpkgs {
        system = "aarch64-linux";
      };

      backup_world = {pkgs}:
        pkgs.writeShellScriptBin ''minecraft_backup'' ''
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

      backup_world_arm64 = backup_world {pkgs = pkgs_arm64;};
      backup_world_x86_64 = backup_world {inherit pkgs;};

      container_aarch64 = pkgs.pkgsCross.aarch64-multiplatform.dockerTools.buildLayeredImage {
        name = "minecraft-backup";
        tag = "latest-aarch64";
        config.Cmd = ["/bin/minecraft_backup"];
        contents = pkgs.pkgsCross.aarch64-multiplatform.buildEnv {
          name = "image-root";
          paths = with pkgs.pkgsCross.aarch64-multiplatform; [
            backup_world_arm64
            dockerTools.caCertificates
            ps
          ];
          pathsToLink = ["/bin" "/etc" "/var"];
        };
        fakeRootCommands = ''
          mkdir /tmp
          chmod 1777 /tmp
        '';
      };

      container_x86_64 = pkgs.dockerTools.buildLayeredImage {
        name = "minecraft-backup";
        tag = "latest-x86_64";
        config.Cmd = ["/bin/minecraft_backup"];
        contents = pkgs.buildEnv {
          name = "image-root";
          paths = with pkgs; [
            backup_world_x86_64
            dockerTools.caCertificates
            ps
          ];
          pathsToLink = ["/bin" "/etc" "/var"];
        };
        fakeRootCommands = ''
          mkdir /tmp
          chmod 1777 /tmp
        '';
      };
    in {
      packages = {
        container_x86_64 = container_x86_64;
        container_aarch64 = container_aarch64;
      };

      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.podman
          pkgs.rdiff-backup
        ];
      };
    });
}
