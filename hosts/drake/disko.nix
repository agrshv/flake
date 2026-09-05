{ ... }:
{
  # drake's own layout: the same GPT + btrfs-subvolume scheme as
  # ../common/disko.nix, minus LUKS — a headless cloud VM has no TPM and
  # nobody at a console, so a passphrase would strand every reboot. The boot
  # volume is a paravirtualized (virtio-scsi) OCI block volume, always /dev/sda.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
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
        root = {
          size = "100%";
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
                  swap.swapfile.size = "4G";
                };
              };
          };
        };
      };
    };
  };
}
