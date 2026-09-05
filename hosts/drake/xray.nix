{ config, ... }:
let
  # VLESS + Reality: TCP that is indistinguishable from ordinary HTTPS to the
  # decoy below (the TLS handshake is proxied from it). On 8443, not 443 —
  # stalwart owns 443. One UUID + shortId per relative, matching the vless://
  # links generated off-repo.
  clients = [
    {
      id = "6c4dab45-8e92-4803-b4c0-e3ef4475a4d4";
      email = "r1";
    }
    {
      id = "d61fb641-2351-4a90-9cca-d88b608b1bba";
      email = "r2";
    }
    {
      id = "739eb0b2-0284-441e-b607-0bd24aef67d1";
      email = "r3";
    }
    {
      id = "6569d45e-1f1a-4764-9395-263d8b4e13f7";
      email = "r4";
    }
  ];
  shortIds = [
    "97280058"
    "0099022b"
    "fe125328"
    "891f62db"
  ];
in
{
  sops.secrets."xray/reality-private-key" = { };

  # The private key can't sit in the nix store, so the config is a sops
  # template; the xray unit reads it via LoadCredential (as root), before
  # DynamicUser sandboxing applies.
  sops.templates."xray-config.json".content = builtins.toJSON {
    log.loglevel = "warning";
    inbounds = [
      {
        listen = "0.0.0.0";
        port = 8443;
        protocol = "vless";
        settings = {
          clients = map (c: c // { flow = "xtls-rprx-vision"; }) clients;
          decryption = "none";
        };
        streamSettings = {
          network = "tcp";
          security = "reality";
          realitySettings = {
            dest = "www.samsung.com:443";
            serverNames = [ "www.samsung.com" ];
            privateKey = config.sops.placeholder."xray/reality-private-key";
            inherit shortIds;
          };
        };
        sniffing = {
          enabled = true;
          destOverride = [
            "http"
            "tls"
            "quic"
          ];
        };
      }
    ];
    # Clients get the whole internet, not the VCN/overlay behind the NAT.
    routing.rules = [
      {
        type = "field";
        ip = [ "geoip:private" ];
        outboundTag = "block";
      }
    ];
    outbounds = [
      { protocol = "freedom"; }
      {
        protocol = "blackhole";
        tag = "block";
      }
    ];
  };

  services.xray = {
    enable = true;
    settingsFile = config.sops.templates."xray-config.json".path;
  };

  networking.firewall.allowedTCPPorts = [ 8443 ];
}
