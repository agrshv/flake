{ config, pkgs, ... }:
{
  sops.secrets."stalwart/noctalia".sopsFile = ../secrets/common.yaml;

  # kdeconnectd user service; niri doesn't run XDG autostart entries, so the
  # NixOS module alone wouldn't get the daemon started.
  services.kdeconnect.enable = true;

  # Noctalia's KDE Connect widget shells out to gdbus for DBus calls and
  # mounts device filesystems over sshfs.
  home.packages = [
    pkgs.glib # gdbus
    pkgs.sshfs
  ];

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      bar.default.start = [
        "launcher"
        "workspaces"
      ];
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
      lockscreen_widgets = {
        enabled = true;
        schema_version = 2;
        widget_order = [
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
          "lockscreen-login-box@DP-2" = {
            box_height = 0.0;
            box_width = 0.0;
            cx = 960.0;
            cy = 957.0;
            output = "DP-2";
            rotation = 0.0;
            type = "login_box";
          };
          settings = {
            background_color = "surface_variant";
            background_opacity = 0.88;
            background_radius = 12.0;
            input_opacity = 1.0;
            input_radius = 6.0;
            show_login_button = true;
          };
          "lockscreen-widget-clock" = {
            box_height = 160.0;
            box_width = 288.0;
            cx = 960.0;
            cy = 220.0;
            output = "eDP-1";
            rotation = 0.0;
            type = "clock";
          };
        };
      };
      nightlight.enabled = true;
      shell.launch_apps_as_systemd_services = true;
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };
      wallpaper = {
        enabled = true;
        default.path = "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png";
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
