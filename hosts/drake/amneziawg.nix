{ config, ... }:
let
  # One peer per relative. Client bundles (private key, PSK, QR) are generated
  # off-repo — only public keys live here. Add a peer: generate keys, append
  # here, add the PSK to secrets/drake.yaml, hand out the mirrored client conf.
  peers = [
    {
      name = "r1";
      publicKey = "bf4D87qnOSMmpZXJf7oKuKHOAluJdi7FkU8lms3vNmc=";
      ip = "10.11.0.2";
    }
    {
      name = "r2";
      publicKey = "pm+vPNU50qQslsGKgqytg2JBPSUtkH14QLRcX5530As=";
      ip = "10.11.0.3";
    }
    {
      name = "r3";
      publicKey = "/cm26+QiEpsUkXtAY6NRt+BdquHsiZSTEswTLSsZilQ=";
      ip = "10.11.0.4";
    }
    {
      name = "r4";
      publicKey = "vDqOG4h/nQoljO9fRdknoe0LcHvURZggnWpI5YxMWBk=";
      ip = "10.11.0.5";
    }
  ];
in
{
  sops.secrets =
    {
      "amneziawg/private-key" = { };
    }
    // builtins.listToAttrs (
      map (p: {
        name = "amneziawg/psk-${p.name}";
        value = { };
      }) peers
    );

  networking.wg-quick.interfaces.awg0 = {
    type = "amneziawg";
    address = [ "10.11.0.1/24" ];
    listenPort = 39422;
    privateKeyFile = config.sops.secrets."amneziawg/private-key".path;

    # DPI-evasion junk parameters, mirrored byte-for-byte in every client
    # profile — changing any of them here strands all clients. They are not
    # secrets (H1–H4 and the padding sizes are visible on the wire); the
    # per-peer PSKs above are what actually gate the tunnel.
    extraOptions = {
      Jc = 6;
      Jmin = 50;
      Jmax = 1000;
      S1 = 86;
      S2 = 142;
      H1 = 1023371810;
      H2 = 537604145;
      H3 = 1423277339;
      H4 = 902565492;
    };

    peers = map (p: {
      publicKey = p.publicKey;
      presharedKeyFile = config.sops.secrets."amneziawg/psk-${p.name}".path;
      allowedIPs = [ "${p.ip}/32" ];
    }) peers;
  };

  networking.nat = {
    enable = true;
    externalInterface = "enp0s6";
    internalInterfaces = [ "awg0" ];
  };

  networking.firewall.allowedUDPPorts = [ 39422 ];
}
