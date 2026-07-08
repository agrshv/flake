{ pkgs, ... }: {
  nixflix = {
    enable = true;
    nginx = {
      enable = true;
      domain = "agrshv.dev";
      forceSSL = true;
      enableACME = true;
    };
    postgres.enable = true;
    torrentClients.qbittorrent = {
      enable = true;
      password._secret = "/root/nixflix/qbittorrent/webui_password";
      serverConfig.Preferences.WebUI = {
        Username = "d3spair";
        AlternativeUIEnabled = true;
        RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
      };
    };
    jellyfin = {
      enable = true;
      apiKey._secret = "/root/nixflix/jellyfin/api_key";
      users.d3spair = {
        policy.isAdministrator = true;
        password._secret = "/root/nixflix/jellyfin/d3spair_password";
      };
    };
    prowlarr = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/prowlarr/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/prowlarr/d3spair_password";
        };
        indexers = [
          {
            name = "Milkie";
            baseUrl = "https://milkie.cc/";
            apikey._secret = "/root/nixflix/prowlarr/milkie_api_key";
          }
          {
            name = "RuTracker.org";
            enable = false;
            baseUrl = "https://rutracker.org/";
            username = "MadAndSlowly";
            password._secret = "/root/nixflix/prowlarr/rutracker_password";
          }
          {
            name = "Nyaa.si";
            baseUrl = "https://nyaa.si/";
          }
          {
            name = "LimeTorrents";
            baseUrl = "https://www.limetorrents.fun/";
          }
        ];
      };
    };

    sonarr = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/sonarr/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/sonarr/d3spair_password";
        };
      };
    };

    sonarr-anime = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/sonarr-anime/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/sonarr-anime/d3spair_password";
        };
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/radarr/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/radarr/d3spair_password";
        };
      };
    };
  };
}
