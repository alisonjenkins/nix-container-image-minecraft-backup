{
  description = "Minecraft backup using rdiff-backup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, ... } @ inputs:
    let
      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
      };

      lib = pkgs.lib;

      backup_world = { myPkgs }: myPkgs.writeShellScriptBin ''minecraft_backup'' ''
        set -euo pipefail
        ${myPkgs.coreutils}/bin/mkdir -p $BACKUP_PATH
        while true; do
          ${myPkgs.coreutils}/bin/sleep $BACKUP_INTERVAL
          ${myPkgs.rdiff-backup}/bin/rdiff-backup --api-version 201 --new backup $WORLD_PATH $BACKUP_PATH
          set +e
          ${myPkgs.rdiff-backup}/bin/rdiff-backup --api-version 201 --new remove increments --older-than ''${KEEP_BACKUPS}B $BACKUP_PATH
          set -e
        done
      '';

      container_packages = { myPkgs }: [
        (backup_world { inherit myPkgs; })
        myPkgs.coreutils
        myPkgs.dockerTools.binSh
        myPkgs.dockerTools.caCertificates
        myPkgs.ps
        myPkgs.rdiff-backup
        myPkgs.yazi
      ];

      pkgs_arm64 = import inputs.nixpkgs {
        system = "aarch64-linux";
      };

      container_aarch64 = pkgs.pkgsCross.aarch64-multiplatform.dockerTools.buildLayeredImage {
        name = "minecraft-backup";
        tag = "latest-aarch64";
        config.Cmd = [ "/bin/minecraft_backup" ];
        contents = pkgs.pkgsCross.aarch64-multiplatform.buildEnv {
          name = "image-root";
          paths = container_packages { myPkgs = pkgs_arm64; };
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
          paths = container_packages { myPkgs = pkgs; };
          pathsToLink = [ "/bin" "/etc" "/var" ];
        };
        fakeRootCommands = ''
          mkdir /tmp
          chmod 1777 /tmp
        '';
      };
    in
    {
      checks =
        let
          packages = lib.mapAttrs' (n: lib.nameValuePair "package-${n}") self.packages;
          # devShells = lib.mapAttrs' (n: lib.nameValuePair "devShell-${n}") self.devShells;
        in
        packages;
      # // devShells;

      packages = {
        x86_64-linux.container_aarch64 = container_aarch64;
        x86_64-linux.container_x86_64 = container_x86_64;
      };

      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [
          pkgs.just
          pkgs.nix-fast-build
          pkgs.podman
          pkgs.rdiff-backup
        ];
      };
    };
}
