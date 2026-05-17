{ config, ... }:
{
  xdg = {
    autostart.enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;

      download = "${config.home.homeDirectory}/downloads";
      desktop = "${config.home.homeDirectory}/desktop";
      documents = "${config.home.homeDirectory}/documents";

      publicShare = "${config.home.homeDirectory}/.local/public";
      templates = "${config.home.homeDirectory}/.local/templates";

      music = "${config.home.homeDirectory}/media/music";
      pictures = "${config.home.homeDirectory}/media/pictures";
      videos = "${config.home.homeDirectory}/media/videos";
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
