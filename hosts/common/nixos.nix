{ pkgs-unstable, ... }:
{
  # security.lockKernelModules = true;

  services.netbird = {
    enable = true;
    # nixos-26.05 ships netbird 0.71.4, which predates the protocol change that
    # carries account-managed DNS zones: the management server now sends them in
    # NetworkMap.account_zones (field 16), a field 0.71.4's protobuf doesn't know
    # and therefore silently discards. Symptom is that peer FQDNs
    # (*.netbird.cloud, delivered the old way via custom_zones) resolve fine
    # while records from a zone managed in the NetBird dashboard never arrive —
    # `netbird status` reports "Nameservers: 0/0" and the local resolver
    # forwards those names straight to the upstream LAN DNS. Track unstable
    # until stable catches up.
    package = pkgs-unstable.netbird;
  };

  services.openssh = {
    enable = true;
    startWhenNeeded = true;
    settings.PasswordAuthentication = false;
  };

  # Show asterisks while typing the sudo password.
  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';
}
