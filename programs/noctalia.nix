{
  config,
  lib,
  pkgs,
  ...
}:
let
  wallpapers = "${config.home.homeDirectory}/Media/Pictures/Wallpapers";
  defaultWallpaper = "sam-ferrara-1527pjeb6jg-unsplash.jpg";
  # Fetched from Unsplash rather than committed, and pinned by hash: the photo
  # id in the URL is permanent, the query string picks the encoding, and a
  # re-encode upstream fails the build instead of silently changing the image.
  # The directory itself stays an ordinary one in $HOME rather than a store
  # path, so wallpapers can still be dropped in by hand; only this one is
  # linked, so the default survives a reinstall.
  defaultWallpaperFile = pkgs.fetchurl {
    name = defaultWallpaper;
    url = "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.1.0&q=85&fm=jpg&crop=entropy&cs=srgb&dl=${defaultWallpaper}";
    hash = "sha256-OZTUlNTFrVD7R+R9n3sTGXZ2sGorqumiGm6po8xRdGc=";
  };
in
{
  sops.secrets."stalwart/noctalia".sopsFile = ../secrets/common.yaml;

  # kdeconnectd user service; niri doesn't run XDG autostart entries, so the
  # NixOS module alone wouldn't get the daemon started.
  services.kdeconnect.enable = true;

  # The phone-connect plugin (plugins.enabled below) shells out to gdbus for
  # KDE Connect's DBus calls and mounts device filesystems over sshfs.
  home.packages = [
    pkgs.glib # gdbus
    pkgs.sshfs
  ];

  home.file."Media/Pictures/Wallpapers/${defaultWallpaper}".source = defaultWallpaperFile;

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      bar.default = {
        start = [
          "launcher"
          "workspaces"
        ];
        # noctalia's default end list (config_types.h), restated in full because
        # setting `end` replaces it rather than appending, plus the phone-connect
        # widget next to the laptop's own battery.
        end = [
          "media"
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "icefish/phone-connect:bar"
          "battery"
          "control-center"
          "session"
        ];
      };
      # Phone Connect (community plugin): battery, ring, ping, share, clipboard
      # and pairing for KDE Connect devices, as a bar widget plus a details
      # panel. Its KDE Connect backend is the kdeconnectd user service above;
      # the glib/sshfs packages are its declared dependencies. Like community
      # templates, the plugin itself is fetched at runtime from noctalia's
      # community repo (a git clone under ~/.local/state/noctalia/plugins), so
      # it is not pinned by the lockfile.
      plugins.enabled = [ "icefish/phone-connect" ];
      brightness.enable_ddcutil = true;
      idle = {
        behavior_order = [
          "lock"
          "screen-off"
          "lock-and-suspend"
        ];
        pre_action_fade_seconds = 5;
        behavior = {
          lock = {
            action = "lock";
            enabled = true;
            timeout = 300;
          };
          lock-and-suspend = {
            action = "lock_and_suspend";
            enabled = true;
            timeout = 900;
          };
          screen-off = {
            action = "screen_off";
            enabled = true;
            timeout = 360;
          };
        };
      };
      location.address = "Almaty, Kazakhstan";
      # Ported from the layout arranged in noctalia's settings UI (it lived only
      # in ~/.local/state/noctalia/settings.toml, which overrides this file).
      # Positions are in each output's own pixels, so the layout is tied to
      # these exact outputs. Per-box options and styling go under that box's
      # `.settings` — a sibling `widget.settings` table is read as a widget
      # named "settings" of no type, which is what the validator used to warn
      # about.
      lockscreen_widgets =
        let
          loginBoxOptions = {
            center_password_text = false;
            layout = "regular";
            show_caps_lock = true;
            show_keyboard_layout = true;
            show_login_button = true;
            show_media = true;
            show_session_buttons = true;
            show_unlock_hint = true;
            show_weather = true;
          };
          loginBoxStyle = {
            background_color = "surface_variant";
            background_opacity = 0.88;
            background_radius = 12.0;
            input_opacity = 1.0;
            input_radius = 6.0;
          };
          loginBox =
            output:
            {
              cx,
              cy,
              placement_width ? 0.0,
              placement_height ? 0.0,
              styled ? true,
            }:
            {
              inherit
                output
                cx
                cy
                placement_width
                placement_height
                ;
              box_width = 810.0;
              box_height = 196.0;
              rotation = 0.0;
              type = "login_box";
              settings = loginBoxOptions // lib.optionalAttrs styled loginBoxStyle;
            };
        in
        {
          enabled = true;
          schema_version = 2;
          widget_order = [
            "lockscreen-login-box@HDMI-A-1"
            "lockscreen-login-box@eDP-1"
            "lockscreen-login-box@DP-2"
            "lockscreen-widget-clock"
          ];
          grid = {
            cell_size = 16;
            major_interval = 4;
            visible = true;
          };
          widget = {
            "lockscreen-login-box@HDMI-A-1" = loginBox "HDMI-A-1" {
              cx = 1280.0;
              cy = 1258.0;
              placement_width = 2560.0;
              placement_height = 1440.0;
            };
            "lockscreen-login-box@eDP-1" = loginBox "eDP-1" {
              cx = 960.0;
              cy = 898.0;
              placement_width = 1920.0;
              placement_height = 1080.0;
            };
            # Unstyled, as it was in the UI; drop `styled` to match the others.
            "lockscreen-login-box@DP-2" = loginBox "DP-2" {
              cx = 960.0;
              cy = 957.0;
              styled = false;
            };
            "lockscreen-widget-clock" = {
              box_width = 288.0;
              box_height = 160.0;
              cx = 960.0;
              cy = 220.0;
              output = "eDP-1";
              placement_width = 1920.0;
              placement_height = 1080.0;
              rotation = 0.0;
              type = "clock";
            };
          };
        };
      nightlight.enabled = true;
      shell = {
        polkit_agent = true;
        launch_apps_as_systemd_services = true;
        readline_shortcuts = true;
        greeter_sync.auto_sync = true;
      };
      theme = {
        mode = "light";
        source = "builtin";
        builtin = "Gruvbox";
        # Apps whose colours noctalia owns instead of the catppuccin modules.
        # Both lists are opt-in: empty `builtin_ids`/`community_ids` apply
        # nothing, so only what is named here is ever written.
        #
        # NB: community templates are not part of the noctalia package. They
        # are fetched at runtime from api.noctalia.dev into noctalia's cache
        # (md5-checked against the catalog) and so are neither pinned by the
        # lockfile nor available offline on a fresh machine.
        templates = {
          enable_builtin_templates = true;
          # gtk3/gtk4 share one apply.sh that adds an @import of the generated
          # noctalia.css to each gtk.css. home-manager owns settings.ini in
          # those directories but not gtk.css, so the two do not collide.
          builtin_ids = [
            "ghostty"
            "gtk3"
            "gtk4"
          ];
          enable_community_templates = true;
          # zed: writes ~/.config/zed/themes/noctalia.json with four variants
          # (Noctalia {Dark,Light}[ Transparent]); programs/zed.nix selects by
          # name. discord: writes three stylesheets into the themes directory
          # of whichever clients are installed — programs/vesktop.nix enables
          # noctalia-material.theme.css. telegram: drops a .tdesktop-theme into
          # ~/.config/telegram-desktop/themes, which has to be picked once from
          # Settings → Chat Settings → Themes, as the client keeps that choice
          # in its own state. None of the three has an apply hook, so read-only
          # settings files home-manager owns are untouched.
          community_ids = [
            "discord"
            "telegram"
            "zed"
          ];
        };
      };
      wallpaper = {
        enabled = true;
        # `directory` is what the wallpaper picker browses; `default.path` is
        # the one it starts on, which home-manager links in below.
        directory = wallpapers;
        default.path = "${wallpapers}/${defaultWallpaper}";
      };
      widget = {
        media.hide_when_no_media = true;
        tray.hidden = [ "nm-applet" ];
      };
      calendar = {
        enabled = true;
        account.stalwart = {
          color = "primary";
          credential_source = "file";
          name = "Personal Calendar";
          password_file = config.sops.secrets."stalwart/noctalia".path;
          provider = "custom";
          server_url = "https://mail.agrshv.dev/dav/cal";
          type = "caldav";
          username = "d3spair@agrshv.dev";
        };
      };
    };
  };
}
