{ config, ... }:
let
  inherit (config.xdg)
    configHome
    dataHome
    stateHome
    cacheHome
    ;
in
{
  # Keep $HOME clean (xdg-ninja). xdg.enable exports XDG_{CONFIG,DATA,STATE,CACHE}_HOME;
  # preferXdgDirectories moves HM-written files (e.g. gtkrc-2.0) under ~/.config.
  home.preferXdgDirectories = true;
  home.pointerCursor.dotIcons.enable = false; # the cursor is also linked into ~/.local/share/icons
  xresources.path = "${configHome}/X11/xresources";
  programs.bash.historyFile = "${stateHome}/bash/history";

  home.sessionVariables = {
    ANSIBLE_HOME = "${dataHome}/ansible";
    AWS_CONFIG_FILE = "${configHome}/aws/config";
    AWS_SHARED_CREDENTIALS_FILE = "${configHome}/aws/credentials";
    CUDA_CACHE_PATH = "${cacheHome}/nv";
    DOCKER_CONFIG = "${configHome}/docker";
    GNUPGHOME = "${dataHome}/gnupg";
    NPM_CONFIG_CACHE = "${cacheHome}/npm";
  };

  xdg = {
    enable = true;
    autostart.enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      # Adopt the 26.05 default: don't export XDG_*_DIR as session variables.
      # Apps read ~/.config/user-dirs.dirs, which is still generated.
      setSessionVariables = false;

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
        # brave-origin's own desktop file (programs/chromium.nix).
        "text/html" = [ "brave-origin.desktop" ];
        "x-scheme-handler/http" = [ "brave-origin.desktop" ];
        "x-scheme-handler/https" = [ "brave-origin.desktop" ];
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
