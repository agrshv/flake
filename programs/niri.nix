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

  # When the Lenovo is unplugged niri appends its workspaces after the laptop's;
  # pull them to the front instead, so they stay on Mod+1/2 there too. Fires on
  # every workspace change but only acts while `terminal` shares an output with
  # `code`, and moves are by name, so it settles after one pass. niri itself
  # comes from PATH so its IPC matches the running compositor.
  lenovoWorkspacesFirst = pkgs.writeShellApplication {
    name = "niri-lenovo-workspaces-first";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      niri msg --json event-stream | while read -r event; do
        if jq -e '
          .WorkspacesChanged.workspaces // empty
          | (map(select(.name == "code"))[0].output) as $laptop
          | map(select(.output == $laptop))
          | select(any(.name == "terminal"))
          | (map(select(.name == "terminal"))[0].idx != 1)
            or (map(select(.name == "browser"))[0].idx != 2)
          | select(.)
        ' <<<"$event" >/dev/null; then
          niri msg action move-workspace-to-index --reference terminal 1
          niri msg action move-workspace-to-index --reference browser 2
        fi
      done
    '';
  };
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
                layout "us,ru,de"
                options "grp:alt_shift_toggle"
            }
            repeat-delay 300
            repeat-rate 50
        }
        touchpad {
            tap
            natural-scroll
            // Ignore the touchpad while typing (niri leaves libinput's dwt off
            // unless asked).
            dwt
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
        scale 1
    }

    // Pinned to their monitors and listed first there in declaration order,
    // so Mod+1..3 still reach them by index. Matched by model rather than
    // connector so the Lenovo keeps its workspaces on any port.
    workspace "terminal" { open-on-output "Lenovo Group Limited N27q UT33383Y"; }
    workspace "browser" { open-on-output "Lenovo Group Limited N27q UT33383Y"; }
    workspace "code" { open-on-output "eDP-1"; }
    workspace "chat" { open-on-output "eDP-1"; }
    workspace "telegram" { open-on-output "eDP-1"; }

    spawn-at-startup "${ghostty}"
    spawn-at-startup "brave-origin"
    spawn-at-startup "zeditor"
    spawn-at-startup "vesktop"
    spawn-at-startup "Telegram"
    spawn-at-startup "${lib.getExe lenovoWorkspacesFirst}"

    layout {
        gaps 8
        // Colours come from noctalia.kdl, included at the end.
        focus-ring {
            width 2
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

        Mod+Shift+S { spawn "noctalia" "msg" "screenshot-region"; }

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

    // Only for the session's first minute (at-startup), so a terminal opened
    // later with Mod+Return still lands on the focused workspace (at its usual
    // width; only the startup windows open full-width).
    window-rule {
      match app-id=r#"^com\.mitchellh\.ghostty$"# at-startup=true
      open-on-workspace "terminal"
      default-column-width { proportion 1.0; }
    }
    window-rule {
      match app-id="^brave-origin$" at-startup=true
      open-on-workspace "browser"
      default-column-width { proportion 1.0; }
    }
    window-rule {
      match app-id=r#"^dev\.zed\.Zed$"# at-startup=true
      open-on-workspace "code"
      default-column-width { proportion 1.0; }
    }
    window-rule {
      match app-id="^vesktop$" at-startup=true
      open-on-workspace "chat"
      default-column-width { proportion 1.0; }
    }
    window-rule {
      match app-id=r#"^org\.telegram\.desktop$"# at-startup=true
      open-on-workspace "telegram"
      default-column-width { proportion 1.0; }
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

    // Focus ring, border, tab indicator and window-switcher highlight in the
    // noctalia palette, written by its `niri` template (programs/noctalia.nix).
    // Last, so it wins over anything above. optional: on a fresh login niri
    // starts before noctalia has rendered the file. The template's apply hook
    // sees this line and leaves the read-only config alone.
    include optional=true "noctalia.kdl"
  '';
}
