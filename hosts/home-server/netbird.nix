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

  services.netbird.clients.default.login = {
    enable = true;
    setupKeyFile = config.sops.secrets."netbird/setup-key".path;
  };
}
