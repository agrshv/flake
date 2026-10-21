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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hardware quirk profiles, imported per host. Its nixpkgs input is only
    # used by its own checks, so follow ours rather than let a third nixpkgs
    # into the lock.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Do NOT set inputs.nixpkgs.follows here: noctalia's cachix builds are keyed
    # to its own pinned nixpkgs, so overriding it forces a from-source rebuild
    # (cache miss). Track the `cachix` branch to stay on cached commits.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
    # No binary cache behind this one, so it builds from source either way;
    # follow ours rather than fetch a third nixpkgs just for the greeter.
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Unlike noctalia, umbriel publishes no binary cache, so it builds from
    # source either way; follow our unstable (it pins nixos-unstable upstream
    # and needs wlroots_0_20) instead of fetching a third nixpkgs.
    umbriel = {
      url = "github:noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    # Kubernetes TUI (k9s replacement). Do NOT set inputs.nixpkgs.follows: the
    # nkl-sofka cachix builds (substituter in hosts/common/desktop.nix) are
    # keyed to upstream's own nixpkgs, so following ours forces a local build.
    sofka.url = "github:nklmilojevic/sofka";
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
      # drake is the one aarch64 host; everything else is x86_64.
      systems = [
        system
        "aarch64-linux"
      ];
      me = import ./hosts/common/me.nix;

      # Evaluated once per system here and handed to every host (NixOS and
      # home-manager) so no module needs to `import nixpkgs-unstable` again.
      # The attrset is lazy, so the aarch64 one is only instantiated for drake.
      pkgs-unstable = nixpkgs.lib.genAttrs systems (
        sys:
        import nixpkgs-unstable {
          system = sys;
          config.allowUnfree = true;
        }
      );
      specialArgsFor = sys: {
        inherit inputs;
        pkgs-unstable = pkgs-unstable.${sys};
      };
      specialArgs = specialArgsFor system;

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

      # A headless server: NixOS with disko + sops, no home-manager.
      mkServer =
        {
          host,
          system ? "x86_64-linux",
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = specialArgsFor system;
          modules = [
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
            revision
            ./hosts/${host}
          ];
        };
    in
    {
      nixosConfigurations = {
        work-laptop = mkWorkstation "work-laptop";

        # Headless. Deploy with:
        #   nh os switch -H home-server --target-host home-server.agrshv.dev --build-host home-server.agrshv.dev
        home-server = mkServer { host = "home-server"; };

        # Oracle Cloud Ampere VM (aarch64, UEFI, virtio). Headless; no LUKS.
        # Install and day-2 deploys: see INSTALL.md "drake". Closures are built
        # on the box itself — this machine can't build aarch64 locally:
        #   nh os switch -H drake --target-host drake --build-host drake
        drake = mkServer {
          host = "drake";
          system = "aarch64-linux";
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

      # Every host's system closure, grouped by the platform it builds on.
      # `nix flake check --no-build` evaluates them all (what CI runs); a plain
      # `nix flake check` also builds this machine's x86_64 hosts, home-server
      # included — slow, so only when a real build is wanted.
      checks = nixpkgs.lib.genAttrs systems (
        sys:
        nixpkgs.lib.mapAttrs (_: host: host.config.system.build.toplevel) (
          nixpkgs.lib.filterAttrs (
            _: host: host.pkgs.stdenv.hostPlatform.system == sys
          ) self.nixosConfigurations
        )
      );

      packages.${system}.installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;

      # `nix fmt` / `nix fmt -- --ci`, in the style every .nix file here is
      # already written in. nixfmt-tree is nixfmt wrapped in treefmt, so a bare
      # `nix fmt` walks the whole tree (plain nixfmt would read stdin). aarch64
      # is covered so it also works on drake.
      formatter = nixpkgs.lib.genAttrs systems (sys: nixpkgs.legacyPackages.${sys}.nixfmt-tree);
    };
}
