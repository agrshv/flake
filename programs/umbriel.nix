{
  config,
  osConfig,
  pkgs,
  lib,
  ...
}:

let
  ghostty = lib.getExe pkgs.ghostty;
  noctalia = "spawn noctalia msg";
  lenovo = "Lenovo Group Limited N27q UT33383Y";

  # Same app-to-number mapping as programs/mango.nix, so one set of habits
  # works in both: Mod+N goes to the app's workspace by name, on whichever
  # output holds it.
  workspaces = [
    {
      name = "terminal";
      output = lenovo;
      app_id = ''^com\.mitchellh\.ghostty$'';
    }
    {
      name = "browser";
      output = lenovo;
      app_id = "^brave-origin$";
    }
    # Kept for the numbering, but nothing opens there at login.
    {
      name = "code";
      output = "eDP-1";
      app_id = null;
    }
    {
      name = "chat";
      output = "eDP-1";
      app_id = "^vesktop$";
    }
    {
      name = "telegram";
      output = "eDP-1";
      app_id = ''^org\.telegram\.desktop$'';
    }
  ];

  numbered = lib.imap1 (i: w: w // { key = toString i; }) workspaces;
  locked = action: {
    inherit action;
    allow_when_locked = true;
  };
in
{
  # Upstream dropped the home module's build-time check, so run
  # `umbriel config validate` here: an unknown key or action fails the build
  # instead of being skipped with a warning at login. The marker file is only
  # there to pull the check into the generation.
  xdg.configFile."umbriel/.validated".source = pkgs.runCommand "umbriel-config-validated" { } ''
    export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR
    cp ${config.xdg.configFile."umbriel/config.toml".source} $TMPDIR/config.toml
    ${lib.getExe' osConfig.programs.umbriel.package "umbriel"} config validate -c $TMPDIR/config.toml
    touch $out
  '';

  # Session/portal/package come from the umbriel flake's NixOS module
  # (hosts/common/desktop.nix); this writes ~/.config/umbriel/config.toml.
  # It replaces the packaged
  # config, so everything umbriel should do is spelled out here. Mirrors the
  # old niri setup with dwindle in place of scrolling columns. Noctalia starts
  # from its systemd service, so it isn't in autostart.
  programs.umbriel = {
    enable = true;
    settings = {
      # Under `optional`, which is what noctalia's umbriel template expects:
      # anywhere else its apply hook rewrites config.toml, and this file is a
      # read-only home-manager link. Optional also lets umbriel start before
      # noctalia has rendered the file.
      include.optional.files = [ "noctalia.toml" ];

      general = {
        autostart = [
          ghostty
          "brave-origin"
          "vesktop"
          "Telegram"
        ];
        show_cheatsheet = false;
        # Notification actions and window activation from noctalia (niri's
        # honor-xdg-activation-with-invalid-serial).
        focus_on_activate = true;
      };

      input = {
        keyboard = {
          layout = "us,ru,de";
          options = "grp:alt_shift_toggle";
          repeat_rate = 50;
          repeat_delay = 300;
        };
        touchpad = {
          tap = true;
          natural_scroll = true;
          disable_while_typing = true;
        };
        mouse.accel_profile = "flat";
        cursor.follows_focus = true;
        focus.follows_mouse = true;
      };

      # The Lenovo above the laptop, as in the greeter (hosts/common/desktop.nix);
      # matched by identity so it keeps its settings on any port. DP-2 is
      # placed automatically.
      output = {
        "DP-2" = {
          mode = "1920x1080@239.757";
          vrr = "always";
        };
        ${lenovo} = {
          mode = "2560x1440@99.946";
          position = [
            0
            0
          ];
        };
        "eDP-1" = {
          position = [
            0
            1440
          ];
          scale = 1;
        };
      };

      # One app per workspace, so a single window fills the screen; a second
      # one splits it instead of scrolling off to the side.
      layout = {
        mode = "dwindle";
        gap = 8;
      };

      # Persistent named workspaces, pinned to their monitors. Undocked, the
      # Lenovo's two don't exist and their apps open on the focused workspace.
      workspace = map (w: { inherit (w) name output; }) workspaces;

      appearance = {
        prefer_no_csd = true;
        border_width = 2;
        corner_radius = 20;
      };

      keybinds = {
        "Mod+Return" = "spawn ${ghostty}";
        "Mod+Shift+Q" = "window-close";
        # The packaged Mod+Escape quits; lock wins (niri/sway habit) and quit
        # moves to Mod+Shift+E.
        "Mod+Escape" = "${noctalia} session lock";
        "Mod+Shift+E" = "session-quit";
        "Mod+Ctrl+R" = "config-reload";

        "Mod+D" = {
          action = "${noctalia} panel-toggle launcher";
          repeat = false;
        };
        "Mod+S" = "${noctalia} panel-toggle control-center";
        "Mod+Comma" = "${noctalia} settings-toggle";
        "Mod+Shift+S" = "${noctalia} screenshot-region";
        # Start/stop noctalia's screen_recorder plugin (programs/noctalia.nix).
        "Mod+Shift+R" = "${noctalia} plugin noctalia/screen_recorder:service all toggle";

        "XF86AudioRaiseVolume" = locked "${noctalia} volume-up";
        "XF86AudioLowerVolume" = locked "${noctalia} volume-down";
        "XF86AudioMute" = locked "${noctalia} volume-mute";
        "XF86MonBrightnessUp" = locked "${noctalia} brightness-up";
        "XF86MonBrightnessDown" = locked "${noctalia} brightness-down";

        "Mod+Left" = "window-focus-or-output-left";
        "Mod+Right" = "window-focus-or-output-right";
        "Mod+Up" = "window-focus-or-output-up";
        "Mod+Down" = "window-focus-or-output-down";
        "Mod+Shift+Left" = "window-swap-left";
        "Mod+Shift+Right" = "window-swap-right";
        "Mod+Shift+Up" = "window-swap-up";
        "Mod+Shift+Down" = "window-swap-down";

        "Mod+F" = "window-toggle-fullscreen";
        "Mod+Space" = "window-toggle-floating";
        "Mod+R" = "layout-toggle-split";
        "Mod+Minus" = "window-modify-primary-extent -0.1";
        "Mod+Equal" = "window-modify-primary-extent 0.1";
      }
      // lib.listToAttrs (
        lib.concatMap (w: [
          (lib.nameValuePair "Mod+${w.key}" "workspace-switch ${w.name}")
          (lib.nameValuePair "Mod+Shift+${w.key}" "window-move-to-workspace ${w.name}")
        ]) numbered
      );

      window_rule = [
        # Blur behind every window, against the live content rather than the
        # cached wallpaper (niri's xray off).
        {
          blur = true;
          blur_optimized = false;
        }
      ]
      # Only for the session's first minute, so a terminal opened later with
      # Mod+Return still lands on the focused workspace (niri's at-startup).
      ++ map (w: {
        match = {
          inherit (w) app_id;
          at_startup = true;
        };
        default_workspace = w.name;
        default_output = w.output;
      }) (lib.filter (w: w.app_id != null) workspaces)
      ++ [
        {
          match.app_id = ''^dev\.noctalia\.Noctalia\.Settings$'';
          default_floating = true;
          default_floating_size_px = {
            width = 1080;
            height = 920;
          };
        }
        {
          match.app_id = ''^dev\.noctalia\.UmbrielSharePicker$'';
          default_floating = true;
          default_floating_size_px = {
            width = 800;
            height = 600;
          };
        }
      ];

      # Noctalia's translucent bar, panels and notifications: blur what's
      # behind them, popups included.
      layer_rule = [
        {
          match.namespace = ''^noctalia-(bar-[^"]+|notification|dock|panel|attached-panel|osd)$'';
          blur = true;
          blur_ignore_alpha = 0.5;
          blur_popups = true;
          blur_optimized = false;
        }
      ];
    };
  };
}
