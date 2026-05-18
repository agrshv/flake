{ config, ... }:
{
  xdg = {
    autostart.enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;

      download = "${config.home.homeDirectory}/Downloads";
      desktop = "${config.home.homeDirectory}/Desktop";
      documents = "${config.home.homeDirectory}/Documents";

      publicShare = "${config.home.homeDirectory}/.local/Public";
      templates = "${config.home.homeDirectory}/.local/Templates";

      music = "${config.home.homeDirectory}/Media/Music";
      pictures = "${config.home.homeDirectory}/Media/Pictures";
      videos = "${config.home.homeDirectory}/Media/Videos";
    };
    mimeApps = {
      enable = true;
      #TODO research into xdg.mimeApps.defaultApplicationPackages
      defaultApplications = {
        "text/html" = [ "brave-browser.desktop" ]; # or com.brave.Browser.desktop
        "x-scheme-handler/discord" = [ "vesktop.desktop" ];
        "x-scheme-handler/tg" = [ "org.telegram.desktop.desktop" ];
        "x-scheme-handler/tonsite" = [ "org.telegram.desktop.desktop" ];
      };
      associations.added = {
        "x-scheme-handler/tg" = [ "org.telegram.desktop.desktop" ];
        "x-scheme-handler/tonsite" = [ "org.telegram.desktop.desktop" ];
      };
    };
  };
}
