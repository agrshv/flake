{
  pkgs,
  lib,
  ...
}:

let
  ghostty = lib.getExe pkgs.ghostty;
  grim = lib.getExe pkgs.grim;
  slurp = lib.getExe pkgs.slurp;
  wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
in
{
  # niri has no built-in home-manager module (unlike sway), so the config is
  # written directly. Noctalia starts via its systemd service under any Wayland
  # compositor, so niri only needs input/output/keybind wiring here. Keybinds
  # mirror programs/sway.nix.
  home.packages = [
    pkgs.grim
    pkgs.slurp
    pkgs.xwayland-satellite
  ];

  xdg.configFile."niri/config.kdl".text = ''
    input {
        warp-mouse-to-focus
        focus-follows-mouse
        keyboard {
            xkb {
                layout "us,ru"
                options "grp:alt_shift_toggle"
            }
            repeat-delay 300
            repeat-rate 50
        }
        touchpad {
            tap
            natural-scroll
        }
        mouse {
            accel-profile "flat"
        }
    }

    output "DP-2" {
        mode "1920x1080@239.757"
        variable-refresh-rate
    }
    output "HDMI-A-1" {
        mode "2560x1440@99.946"
        position x=0 y=0
    }
    output "eDP-1" {
        position x=0 y=1440
    }

    layout {
        gaps 8
        focus-ring {
            width 2
            active-color "#b4befe"
            inactive-color "#6c7086"
        }
    }

    prefer-no-csd
    hotkey-overlay {
        skip-at-startup
    }

    binds {
        Mod+Return { spawn "${ghostty}"; }
        Mod+Shift+Q { close-window; }

        Mod+Escape { spawn "noctalia" "msg" "session" "lock"; }
        Mod+D { spawn "noctalia" "msg" "panel-toggle" "launcher"; }
        Mod+S { spawn "noctalia" "msg" "panel-toggle" "control-center"; }
        Mod+Comma { spawn "noctalia" "msg" "settings-toggle"; }

        Mod+Shift+S { spawn "sh" "-c" "${grim} -g \"$(${slurp})\" - | ${wlCopy} -t image/png"; }

        XF86AudioRaiseVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-up"; }
        XF86AudioLowerVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-down"; }
        XF86AudioMute allow-when-locked=true { spawn "noctalia" "msg" "volume-mute"; }
        XF86MonBrightnessUp allow-when-locked=true { spawn "noctalia" "msg" "brightness-up"; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "noctalia" "msg" "brightness-down"; }

        Mod+Left  { focus-column-left; }
        Mod+Right { focus-column-right; }
        Mod+Up    { focus-window-up; }
        Mod+Down  { focus-window-down; }

        Mod+Shift+Left  { move-column-left; }
        Mod+Shift+Right { move-column-right; }
        Mod+Shift+Up    { move-window-up; }
        Mod+Shift+Down  { move-window-down; }

        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+Shift+1 { move-column-to-workspace 1; }
        Mod+Shift+2 { move-column-to-workspace 2; }
        Mod+Shift+3 { move-column-to-workspace 3; }
        Mod+Shift+4 { move-column-to-workspace 4; }
        Mod+Shift+5 { move-column-to-workspace 5; }

        Mod+F { fullscreen-window; }
        Mod+R { switch-preset-column-width; }
        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }

        Mod+Shift+E { quit; }
    }

    window-rule {
      // Rounded corners for a modern look.
      geometry-corner-radius 20

      // Clips window contents to the rounded corner boundaries.
      clip-to-geometry true

      // Apps: blur them all without xray so it looks more realistic.
      background-effect {
        blur true
        xray false
      }
    }

    window-rule {
      match app-id="dev.noctalia.Noctalia.Settings"
      open-floating true
      default-column-width { fixed 1080; }
      default-window-height { fixed 920; }
    }

    /*
      Noctalia
      Disable xray on all our surfaces so it looks more realistic.
      Noctalia publishes blur regions automatically when ext-background-effects is available.
    */
    layer-rule {
      match namespace="^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$"
      background-effect {
        xray false
        // blur false
      }
    }

    debug {
      // Allows notification actions and window activation from Noctalia.
      honor-xdg-activation-with-invalid-serial
    }
  '';
}
