{
  pkgs,
  lib,
  config,
  ...
}:

let
  modifier = config.wayland.windowManager.sway.config.modifier;
in
{
  wayland.windowManager.sway = {
    enable = true;
    config = {
      defaultWorkspace = "workspace number 1";
      terminal = lib.getExe pkgs.ghostty;
      menu = lib.getExe pkgs.fuzzel;
      modifier = "Mod4";
      bindkeysToCode = true;
      input = {
        "type:keyboard" = {
          repeat_rate = "50";
          repeat_delay = "300";
          xkb_layout = "us,ru";
          xkb_options = "grp:alt_shift_toggle";
        };
        "type:pointer".accel_profile = "flat";
        "type:touchpad" = {
          natural_scroll = "enabled";
          tap = "enabled";
        };
      };
      output = {
        # "*".bg =
        #   "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png fill";
        "DP-2" = {
          mode = "1920x1080@239.757Hz";
          adaptive_sync = "on";
        };
        "HDMI-A-1" = {
          mode = "2560x1440@99.946Hz";
          position = "0 0";
        };
        "eDP-1".position = "0 1440";
      };
      bars = [ ]; # Disabled in favor of waybar
      colors = {
        focused = {
          border = "$lavender";
          background = "$base";
          text = "$text";
          indicator = "$rosewater";
          childBorder = "$lavender";
        };
        focusedInactive = {
          border = "$overlay0";
          background = "$base";
          text = "$text";
          indicator = "$rosewater";
          childBorder = "$overlay0";
        };
        unfocused = {
          border = "$overlay0";
          background = "$base";
          text = "$text";
          indicator = "$rosewater";
          childBorder = "$overlay0";
        };
        urgent = {
          border = "$peach";
          background = "$base";
          text = "$peach";
          indicator = "$overlay0";
          childBorder = "$peach";
        };
        placeholder = {
          border = "$overlay0";
          background = "$base";
          text = "$text";
          indicator = "$overlay0";
          childBorder = "$overlay0";
        };
        background = "$base";
      };
      window.commands = [
        {
          command = "inhibit_idle focus";
          criteria = {
            app_id = "forzahorizon6.exe";
          };
        }
        {
          command = "fullscreen enable";
          criteria = {
            app_id = "forzahorizon6.exe";
          };
        }
      ];
      keybindings = lib.mkOptionDefault {
        "${modifier}+Shift+S" =
          ''exec pgrep -x slurp || ${lib.getExe pkgs.grim} -g "$(${lib.getExe pkgs.slurp})" - | ${lib.getExe' pkgs.wl-clipboard "wl-copy"} -t image/png'';
        "${modifier}+Escape" = "exec noctalia msg session lock";
        "${modifier}+D" = "exec noctalia msg panel-toggle launcher";
        "${modifier}+S" = "exec noctalia msg panel-toggle control-center";
        "${modifier}+Comma" = "exec noctalia msg settings-toggle";
      };
      extraConfig = ''
        bindsym --locked XF86AudioRaiseVolume exec noctalia msg volume-up
        bindsym --locked XF86AudioLowerVolume exec noctalia msg volume-down
        bindsym --locked XF86AudioMute exec noctalia msg volume-mute
        bindsym --locked XF86MonBrightnessUp exec noctalia msg brightness-up
        bindsym --locked XF86MonBrightnessDown exec noctalia msg brightness-down
      '';
    };
  };
}
