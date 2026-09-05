{ config, pkgs, ... }:
let
  me = import ../common/me.nix;
in
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ../common/nixos.nix
    ./stalwart.nix
  ];

  # Same scheme as home-server: the host decrypts with its own SSH host key
  # (see .sops.yaml for the derived age recipient). A reinstall must carry
  # /etc/ssh across (--extra-files) or re-derive the recipient.
  sops = {
    defaultSopsFile = ../../secrets/drake.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
  };

  # OCI's "Console Connection" (the break-glass path if a deploy goes wrong)
  # attaches to the serial port; keep it as the primary console.
  boot.kernelParams = [
    "console=tty1"
    "console=ttyAMA0,115200"
  ];

  networking.hostName = "drake";

  time.timeZone = "UTC";

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        me.user
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    optimise.automatic = true;
    channel.enable = false;
  };

  # Login/sudo password hash, as on home-server. With mutableUsers it only
  # applies at user creation; the live box got the same password via passwd
  # right after this secret was minted. Plaintext: Bitwarden, "drake sudo".
  sops.secrets."user/hashed-password".neededForUsers = true;

  users.users.${me.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets."user/hashed-password".path;
    openssh.authorizedKeys.keys = [ me.sshKey ];
  };

  # Deploys run as root@drake: the box is aarch64, so closures are built on
  # the host itself (see INSTALL.md "drake").
  users.users.root.openssh.authorizedKeys.keys = [ me.sshKey ];

  environment.systemPackages = with pkgs; [
    vim
    git
    btop
  ];

  system.stateVersion = "26.05";
}
