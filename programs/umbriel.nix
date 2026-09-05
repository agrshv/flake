{ pkgs, lib, ... }:

let
  ghostty = lib.getExe pkgs.ghostty;
in
{
  # Session/portal/package come from the umbriel flake's NixOS module
  # (hosts/common/desktop.nix); this module only writes
  # ~/.config/umbriel/config.toml (validated at build time via
  # `umbriel validate`). Input/output/keybind wiring mirrors
  # programs/niri.nix; chords not set here keep umbriel's built-ins
  # (Mod+1..9 workspaces, Mod+arrows focus, Mod+Shift+arrows move, Mod+F
  # fullscreen, Mod+R cycle width). Noctalia starts via its systemd service
  # under any Wayland compositor, so no autostart entry is needed.
  programs.umbriel = {
    enable = true;
    settings = {
      include.files = [ "noctalia.toml" ];
      input = {
        touchpad = {
          tap = true;
          natural_scroll = true;
        };
        focus.follows_mouse = true;
      };
    };
    #   input = {
    #     keyboard = {
    #       layout = "us,ru";
    #       options = "grp:alt_shift_toggle";
    #       repeat_rate = 50;
    #       repeat_delay = 300;
    #     };
    #     touchpad = {
    #       tap = true;
    #       natural_scroll = true;
    #     };
    #     mouse.accel_profile = "flat";
    #     cursor.follows_focus = true;
    #     focus.follows_mouse = true;
    #   };

    #   output = {
    #     "DP-2" = {
    #       mode = "1920x1080@239.757";
    #       vrr = "always";
    #     };
    #     "HDMI-A-1" = {
    #       mode = "2560x1440@99.946";
    #       position = [
    #         0
    #         0
    #       ];
    #     };
    #     "eDP-1" = {
    #       position = [
    #         0
    #         1440
    #       ];
    #       scale = 1;
    #     };
    #   };

    #   layout.gap = 8;

    #   appearance = {
    #     prefer_no_csd = true;
    #     border_width = 2;
    #     corner_radius = 20;
    #   };

    #   # Catppuccin Mocha: lavender focus ring, overlay0 unfocused (as in niri).
    #   colors.border = {
    #     focused = "#b4befeff";
    #     unfocused = "#6c7086ff";
    #   };

    #   keybinds = {
    #     "Mod+Return" = "spawn:${ghostty}";
    #     "Mod+Shift+Q" = "window-close";

    #     # Built-in Mod+Escape is session-quit; lock wins (niri/sway habit)
    #     # and quit moves to Mod+Shift+E.
    #     "Mod+Escape" = "spawn:noctalia msg session lock";
    #     "Mod+Shift+E" = "session-quit";
    #     "Mod+D" = "spawn:noctalia msg panel-toggle launcher";
    #     "Mod+S" = "spawn:noctalia msg panel-toggle control-center";
    #     "Mod+Comma" = "spawn:noctalia msg settings-toggle";
    #     "Mod+Shift+S" = "spawn:noctalia msg screenshot-region";

    #     "Mod+Minus" = "window-modify-width:-0.1";
    #     "Mod+Equal" = "window-modify-width:0.1";

    #     "XF86AudioRaiseVolume" = {
    #       action = "spawn:noctalia msg volume-up";
    #       allow_when_locked = true;
    #     };
    #     "XF86AudioLowerVolume" = {
    #       action = "spawn:noctalia msg volume-down";
    #       allow_when_locked = true;
    #     };
    #     "XF86AudioMute" = {
    #       action = "spawn:noctalia msg volume-mute";
    #       allow_when_locked = true;
    #     };
    #     "XF86MonBrightnessUp" = {
    #       action = "spawn:noctalia msg brightness-up";
    #       allow_when_locked = true;
    #     };
    #     "XF86MonBrightnessDown" = {
    #       action = "spawn:noctalia msg brightness-down";
    #       allow_when_locked = true;
    #     };
    #   };

    #   # This file replaces umbriel's packaged config wholesale, so carry over
    #   # its noctalia integration rules: blur all windows, float the settings
    #   # window, blur noctalia's layer-shell surfaces.
    #   window_rule = [
    #     {
    #       blur = true;
    #       blur_optimized = false;
    #     }
    #     {
    #       match.app_id = "^dev.noctalia.Noctalia$";
    #       default_floating = true;
    #       default_size = [
    #         1080
    #         920
    #       ];
    #     }
    #     {
    #       match.app_id = "^dev.noctalia.UmbrielSharePicker$";
    #       default_floating = true;
    #       default_size = [
    #         800
    #         600
    #       ];
    #     }
    #   ];

    #   layer_rule = [
    #     {
    #       match.namespace = ''^noctalia-(bar-[^"]+|notification|dock|panel|attached-panel|osd|desktop-widget-[^"]*)$'';
    #       blur = true;
    #       blur_ignore_alpha = 0.5;
    #       blur_popups = true;
    #       blur_optimized = false;
    #     }
    #   ];
    # };
  };
}
