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
    # Unlike noctalia, umbriel publishes no binary cache, so it builds from
    # source either way; follow our unstable (it pins nixos-unstable upstream
    # and needs wlroots_0_20) instead of fetching a third nixpkgs.
    umbriel = {
      url = "github:noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixflix = {
      url = "github:kiriwalawren/nixflix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # k9s replacement (see programs/k9s.nix — both are installed for now).
    # Upstream pins nixos-26.05 too, so following our nixpkgs dedupes the lock
    # without moving sofka off the nixpkgs it is tested against; there is no
    # binary cache either way, so it builds from source.
    sofka = {
      url = "github:nklmilojevic/sofka";
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
      me = import ./hosts/common/me.nix;

      # Evaluated once here and handed to every host (NixOS and home-manager) so
      # no module needs to `import nixpkgs-unstable` again. drake is the one
      # aarch64 host, so it gets its own instantiation below.
      mkPkgsUnstable =
        system:
        import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      pkgs-unstable = mkPkgsUnstable system;
      specialArgs = { inherit inputs pkgs-unstable; };

      # Stamp each host with the commit it was built from, so
      # `nixos-version --configuration-revision` on a box that was deployed by
      # hand (home-server, drake) says exactly what is running there.
      revision = {
        system.configurationRevision = self.rev or self.dirtyRev or "dirty";
      };

      # A graphical workstation: NixOS + home-manager for me.user with the shared
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
                # Rename a conflicting file instead of aborting activation: a
                # program that writes its own config before home-manager takes
                # the file over (~/.claude/settings.json, mimeapps.list, ...)
                # otherwise fails the switch with "would be clobbered".
                backupFileExtension = "hm-bak";
                sharedModules = [
                  inputs.sops-nix.homeManagerModules.sops
                  inputs.nix-index-database.homeModules.default
                ];
                users.${me.user}.imports = [
                  ./home.nix
                  inputs.catppuccin.homeModules.catppuccin
                  inputs.noctalia.homeModules.default
                  inputs.umbriel.homeModules.default
                  inputs.work.homeModules.default
                ];
                extraSpecialArgs = specialArgs;
              };
            }
            revision
            ./hosts/${host}
          ];
        };
    in
    {
      nixosConfigurations = {
        work-laptop = mkWorkstation "work-laptop";

        # Headless. Deploy with:
        #   nixos-rebuild switch --flake .#home-server --target-host home-server.agrshv.dev --build-host home-server.agrshv.dev --sudo --ask-sudo-password
        home-server = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            inputs.disko.nixosModules.disko
            inputs.catppuccin.nixosModules.catppuccin
            inputs.sops-nix.nixosModules.sops
            inputs.nixflix.nixosModules.default
            revision
            ./hosts/home-server
          ];
        };

        # Oracle Cloud Ampere VM (aarch64, UEFI, virtio). Headless; no LUKS.
        # Install and day-2 deploys: see INSTALL.md "drake". Closures are built
        # on the box itself — this machine can't build aarch64 locally.
        drake = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit inputs;
            pkgs-unstable = mkPkgsUnstable "aarch64-linux";
          };
          modules = [
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
            revision
            ./hosts/drake
          ];
        };

        # Thin bootstrap ISO — see INSTALL.md. Build with `nix build .#installer-iso`.
        installer = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            revision
            ./hosts/installer
          ];
        };
      };

      packages.${system}.installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;

      # `nix fmt` / `nix fmt -- --check`, in the style every .nix file here is
      # already written in. aarch64 is covered so it also works on drake.
      formatter = nixpkgs.lib.genAttrs [ system "aarch64-linux" ] (
        sys: nixpkgs.legacyPackages.${sys}.nixfmt
      );
    };
}
