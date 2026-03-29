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
      };
      output."*".bg = "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png fill";
      output."DP-4".mode = "1920x1080@239.757Hz";
      bars = [
        {
          fonts = {
            names = [ "monospace" ];
            size = 8.0;
          };
          mode = "dock";
          hiddenState = "hide";
          position = "top";
          statusCommand = "${pkgs.i3status}/bin/i3status";
          workspaceButtons = true;
          workspaceNumbers = true;
          trayOutput = "DP-4";
          extraConfig = ''
            icon_theme Papirus-Dark
          '';
          colors = {
            background = "$base";
            statusline = "$text";
            focusedStatusline = "$text";
            separator = "$base";
            focusedWorkspace = {
              border = "$base";
              background = "$mauve";
              text = "$crust";
            };
            activeWorkspace = {
              border = "$base";
              background = "$surface2";
              text = "$text";
            };
            inactiveWorkspace = {
              border = "$base";
              background = "$base";
              text = "$text";
            };
            urgentWorkspace = {
              border = "$base";
              background = "$red";
              text = "$crust";
            };
          };
        }
      ];
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
