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
    ./amneziawg.nix
    ./xray.nix
    ./ntfy.nix
    ./postgresql.nix
    ./restic.nix
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

  # drake is the NetBird routing peer / exit node, so it needs IP forwarding:
  # "server" is what makes the module set net.ipv4.conf.all.forwarding and
  # net.ipv6.conf.all.forwarding. The v4 half was already on, but only as a
  # side effect of networking.nat.enable in ./amneziawg.nix — dropping
  # AmneziaWG would have silently killed exit-node routing with nothing in the
  # netbird config to explain it. The v6 half was off entirely (the nat module
  # only sets the v6 sysctls under enableIPv6, which this host doesn't set).
  #
  # Masquerading is deliberately not configured here: the NetBird client
  # installs its own NAT rules for the routes it serves, toggled per-route in
  # the dashboard — which is why networking.nat.internalInterfaces covers only
  # awg0. NB: the peer port (udp/51820) is opened in the NixOS firewall by the
  # module, but the OCI security list gates it a second time; without that
  # peers never connect directly and every flow falls back to a TURN relay.
  services.netbird.useRoutingFeatures = "server";

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
