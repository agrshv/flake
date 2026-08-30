{
  description = "NixOS system config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # millennium.url = "github:SteamClientHomebrew/Millennium/01a7f1f9?dir=packages/nix";
    catppuccin.url = "github:catppuccin/nix/release-26.05";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Do NOT set inputs.nixpkgs.follows here: noctalia's cachix builds are keyed
    # to its own pinned nixpkgs, so overriding it forces a from-source rebuild
    # (cache miss). Track the `cachix` branch to stay on cached commits.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";
    nixflix = {
      url = "github:kiriwalawren/nixflix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Private work-specific modules (VPN profiles, work SSH/git identity, cloud
    # CLIs and their sops secrets). Fetched over SSH from a private GitHub repo;
    # if you are reusing this flake, drop this input and the two
    # `inputs.work.*Modules.default` lines in mkWorkstation below.
    work.url = "git+ssh://git@github.com/agrshv/flake-work.git";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Evaluated once here and handed to every host (NixOS and home-manager) so
      # no module needs to `import nixpkgs-unstable` again.
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      specialArgs = { inherit inputs pkgs-unstable; };

      # A graphical workstation: NixOS + home-manager for d3spair with the shared
      # desktop/work modules wired in. `host` names a directory under ./hosts.
      mkWorkstation =
        host:
        nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            inputs.disko.nixosModules.disko
            inputs.home-manager.nixosModules.home-manager
            inputs.catppuccin.nixosModules.catppuccin
            inputs.sops-nix.nixosModules.sops
            inputs.work.nixosModules.default
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                sharedModules = [
                  inputs.sops-nix.homeManagerModules.sops
                  inputs.nix-index-database.homeModules.default
                ];
                users.d3spair.imports = [
                  ./home.nix
                  inputs.catppuccin.homeModules.catppuccin
                  inputs.noctalia.homeModules.default
                  inputs.work.homeModules.default
                ];
                extraSpecialArgs = specialArgs;
              };
            }
            ./hosts/${host}
          ];
        };
    in
    {
      nixosConfigurations = {
        home-desktop = mkWorkstation "home-desktop";
        home-laptop = mkWorkstation "home-laptop";
        work-laptop = mkWorkstation "work-laptop";

        # Headless. Deploy with:
        #   nixos-rebuild switch --flake .#home-server --target-host home-server.agrshv.dev --sudo --ask-sudo-password
        home-server = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            inputs.disko.nixosModules.disko
            inputs.catppuccin.nixosModules.catppuccin
            inputs.sops-nix.nixosModules.sops
            inputs.nixflix.nixosModules.default
            ./hosts/home-server
          ];
        };

        # Thin bootstrap ISO — see INSTALL.md. Build with `nix build .#installer-iso`.
        installer = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [ ./hosts/installer ];
        };
      };

      packages.${system}.installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
