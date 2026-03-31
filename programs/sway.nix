{ pkgs, ... }:

{
  wayland.windowManager.sway = {
    enable = true;
    config = {
      terminal = "${pkgs.ghostty}/bin/ghostty";
      menu = "${pkgs.fuzzel}/bin/fuzzel";
      modifier = "Mod4";
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
      output."*".bg = "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png fill";
      output."DP-4" = {
        mode = "1920x1080@239.757Hz";
        adaptive_sync = "on";
      };
      output."HDMI-A-1".position = "0 0";
      output."eDP-1".position = "0 1080";
      bars = []; # Disabled in favor of waybar
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
    };
  };
}
