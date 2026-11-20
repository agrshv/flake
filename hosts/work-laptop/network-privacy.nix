# Keep the laptop quiet on networks it doesn't own (the office Wi-Fi gets
# scanned): no real MAC, no hostname in DHCP, no name-resolution responders,
# nothing to find with a port scan, no service announcements. What is left is
# what joining a network can't avoid: an ARP entry for a random MAC.
{ me, lib, ... }:
{
  networking.networkmanager = {
    # A new random MAC on every connection, for scans and for the link itself
    # (scans are already random, wifi.scanRandMacAddress). A network that pins
    # leases or access to a MAC needs a per-profile override:
    #   nmcli con mod <name> 802-11-wireless.cloned-mac-address stable
    wifi.macAddress = "random";
    ethernet.macAddress = "random";

    # Defaults for every profile; a value set on the profile itself still wins.
    settings.connection = {
      # DHCP option 12 / DHCPv6 FQDN would hand out "work-laptop".
      "ipv4.dhcp-send-hostname" = false;
      "ipv6.dhcp-send-hostname" = false;
      # Client identifiers derived from the (random) MAC, not from the machine
      # id or the interface name, so leases don't link one session to the next.
      "ipv4.dhcp-client-id" = "mac";
      "ipv4.dhcp-iaid" = "mac";
      "ipv6.dhcp-duid" = "ll";
      "ipv6.dhcp-iaid" = "mac";
      # SLAAC: temporary addresses, preferred for outgoing connections.
      "ipv6.ip6-privacy" = 2;
    };
  };

  # LLMNR and mDNS both answer for "work-laptop" on the LAN, and LLMNR is what
  # Responder-style poisoning feeds on. NetBird names (*.netbird.cloud) are
  # unicast DNS on wt0 and don't need either.
  services.resolved.settings.Resolve = {
    LLMNR = false;
    MulticastDNS = false;
  };

  networking.firewall = {
    allowPing = false;

    # sshd only over NetBird.
    interfaces.wt0.allowedTCPPorts = [ 22 ];

    # KDE Connect (programs.kdeconnect in common/desktop.nix opens 1714-1764
    # both ways). With its broadcasts off (below) the phone does the finding:
    # its UDP identity packet arrives on udp/1716 and kdeconnectd dials the
    # phone back over TCP, so no TCP listener needs to be reachable for that.
    # tcp/1739-1764 stays open for files sent *to* the phone: the laptop
    # listens there for the duration of the transfer and the phone connects in.
    # A scan then finds nothing, short of someone faking a KDE Connect
    # broadcast and getting a TLS connection back from the laptop.
    allowedTCPPortRanges = lib.mkForce [
      {
        from = 1739;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = lib.mkForce [ ];
    allowedUDPPorts = [ 1716 ];

    # kdeconnectd announces itself (device name and id) over mDNS from its own
    # responder, with no setting to turn it off. resolved's is off above, so
    # the user's mDNS traffic is only that; dropping it keeps discovery
    # one-way. -D first: extraCommands runs again on every firewall reload,
    # and OUTPUT isn't one of the chains the firewall flushes.
    extraCommands = ''
      ip46tables -D OUTPUT -p udp --dport 5353 -m owner --uid-owner ${me.user} -j DROP 2>/dev/null || true
      ip46tables -A OUTPUT -p udp --dport 5353 -m owner --uid-owner ${me.user} -j DROP
    '';
    extraStopCommands = ''
      ip46tables -D OUTPUT -p udp --dport 5353 -m owner --uid-owner ${me.user} -j DROP 2>/dev/null || true
    '';
  };
  services.openssh.openFirewall = false;

  # The other half of KDE Connect's announcing: the identity broadcast to
  # 255.255.255.255:1716 on every network change. This also skips unicast
  # packets to manually added device IPs; the phone still reaches the laptop
  # by broadcasting, or by adding the laptop's IP on the phone. The catch: the
  # laptop no longer pings the phone after joining a network, so reconnecting
  # waits for the phone to broadcast (opening the app, or its own network change).
  home-manager.users.${me.user}.systemd.user.services.kdeconnect.Service.Environment = [
    "KDECONNECT_DISABLE_UDP_BROADCAST=1"
  ];
}
