# Installing a host

Every host shares one disk layout (`hosts/common/disko.nix`: GPT, 1G ESP,
LUKS2 root, btrfs subvolumes) and is installed from this flake on GitHub. The
ISO is only a bootstrap: it boots the hardware, joins the network and accepts
the personal SSH key. It never embeds the config, so it does not go stale.

## 0. Build and boot the ISO (once per release)

```sh
nix build .#installer-iso
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot it. The `nixos` user is auto-logged-in on the console and reachable as
`ssh nixos@<ip>` (key only, passwordless sudo). Wi-Fi: `nmtui`.

## Path A — from a workstation with nixos-anywhere (preferred)

Works for anything on the LAN, headless or not. The closure is **built here and
pushed over SSH**, so the target needs no internet and the private `work`
input is evaluated on this machine, where the GitHub key lives.

```sh
# LUKS passphrase file: exact bytes are the passphrase — no trailing newline.
read -rs pw && printf '%s' "$pw" > /tmp/disk.key && unset pw

nix run github:nix-community/nixos-anywhere -- \
  --flake .#home-laptop \
  --disk-encryption-keys /tmp/disk.key /tmp/disk.key \
  --target-host nixos@<ip>
shred -u /tmp/disk.key
```

Target disk is `disko.devices.disk.main.device` (default `/dev/nvme0n1`); pin
the real `/dev/disk/by-id/…` in the host's `default.nix` if it differs.

## Path B — at the console with disko-install

For when only the target machine is at hand. `disko-install` (same pinned
disko as the hosts) formats and installs in one step; `--disk main <dev>`
overrides the device in the config.

```sh
# The `work` input is fetched over SSH, so bring your agent along:
ssh -A nixos@<ip>            # or use the console with a key on a USB stick

read -rs pw && printf '%s' "$pw" | sudo tee /tmp/disk.key >/dev/null && unset pw
lsblk -d -o NAME,SIZE,MODEL
sudo -E disko-install --flake github:agrshv/flake#home-laptop --disk main /dev/nvme0n1
```

`sudo -E` keeps `SSH_AUTH_SOCK` so root can reach the forwarded agent.

## First boot

```sh
passwd                                   # initialPassword is "changeme"
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-luks \
  --tpm2-device=auto --tpm2-pcrs=0+7     # TPM2 unlock; must be done from the
                                         # installed system, not the ISO (PCR 7)
git clone git@github.com:agrshv/flake.git ~/flake   # `nh` expects ~/flake
```
