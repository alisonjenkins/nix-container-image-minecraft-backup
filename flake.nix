{
  description = "Minecraft backup using rdiff-backup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { ... } @ inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
        };

        backup_world = { pkgs }:
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

        container_packages = pkgs: with pkgs; [
          (backup_world { inherit pkgs; })
          coreutils
          dockerTools.binSh
          dockerTools.caCertificates
          ps
          rdiff-backup
          yazi
        ];

        container_aarch64 = pkgs.pkgsCross.aarch64-multiplatform.dockerTools.buildLayeredImage {
          name = "minecraft-backup";
          tag = "latest-aarch64";
          config.Cmd = [ "/bin/minecraft_backup" ];
          contents = pkgs.pkgsCross.aarch64-multiplatform.buildEnv {
            name = "image-root";
            paths = container_packages { pkgs = pkgs.pkgsCross.aarch64-multiplatform; };
            pathsToLink = [ "/bin" "/etc" "/var" ];
          };
          fakeRootCommands = ''
            mkdir /tmp
            chmod 1777 /tmp
          '';
        };

        container_x86_64 = pkgs.dockerTools.buildLayeredImage {
          name = "minecraft-backup";
          tag = "latest-x86_64";
          config.Cmd = [ "/bin/minecraft_backup" ];
          contents = pkgs.buildEnv {
            name = "image-root";
            paths = (container_packages { inherit pkgs; });
            pathsToLink = [ "/bin" "/etc" "/var" ];
          };
          fakeRootCommands = ''
            mkdir /tmp
            chmod 1777 /tmp
          '';
        };
      in
      {
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
