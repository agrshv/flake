let
  # Not a wildcard 53: NetBird's own resolver already holds 100.78.44.236:53
  # (wt0) and podman's aardvark-dns 10.88.0.1:53, and 0.0.0.0:53 would collide
  # with both. So the LAN gets 53 on the LAN address only, and NetBird peers get
  # a separate port on every address (nameserver groups take a port).
  port = 5053;
  # A DHCP lease from the router, so it must be reserved there (static lease),
  # or blocky stops answering the LAN when it changes.
  lanAddress = "192.168.88.23";
in
{
  # Ad/tracker-blocking DNS for the home LAN and for NetBird peers, wherever
  # they are. The LAN side is wired up on the router: DHCP hands out
  # 192.168.88.23 as the DNS server. The NetBird side happens in the NetBird
  # dashboard, not here: DNS → Nameservers → add
  # 100.78.44.236:5053, match all domains, distributed to the peers that should
  # use it. Leave home-server itself out of that group so its own lookups don't
  # depend on blocky being up. Peer names (*.netbird.cloud) and dashboard zones
  # are still answered by each peer's NetBird resolver before anything reaches
  # here.
  #
  # Stateless: lists are re-downloaded on start and every 24h, and there is no
  # query log, so nothing to back up. To let something through temporarily:
  # `blocky blocking disable --duration 10m` on the box (talks to the loopback
  # API below).
  services.blocky = {
    enable = true;
    settings = {
      ports = {
        dns = [
          "${lanAddress}:53"
          ":${toString port}"
        ];
        http = "127.0.0.1:4000";
      };

      # DoH, so the ISP can neither see nor rewrite the lookups (it already
      # interferes at the IP level, see ./netbird.nix). The bootstrap IPs
      # resolve the DoH hostnames themselves without a chicken-and-egg lookup.
      upstreams = {
        groups.default = [
          "https://cloudflare-dns.com/dns-query"
          "https://dns.quad9.net/dns-query"
        ];
        strategy = "parallel_best";
      };
      bootstrapDns = [
        {
          upstream = "https://cloudflare-dns.com/dns-query";
          ips = [
            "1.1.1.1"
            "1.0.0.1"
          ];
        }
        {
          upstream = "https://dns.quad9.net/dns-query";
          ips = [ "9.9.9.9" ];
        }
      ];
      # The box has no IPv6 uplink; don't waste time trying it.
      connectIPVersion = "v4";

      blocking = {
        # HaGeZi Pro: ads, tracking, telemetry, malware, with few false
        # positives. The wildcard variant (`*.domain`) also blocks subdomains.
        denylists.ads = [
          "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt"
        ];
        clientGroupsBlock.default = [ "ads" ];
        # Answer blocked names with 0.0.0.0 rather than NXDOMAIN, so apps fail
        # fast instead of retrying.
        blockType = "zeroIp";
        loading = {
          refreshPeriod = "24h";
          # Start answering before the lists finish downloading rather than
          # holding DNS hostage to GitHub.
          strategy = "fast";
        };
      };

      # Public DNS points git.agrshv.dev at home-server.netbird.cloud, which
      # only NetBird's resolver can answer, so upstream lookups end empty.
      # Forgejo Actions job containers resolve through blocky
      # (./forgejo-runner.nix) and need the forge for actions/checkout. Same
      # address NetBird hands out; nginx's gate admits the containers' 10.x
      # sources. LAN clients without NetBird couldn't reach it before either.
      customDNS.mapping."git.agrshv.dev" = "100.78.44.236";

      caching = {
        minTime = "5m";
        prefetching = true;
      };
    };
  };

  # Binding the LAN address needs it to exist, and blocky can start before
  # dhcpcd has a lease. Allowing non-local binds removes that race instead of
  # making blocky wait for network-online.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  networking.firewall.interfaces = {
    enp4s0 = {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
    };
    wt0 = {
      allowedUDPPorts = [ port ];
      allowedTCPPorts = [ port ];
    };
  };
}
