# flake

NixOS and home-manager configuration for my machines, in one flake on
`nixos-26.05`.

| Host          | What it is                                                                                     |
| ------------- | ---------------------------------------------------------------------------------------------- |
| `work-laptop` | Zenbook laptop: mango + noctalia desktop, home-manager for the user, work modules               |
| `home-server` | AMD box at home: Immich, Jellyfin and the *arr stack, Forgejo, Paperless, Vaultwarden and more behind nginx, limited to Kazakhstan and the LAN/VPN |
| `drake`       | Oracle Cloud Ampere VM (aarch64): Stalwart mail, AmneziaWG and Xray, ntfy, NetBird exit node   |
| `installer`   | Thin bootstrap ISO; it carries no config (see [INSTALL.md](INSTALL.md))                        |

## Layout

```
flake.nix            inputs, host builders (mkWorkstation / mkServer), deploy-rs nodes, checks
home.nix             home-manager entry point for the laptop user
programs/            one home-manager module per program (nvim config under programs/nvim)
hosts/common/        shared NixOS modules: base system, desktop, disko layout, ntfy alerts, me.nix
hosts/<host>/        per-host config; one file per service, plus facter.json (hardware report)
secrets/             sops-encrypted secrets, recipients in .sops.yaml
treefmt.nix          formatters and linters behind `nix fmt`
INSTALL.md           installing a host, first boot, deploys
```

Every host gets `me` (login user and SSH key, from `hosts/common/me.nix`),
`inputs` and `pkgs-unstable` as module arguments. Hardware is detected from
each host's `facter.json` rather than a generated `hardware-configuration.nix`.

## Everyday use

```sh
nh os switch                          # rebuild and switch this machine
nix run .#deploy -- .#home-server     # deploy a server (or .#drake, or . for both)
nix fmt                               # format and lint everything
nix flake check --no-build            # evaluate every host, as CI does
```

Servers are deployed with deploy-rs: it builds on the server, asks for the
sudo password, and rolls back automatically if the server can't be reached
after activation. Installing a new machine is covered in
[INSTALL.md](INSTALL.md).

CI (`.github/workflows/check.yml`) runs `nix fmt -- --ci` and evaluates every
host on each push. A weekly workflow opens a PR that updates `flake.lock`.

## Reusing this

Two inputs are private repos fetched over SSH, so the flake won't evaluate
for anyone else as-is:

- `work`: VPN profiles, work SSH/git identity, cloud CLIs. Drop the input and
  the two `inputs.work.*Modules.default` lines in `mkWorkstation`.
- `jobscout`: a nightly job-ad scout on drake. Drop the input and its two
  imports in `hosts/drake/default.nix`.

Secrets are encrypted to my age keys, so you'll need your own `.sops.yaml` and
`secrets/`. Replace `hosts/common/me.nix` with your own user and key.
