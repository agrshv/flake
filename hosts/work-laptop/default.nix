{ inputs, pkgs, ... }:
let
  me = import ../common/me.nix;
in
{
  imports = [
    ../common/disko.nix
    ./hardware-configuration.nix
    ../common/nixos.nix
    ../common/desktop.nix

    # Zenbook UM425QA (Ryzen, NVMe). nixos-hardware has no profile for this
    # model, so these are the generic AMD-laptop ones. The pstate module also
    # pulls in common-cpu-amd, and hands frequency scaling to amd_pstate in
    # active mode, which is what power-profiles-daemon drives via EPP.
    # common-pc-laptop would enable TLP, but only when no other power daemon
    # is on — power-profiles-daemon (common/desktop.nix) keeps it off.
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  # Pinned so an install can't land on the Ventoy stick it was booted from.
  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLQ512HALU-00000_S4Y4NS0R633464";

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd = {
      systemd.enable = true;
      luks.devices."cryptroot" = {
        device = "/dev/disk/by-partlabel/disk-main-luks";
        allowDiscards = true;
        # Try the TPM first; with nothing enrolled this falls straight through
        # to the passphrase. Enrolled with a PIN, bound to PCR 7 (Secure Boot
        # state, own keys):
        #   systemd-cryptenroll /dev/disk/by-partlabel/disk-main-luks \
        #     --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes
        # A firmware or dbx update changes PCR 7: boot then asks for the
        # passphrase once — re-enroll with --wipe-slot=tpm2 added. Always keep
        # a typed fallback slot (passphrase or recovery key): it is the way in
        # after that, or with a dead TPM.
        crypttabExtraOpts = [ "tpm2-device=auto" ];
      };
    };
    loader = {
      efi.canTouchEfiVariables = true;
      limine = {
        enable = true;
        # Each generation keeps its own kernel and initrd on the 1 GiB ESP;
        # GC normally prunes them, this caps it if GC ever stops running.
        maxGenerations = 10;
        secureBoot = {
          enable = true;
          # Without this the very first bootloader install aborts: signing needs
          # /var/lib/sbctl, which only exists once keys have been made. Enrolling
          # them is still manual (firmware Setup Mode) — see INSTALL.md.
          autoGenerateKeys = true;
        };
      };
    };
    plymouth = {
      enable = true;
      font = "${pkgs.dejavu_fonts.minimal}/share/fonts/truetype/DejaVuSans.ttf";
    };
  };

  hardware.i2c.enable = true;

  # Firmware updates from LVFS (`fwupdmgr refresh && fwupdmgr update`): little
  # from ASUS itself, but the NVMe drive and UEFI revocation lists (dbx) land
  # there.
  services.fwupd.enable = true;

  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
  # Keep blueman-manager and its daemon, but not the tray applet: noctalia's
  # bluetooth widget already covers it. The package ships an XDG autostart
  # entry that systemd's generator starts at login; a same-named user entry
  # with Hidden=true overrides it per the XDG autostart spec.
  home-manager.users.${me.user}.xdg.configFile."autostart/blueman.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Blueman Applet
    Exec=blueman-applet
    Hidden=true
  '';

  networking.hostName = "work-laptop";

  # This host *uses* an exit node (drake, see hosts/drake/default.nix) rather
  # than being one. "client" relaxes networking.firewall.checkReversePath from
  # strict to loose: with the default route pointed at wt0, replies come back
  # over an interface the reverse-path lookup doesn't expect, and strict rpfilter
  # drops them — the tunnel comes up and then no traffic flows.
  services.netbird.useRoutingFeatures = "client";

  users.users.${me.user}.extraGroups = [ "i2c" ];

  environment.systemPackages = with pkgs; [
    brightnessctl
    ddcutil
  ];

  system.stateVersion = "25.11";
}
