{ lib, ... }:
{
  # One layout for every host: GPT, 1G ESP, LUKS2 over the rest, btrfs subvolumes
  # inside. The LUKS container is opened by partlabel (see each host's
  # boot.initrd.luks.devices), so the device path below only matters at install
  # time. It is a default: a host may pin its real /dev/disk/by-id/… path, and
  # `disko-install --disk main /dev/…` overrides it on the command line.
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # Initial passphrase, read from this file at format time (both
            # disko-install and nixos-anywhere upload it — see INSTALL.md). The
            # file's exact bytes are the passphrase, so write it without a
            # trailing newline. After first boot, enroll TPM2 as a second slot.
            passwordFile = "/tmp/disk.key";
            settings = {
              allowDiscards = true;
              bypassWorkqueues = true;
            };
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes =
                let
                  opts = [
                    "compress=zstd"
                    "noatime"
                  ];
                in
                {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = opts;
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = opts;
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = opts;
                  };
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = opts;
                  };
                  "/var-log" = {
                    mountpoint = "/var/log";
                    mountOptions = opts;
                  };
                  "/swap" = {
                    mountpoint = "/swap";
                    swap.swapfile.size = "8G";
                  };
                };
            };
          };
        };
      };
    };
  };
}
