{
  services.navidrome = {
    enable = true;
    settings = {
      EnableInsightsCollector = true;
      BaseUrl = "https://music.agrshv.dev";
      Deezer.Enabled = false;
      DefaultTheme = "Auto";
      LastFM.Enabled = false;
    };
  };
  
  services.nginx = {
    virtualHosts = {
      "music.agrshv.dev" = {
        forceSSL = true;
        useACMEHost = "agrshv.dev";
        locations."/".proxyPass = "http://127.0.0.1:4533";
      };
    };
  };
}
