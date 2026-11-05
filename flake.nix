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
    # `nix fmt` and its flake check; formatters are configured in ./treefmt.nix.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Remote deploys of the servers (`deploy .#<host>`), with rollback if the
    # box stops answering after activation. Only its lib is used: the
    # deploy-rs binary and activate-rs come from our nixpkgs (see deployPkgs),
    # so they're substituted from cache.nixos.org instead of built.
    deploy-rs = {
      url = "github:serokell/deploy-rs";
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
    # Nightly job-ad scout for drake; private repo, fetched over SSH like work.
    jobscout = {
      url = "git+ssh://git@github.com/agrshv/jobscout.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
        inherit inputs me;
        pkgs-unstable = pkgs-unstable.${sys};
      };
      specialArgs = specialArgsFor system;

      treefmt = nixpkgs.lib.genAttrs systems (
        sys: inputs.treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${sys} ./treefmt.nix
      );

      # Stamp each host with the commit it was built from, so
      # `nixos-version --configuration-revision` on a box that was deployed by
      # hand (home-server, drake) says exactly what is running there.
      revision = {
        system.configurationRevision = self.rev or self.dirtyRev or "dirty";
      };

      # Hardware detection from each host's nixos-facter report (kernel
      # modules, microcode, firmware, platform), in place of a generated
      # hardware-configuration.nix. Regenerate on the host (see INSTALL.md):
      #   sudo nix run nixpkgs#nixos-facter -- -o hosts/<host>/facter.json
      facter = host: {
        hardware.facter.reportPath = ./hosts/${host}/facter.json;
      };

      # deploy-rs' lib per system, with the deploy-rs package swapped for
      # nixpkgs' own build (the overlay pattern from its README): activate-rs
      # lands in every deployed closure, and nixpkgs' copy is in the binary
      # cache for aarch64 too, so drake doesn't compile it.
      deployLib = nixpkgs.lib.genAttrs systems (
        sys:
        (import nixpkgs {
          system = sys;
          overlays = [
            inputs.deploy-rs.overlays.default
            (_: super: {
              deploy-rs = {
                inherit (nixpkgs.legacyPackages.${sys}) deploy-rs;
                inherit (super.deploy-rs) lib;
              };
            })
          ];
        }).deploy-rs.lib
      );

      # A deploy-rs node for one of nixosConfigurations, reached at `hostname`.
      mkNode = name: hostname: {
        inherit hostname;
        profiles.system.path =
          let
            host = self.nixosConfigurations.${name};
          in
          deployLib.${host.pkgs.stdenv.hostPlatform.system}.activate.nixos host;
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
            (facter host)
            ./hosts/${host}
          ];
        };

      # A headless server: NixOS with disko + sops, no home-manager.
      # `hostSystem` overrides the default x86_64 platform (drake).
      mkServer =
        {
          host,
          hostSystem ? system,
        }:
        nixpkgs.lib.nixosSystem {
          system = hostSystem;
          specialArgs = specialArgsFor hostSystem;
          modules = [
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
            revision
            (facter host)
            ./hosts/${host}
          ];
        };
    in
    {
      nixosConfigurations = {
        work-laptop = mkWorkstation "work-laptop";

        # Headless. Deployed with deploy-rs; see `deploy` below.
        home-server = mkServer { host = "home-server"; };

        # Oracle Cloud Ampere VM (aarch64, UEFI, virtio). Headless; no LUKS.
        # Install: see INSTALL.md "drake". Deployed with deploy-rs.
        drake = mkServer {
          host = "drake";
          hostSystem = "aarch64-linux";
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
      # Plus `treefmt`, which fails if any file isn't formatted or linted clean.
      checks = nixpkgs.lib.genAttrs systems (
        sys:
        nixpkgs.lib.mapAttrs (_: host: host.config.system.build.toplevel) (
          nixpkgs.lib.filterAttrs (
            _: host: host.pkgs.stdenv.hostPlatform.system == sys
          ) self.nixosConfigurations
        )
        // {
          treefmt = treefmt.${sys}.config.build.check self;
          # No deploy-rs deployChecks: even its schema check takes every node's
          # profile as input, so it would build home-server and drake here.
          # `deploy` validates the same schema itself before it does anything.
        }
      );

      # `nix run .#deploy -- .#home-server` (or `.#drake`, or `.` for both).
      # Logs in as me.user, builds on the target itself (drake is aarch64, and
      # home-server builds its own closures), and asks once for the sudo
      # password (Bitwarden: "home-server sudo" / "drake sudo"). Activation
      # rolls back on its own unless deploy-rs can still reach the box
      # afterwards, so a firewall or netbird mistake can't lock it out.
      deploy = {
        sshUser = me.user;
        user = "root";
        interactiveSudo = true;
        remoteBuild = true;
        nodes = {
          home-server = mkNode "home-server" "home-server.agrshv.dev";
          drake = mkNode "drake" "drake";
        };
      };

      # --skip-checks: deploy-rs otherwise runs a plain `nix flake check` first,
      # which builds every check for this machine — home-server's whole system
      # included. CI already evaluates every host on each push.
      apps.${system}.deploy =
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          type = "app";
          program = toString (
            pkgs.writeShellScript "deploy" ''
              exec ${nixpkgs.lib.getExe' pkgs.deploy-rs "deploy"} --skip-checks "$@"
            ''
          );
          meta.description = "Deploy home-server and drake with deploy-rs";
        };

      packages.${system}.installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;

      # `nix fmt` formats and lints the whole tree; `nix fmt -- --ci` (what CI
      # runs) fails instead of rewriting. aarch64 is covered so it also works
      # on drake.
      formatter = nixpkgs.lib.genAttrs systems (sys: treefmt.${sys}.config.build.wrapper);
    };
}
