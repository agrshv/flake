{ config, ... }:
{
  # NetBird itself is enabled for every host in ../common/nixos.nix; this only
  # adds unattended login, which is a server concern. A workstation can be
  # re-authenticated by hand, but this box is headless — after a rebuild the
  # client comes up in NeedsLogin and there is no browser to finish the flow.
  # The nginx country gate trusts the 100.78.0.0/16 overlay (see ./nginx.nix),
  # so a client stuck at NeedsLogin also costs you that access path.
  #
  # The key must be a **reusable** one (NetBird dashboard → Setup Keys). A
  # one-off key is consumed by the first registration, and any later boot that
  # needs to re-register would fail.
  #
  # No `login.systemdDependencies` entry despite what the option's example
  # suggests: sops.useSystemdActivation is false here, so there is no
  # sops-install-secrets.service to wait on — secrets are written during
  # stage-2 activation, before systemd starts any unit. Naming a unit that
  # doesn't exist would just fail netbird-login.service.
  sops.secrets."netbird/setup-key".restartUnits = [ "netbird-login.service" ];

  # archive.org is blocked here at the IP level, which breaks wrtag's cover
  # downloads: the Cover Art Archive API answers, but redirects the images to
  # archive.org hosts. A NetBird network route (dashboard → Networks, routing
  # peer drake, distributed to this host) sends that traffic out through drake
  # instead. It has to cover both of the Archive's blocks: 207.241.224.0/20
  # (archive.org, ia*.us.archive.org) and 204.62.246.0/23 + 204.62.248.0/23
  # (Internet Archive Canada, dn*.ca.archive.org) — the Canadian data nodes are
  # not blocked but throttled to ~30 KB/s direct, so a 1 MB cover blows wrtag's
  # hardcoded 30s cover-download timeout. A `*.archive.org` domain resource
  # covers both.
  # "client" relaxes the reverse-path filter from strict to loose; without it,
  # replies arrive on wt0 for addresses the kernel expects on the uplink, and
  # strict rpfilter drops them — the route installs but nothing gets through.
  # Same reason as work-laptop, which uses drake as an exit node.
  services.netbird.useRoutingFeatures = "client";

  services.netbird.clients.default.login = {
    enable = true;
    setupKeyFile = config.sops.secrets."netbird/setup-key".path;
  };
}
