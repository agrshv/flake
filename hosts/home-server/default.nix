{
  me,
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ../common/disko.nix
    ../common/nixos.nix
    ../common/ntfy-alerts.nix
    ../common/monitoring-agent.nix
    ./metrics.nix

    # AMD box on a SATA SSD. Both of these only pin what NixOS already
    # defaults to here (microcode updates, weekly fstrim) — they are in for
    # the same reason the laptop has them: upstream additions for this class
    # of hardware land automatically. amd_pstate is deliberately not enabled:
    # it is a kernel param, so it would need a reboot, and this box asks for
    # the LUKS passphrase on the way up.
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-pc-ssd

    ./arr.nix
    ./authelia.nix
    ./blocky.nix
    ./bulwark.nix
    ./forgejo.nix
    ./forgejo-runner.nix
    ./gonic.nix
    ./grampsweb.nix
    ./nocodb.nix
    ./dufs.nix
    ./immich.nix
    ./jellyfin.nix
    ./kavita.nix
    ./mealie.nix
    ./miniflux.nix
    ./monica.nix
    ./navidrome.nix
    ./netbird.nix
    ./nginx.nix
    ./paperless.nix
    ./postgresql.nix
    ./qbittorrent.nix
    ./readeck.nix
    ./redis.nix
    ./restic.nix
    ./romm.nix
    ./searx.nix
    ./seerr.nix
    ./slskd.nix
    ./vaultwarden.nix
    ./wrtag.nix
  ];

  # facter's AMD module adds amd_pstate=active on any bare-metal AMD box and has
  # no switch of its own; drop the module to keep amd_pstate off (see above).
  disabledModules = [ "hardware/facter/amd-cpu.nix" ];

  disko.devices.disk.main.device = "/dev/disk/by-id/ata-Apacer_AST280_480GB_0E4080B001124";

  # home-server decrypts with its own SSH host key, so no human identity has to
  # live on the box (see .sops.yaml for the derived age recipient). /etc/ssh is
  # in the restic path set precisely so this survives a rebuild.
  sops = {
    defaultSopsFile = ../../secrets/home-server.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  # Failure alerts for every unit (../common/ntfy-alerts.nix), published to
  # drake's ntfy over its public HTTPS endpoint — its loopback listener is only
  # reachable from drake itself. `ntfy/env` holds NTFY_TOKEN=<token>, the same
  # write token drake's own alerts use.
  sops.secrets."ntfy/env" = { };
  ntfyAlerts = {
    url = "https://ntfy.agrshv.dev:2443/alerts";
    environmentFile = config.sops.secrets."ntfy/env".path;
  };

  nixpkgs.config.allowUnfree = true;

  boot = {
    initrd = {
      systemd.enable = true;
      luks.devices."cryptroot" = {
        device = "/dev/disk/by-partlabel/disk-main-luks";
        allowDiscards = true;
      };
    };
    loader = {
      efi.canTouchEfiVariables = true;
      limine = {
        enable = true;
        secureBoot = {
          enable = true;
          autoGenerateKeys = true;
          autoEnrollKeys.enable = true;
        };
      };
    };
  };

  hardware.enableRedistributableFirmware = true;

  # VAAPI hardware transcoding for Jellyfin on the Ryzen 5 4600G (Vega 7 iGPU).
  # Mesa's radeonsi provides the VAAPI driver; the render node is /dev/dri/renderD128.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      libva-utils # provides `vainfo` to verify the driver from the CLI
    ];
  };

  networking = {
    hostName = "home-server";
  };

  time.timeZone = "Asia/Almaty";

  # The login/sudo password hash, decrypted with the host key before user
  # creation (neededForUsers → lands under /run/secrets-for-users). With
  # mutableUsers (the default) it only applies when the user is *created*, i.e.
  # on a fresh install — a live host keeps whatever `passwd` last set. The
  # plaintext lives in Bitwarden ("home-server sudo"); deploy-rs asks for it
  # (interactiveSudo) on every deploy. NB: a reinstall must restore
  # /etc/ssh first (see restic.nix) or no sops secret decrypts, this one
  # included — the user is then created passwordless (SSH key still works;
  # fix with a root console + `passwd`).
  sops.secrets."user/hashed-password".neededForUsers = true;

  users.users.${me.user} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];
    hashedPasswordFile = config.sops.secrets."user/hashed-password".path;
    openssh.authorizedKeys.keys = [
      me.sshKey
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    btop
  ];

  system.stateVersion = "25.11";
}
