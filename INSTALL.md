# Installing a host

Every host shares one disk layout (`hosts/common/disko.nix`: GPT, 1G ESP,
LUKS2 root, btrfs subvolumes) and is installed from this flake on GitHub. The
ISO is only a bootstrap: it boots the hardware, joins the network and accepts
the personal SSH key. It never embeds the config, so it does not go stale.

The private `work` input (`git+ssh://git@github.com/agrshv/flake-work.git`) is
fetched during evaluation, so wherever the evaluation runs needs your GitHub
SSH key — that is what decides which path below you take.

## 0. Build and boot the ISO (once per release)

```sh
nix build .#installer-iso
lsblk -d -o NAME,SIZE,MODEL,TRAN      # identify the USB stick
sudo dd if=result/iso/nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Firmware: **disable Secure Boot** (the ISO is not Microsoft-signed; ASUS: F2 →
Security → Secure Boot). Boot the stick. The `nixos` user is auto-logged-in on
the console and reachable as `ssh nixos@<ip>` (key only, passwordless sudo).

```sh
nmtui          # join Wi-Fi if not on a cable
ip -4 a        # note the IP
```

## Path A — from a second machine with nixos-anywhere (preferred)

The closure is **built on the driving machine and pushed over SSH**: the target
needs no internet access of its own and no GitHub key. The driving machine
needs the flake checked out, Bitwarden unlocked with its SSH agent enabled
(`ssh-add -l` lists the personal key), and to be on the same network.

```sh
cd ~/Documents/flake && git pull

# LUKS passphrase file: the exact bytes are the passphrase — no trailing newline.
read -rs pw && printf '%s' "$pw" > /tmp/disk.key && unset pw

nix run github:nix-community/nixos-anywhere -- \
  --flake .#work-laptop \
  --generate-hardware-config nixos-generate-config ./hosts/work-laptop/hardware-configuration.nix \
  --disk-encryption-keys /tmp/disk.key /tmp/disk.key \
  --target-host nixos@<target-ip>

shred -u /tmp/disk.key
git commit -am "work-laptop: regenerate hardware config" && git push
```

`--generate-hardware-config` runs `nixos-generate-config` on the live target and
writes the result into the checkout before installing — use it whenever the
hardware changed since the file was last generated.

Target disk is `disko.devices.disk.main.device`. The shared default is
`/dev/nvme0n1`; a host whose disk differs — or that gets installed next to a
removable stick worth not formatting — pins its real `/dev/disk/by-id/…` in its
own `default.nix`, as `work-laptop` does. Find the path on the live target with
`ls -l /dev/disk/by-id/ | grep -v -e part -e wwn -e eui`.

nixos-anywhere cannot install the machine it runs on, and its no-USB kexec mode
needs a **wired** interface on the target (the RAM installer has no Wi-Fi
credentials). Wi-Fi-only laptop → boot the ISO and use Path A from another
machine, or Path B.

## Path B — single machine, at the console with disko-install

`disko-install` (same pinned disko as the hosts) formats and installs in one
step; `--disk main <dev>` overrides the device in the config. Evaluation runs
on the target, so it needs the `work` input: carry a copy of the `flake-work`
repo on a stick (it holds only sops-encrypted secrets) and point the lock at it.

```sh
git clone https://github.com/agrshv/flake && cd flake
nix flake lock --override-input work path:/run/media/nixos/<stick>/flake-work

# refresh the hardware config from this machine
sudo nixos-generate-config --no-filesystems --show-hardware-config > hosts/work-laptop/hardware-configuration.nix
git add -A

read -rs pw && printf '%s' "$pw" | sudo tee /tmp/disk.key >/dev/null && unset pw
lsblk -d -o NAME,SIZE,MODEL,SERIAL
sudo disko-install --flake .#work-laptop      # host pins its disk; no --disk needed
```

Alternative to the stick: `ssh -A nixos@<ip>` from a machine whose agent has
the GitHub key, then `sudo -E disko-install --flake github:agrshv/flake#work-laptop`
(`-E` keeps `SSH_AUTH_SOCK` for root). Commit the regenerated hardware config
from the installed system afterwards.

## First boot

Log in as `agrshv` with `changeme`, then, in this order:

```sh
passwd

# 1. Bitwarden Desktop autostarts: Settings → enable "SSH agent". Then:
ssh-add -l                                   # personal key served from the vault
echo $SSH_AUTH_SOCK                          # ~/.bitwarden-ssh-agent.sock

# 2. sops age key. It is derived from the personal SSH *private key file*, not
#    the agent: export the key from Bitwarden to tmpfs, convert, delete.
mkdir -p ~/.config/sops/age
nix run nixpkgs#ssh-to-age -- -private-key -i /run/user/1000/personal_key > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
shred -u /run/user/1000/personal_key

# 3. The flake checkout `nh` expects
git clone git@github.com:agrshv/flake.git ~/Documents/flake
nh os switch                                 # applies sops secrets now that the key exists

# 4. TPM2 unlock as a second LUKS slot. Must run from the installed system, not
#    the ISO: PCR 7 (Secure Boot state) differs between the two.
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-luks --tpm2-device=auto --tpm2-pcrs=0+7
```

If the passphrase prompt still appears on the next boot, add
`crypttabExtraOpts = [ "tpm2-device=auto" ];` to
`boot.initrd.luks.devices.cryptroot` in the host's `default.nix` and switch.

Browser: enable Bitwarden's browser integration in the app (it installs its own
native-messaging manifest for Brave).

## Renaming the login user on an existing host

The workstations use `me.user` (`hosts/common/me.nix`, uid 1000). Switching a
live host to a new name **without** the step below creates a second user and
leaves the old one untouched. Do it from a root shell that is not the user's
own session (e.g. `ssh root@host`, or a tty as root):

```sh
usermod -l agrshv -d /home/agrshv -m d3spair
groupmod -n agrshv d3spair
# then, as agrshv:
nh os switch
```

`home-server` still declares `d3spair` for this reason.

## Day-2 deploys

```sh
nh os switch                                                    # local, as your user
nixos-rebuild switch --flake ~/Documents/flake#home-server --target-host home-server.agrshv.dev --sudo --ask-sudo-password
```

Run these as your user, not root: the `work` input is fetched with your agent.
