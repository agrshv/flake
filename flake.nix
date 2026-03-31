{
  description = "NixOS system config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
    catppuccin.url = "github:catppuccin/nix/release-25.11";
    nur.url = "github:nix-community/NUR";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      disko,
      home-manager,
      millennium,
      catppuccin,
      nur,
      sops-nix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      # The actual installed system
      nixosConfigurations.home-desktop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          catppuccin.nixosModules.catppuccin
          sops-nix.nixosModules.sops
          {
            nixpkgs.overlays = [ nur.overlays.default ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];
            home-manager.users.d3spair.imports = [
              ./home.nix
              catppuccin.homeModules.catppuccin
            ];
            home-manager.extraSpecialArgs = { inherit inputs; };
          }
          ./hosts/home-desktop
        ];
      };

      nixosConfigurations.work-laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          catppuccin.nixosModules.catppuccin
          sops-nix.nixosModules.sops
          {
            nixpkgs.overlays = [ nur.overlays.default ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];
            home-manager.users.d3spair.imports = [
              ./home.nix
              catppuccin.homeModules.catppuccin
            ];
            home-manager.extraSpecialArgs = { inherit inputs; };
          }
          ./hosts/work-laptop
        ];
      };

      nixosConfigurations.home-laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          catppuccin.nixosModules.catppuccin
          sops-nix.nixosModules.sops
          {
            nixpkgs.overlays = [ nur.overlays.default ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.sharedModules = [ sops-nix.homeManagerModules.sops ];
            home-manager.users.d3spair.imports = [
              ./home.nix
              catppuccin.homeModules.catppuccin
            ];
            home-manager.extraSpecialArgs = { inherit inputs; };
          }
          ./hosts/home-laptop
        ];
      };

      # Custom installer ISO
      # nix build .#nixosConfigurations.installer.config.system.build.isoImage
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          disko.nixosModules.disko
          (
            { pkgs, ... }:
            {
              # Flakes enabled in the live env
              nix.settings.experimental-features = [
                "nix-command"
                "flakes"
              ];

              # Stuff you want available in the live installer
              environment.systemPackages = with pkgs; [
                vim
                git
                tpm2-tools
                tpm2-tss
              ];

              # Include your config in the ISO so you don't need network
              environment.etc."nixos-config" = {
                source = self; # embeds the entire flake
              };

              # Optional: auto-login for convenience
              services.getty.autologinUser = "nixos";

              # Optional: wifi firmware for broadcom/intel etc
              hardware.enableRedistributableFirmware = true;
              networking.networkmanager.enable = true;

              # Optional: include an install script
              environment.etc."install.sh" = {
                mode = "0755";
                text = ''
                  #!/usr/bin/env bash
                  set -euo pipefail

                  CONFIG_DIR="/etc/nixos-config"
                  HOSTS=(desktop laptop)

                  echo "=== NixOS Installer ==="
                  echo "Config source: $CONFIG_DIR"
                  echo ""

                  # Select host
                  echo "Available hosts:"
                  for i in "''${!HOSTS[@]}"; do
                    echo "  $((i+1))) ''${HOSTS[$i]}"
                  done
                  echo ""
                  read -rp "Select host (1-''${#HOSTS[@]}): " HOST_NUM
                  HOST="''${HOSTS[$((HOST_NUM-1))]}"
                  echo "Selected: $HOST"
                  echo ""

                  # Show available disks
                  echo "Available disks:"
                  lsblk -d -o NAME,SIZE,MODEL
                  echo ""

                  read -rp "Target disk (e.g. /dev/nvme0n1): " TARGET_DISK
                  read -rp "This will WIPE $TARGET_DISK. Type 'yes' to continue: " CONFIRM
                  [[ "$CONFIRM" == "yes" ]] || exit 1

                  # Create a temp copy so we can patch the disk device
                  WORK=$(mktemp -d)
                  cp -r "$CONFIG_DIR"/. "$WORK"
                  chmod -R u+w "$WORK"

                  # Patch the disk device in disko config
                  sed -i "s|/dev/nvme0n1|$TARGET_DISK|g" \
                    "$WORK/hosts/$HOST/disko.nix"

                  # Run disko
                  echo "Partitioning and formatting..."
                  nix run github:nix-community/disko -- \
                    --mode disko "$WORK/hosts/$HOST/disko.nix"

                  # Install
                  echo "Installing NixOS..."
                  nixos-install --flake "$WORK#$HOST" --no-root-passwd

                  echo ""
                  echo "Done! You can reboot now."
                  echo "Remember to enroll TPM2 after first boot:"
                  echo "  sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-luks \\"
                  echo "    --tpm2-device=auto --tpm2-pcrs=0+7"
                '';
              };
            }
          )
        ];
      };
    };
}
