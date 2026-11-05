{
  config,
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
  # noctalia runs template hooks with the session PATH, so they find these
  # too. The brave-origin template (community_ids below) installs its theme
  # with python3 and renders the theme images with Pillow. The screen_recorder
  # plugin picks a region with slurp; its gpu-screen-recorder comes from
  # hosts/common/desktop.nix.
  home.packages = [
    pkgs.glib # gdbus
    pkgs.sshfs
    pkgs.slurp
    (pkgs.python3.withPackages (ps: [ ps.pillow ]))
  ];

  home.file."Media/Pictures/Wallpapers/${defaultWallpaper}".source = defaultWallpaperFile;

  # noctalia's lockscreen editor saves the whole layout it shows into its state
  # file (even on "Done" with nothing moved, and again later from memory), and
  # that table overrides lockscreen_widgets below — so after one visit the Nix
  # layout silently stops applying. Drop it before every start; the module
  # already restarts noctalia when its config changes.
  systemd.user.services.noctalia.Service.ExecStartPre =
    "${pkgs.writeShellScript "noctalia-drop-lockscreen-state" ''
      f="${config.xdg.stateHome}/noctalia/settings.toml"
      [ -f "$f" ] || exit 0
      ${pkgs.gawk}/bin/awk '
        /^[[:space:]]*\[/ { skip = ($0 ~ /^[[:space:]]*\[\[?lockscreen_widgets[].]/) }
        !skip
      ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    ''}";

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      bar.default = {
        # Floating off the screen edge, slightly translucent so niri's blur
        # (the noctalia layer-rule in programs/niri.nix) shows through, with
        # every widget in its own pill.
        margin_edge = 6;
        background_opacity = 0.85;
        capsule = true;
        # control-center wears the NixOS snowflake (widget.control-center
        # below), so it leads the bar like a distro logo.
        start = [
          "control-center"
          "launcher"
          "workspaces"
        ];
        # noctalia's default end list (config_types.h), restated in full because
        # setting `end` replaces it rather than appending, minus `clipboard`
        # (shell.clipboard_enabled is off) and `control-center` (moved to
        # `start`), plus the recorder before the tray and the phone-connect
        # widget next to the laptop's own battery.
        end = [
          "media"
          "noctalia/screen_recorder:recorder"
          "tray"
          "notifications"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "icefish/phone-connect:bar"
          "battery"
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
      #
      # Screen Recorder (official plugin): gpu-screen-recorder behind a bar
      # widget — left click starts/stops. Its default source, "portal", asks
      # which screen or window to record. Saved under the XDG videos dir
      # (programs/xdg.nix) rather than the plugin's ~/Videos/Recordings.
      plugins.enabled = [
        "icefish/phone-connect"
        "noctalia/screen_recorder"
      ];
      plugin_settings = {
        "icefish/phone-connect".battery_display = "percent";
        "noctalia/screen_recorder".directory = "${config.xdg.userDirs.videos}/Recordings";
      };
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
      # A dashboard of tiles centred on the laptop screen: three system graphs
      # | clock, weather and password | calendar. The external monitors show
      # only the wallpaper.
      #
      # Positions are in each output's own pixels, so each output is listed
      # with its size. Per-box options and styling go under that box's
      # `.settings` — a sibling `widget.settings` table is read as a widget
      # named "settings" of no type. Login boxes must be keyed
      # `lockscreen-login-box@<output>`, everything else
      # `lockscreen-widget-<anything>`.
      lockscreen_widgets =
        let
          # Outputs that get the dashboard. An optional `scale` grows the
          # cluster, e.g. 2560.0 / 1920.0 on a 1440p screen to cover the same
          # share of it as on 1080p.
          outputs = {
            "eDP-1" = {
              width = 1920.0;
              height = 1080.0;
            };
          };

          # Wallpaper only. noctalia adds a default login box to any output
          # without one, so these get a disabled one instead. With the lid
          # closed no output shows a password field.
          bare = [
            "HDMI-A-1"
            "DP-2"
          ];
          bareOn = output: {
            "lockscreen-login-box@${output}" = {
              inherit output;
              type = "login_box";
              enabled = false;
            };
          };

          # Shared tile look; the login box takes the same keys minus
          # `background` (it always draws one).
          tileStyle = {
            background_color = "surface";
            background_opacity = 0.8;
            background_radius = 12;
          };

          # The cluster is 802 x 345 px around the output's centre:
          #   graphs 170 wide | 16 gap | 300 centre column | 16 gap | calendar 300
          # with the centre column split into clock 160, weather and password
          # (see clusterOn; 83 and 70 at scale 1) with 16 px gaps, and the three
          # graphs 105 high (15 px gaps).
          # x/y are offsets of each tile's centre from the output's centre, at
          # scale 1.
          tiles = [
            {
              name = "cpu";
              type = "sysmon";
              x = -283.5;
              y = -120.0;
              w = 170.0;
              h = 105.0;
              settings = {
                stat = "cpu_usage";
                stat2 = "cpu_temp";
                display = "graph";
              };
            }
            {
              name = "memory";
              type = "sysmon";
              x = -283.5;
              y = 0.0;
              w = 170.0;
              h = 105.0;
              settings = {
                stat = "ram_pct";
                stat2 = "swap_pct";
                display = "graph";
              };
            }
            {
              name = "network";
              type = "sysmon";
              x = -283.5;
              y = 120.0;
              w = 170.0;
              h = 105.0;
              settings = {
                stat = "net_rx";
                stat2 = "net_tx";
                display = "graph";
              };
            }
            {
              name = "clock";
              type = "clock";
              x = -33.0;
              y = -92.5;
              w = 300.0;
              h = 160.0;
            }
            # Weather for location.address above; an audio_visualizer here sat as a flat
            # line unless something played while locked. y/h are its scale-1
            # slot; clusterOn stretches it to whatever the login box leaves.
            {
              name = "weather";
              type = "weather";
              x = -33.0;
              y = 45.0;
              w = 300.0;
              h = 83.0;
            }
            {
              name = "calendar";
              type = "calendar";
              x = 283.5;
              y = 0.0;
              w = 300.0;
              h = 345.0;
              # Events take half the tile and shrink the month to fit.
              settings.show_events = false;
            }
          ];

          clusterOn =
            output:
            {
              width,
              height,
              scale ? 1.0,
            }:
            let
              place =
                {
                  x,
                  y,
                  w,
                  h,
                  ...
                }:
                {
                  inherit output;
                  cx = width / 2 + x * scale;
                  cy = height / 2 + y * scale;
                  box_width = w * scale;
                  box_height = h * scale;
                  placement_width = width;
                  placement_height = height;
                  rotation = 0.0;
                };

              # The compact login box always draws at its floor (padding + one
              # input row) whatever box_height says, centred in the box. So it
              # is given exactly that, unscaled, with its bottom on the
              # cluster's bottom edge, and the weather tile above takes up the
              # difference, keeping both 16 px (scaled) gaps.
              loginHeight = 70.0;
              bottom = 172.5 * scale;
              loginTop = bottom - loginHeight;
              weatherTop = (-12.5 + 16.0) * scale; # clock bottom + gap
              weatherBottom = loginTop - 16.0 * scale;
            in
            builtins.listToAttrs (
              map (t: {
                name = "lockscreen-widget-${t.name}@${output}";
                value = place t // {
                  inherit (t) type;
                  settings = tileStyle // t.settings or { };
                };
              }) tiles
            )
            // {
              "lockscreen-widget-weather@${output}" =
                (place (builtins.head (builtins.filter (t: t.name == "weather") tiles)))
                // {
                  type = "weather";
                  settings = tileStyle;
                  cy = height / 2 + (weatherTop + weatherBottom) / 2;
                  box_height = weatherBottom - weatherTop;
                };
              "lockscreen-login-box@${output}" =
                place {
                  x = -33.0;
                  y = 0.0;
                  w = 300.0;
                  h = 0.0;
                }
                // {
                  cy = height / 2 + bottom - loginHeight / 2;
                  box_height = loginHeight;
                  type = "login_box";
                  settings = tileStyle // {
                    layout = "compact";
                    center_password_text = true;
                    show_caps_lock = true;
                    show_keyboard_layout = true;
                    show_login_button = false;
                    show_session_buttons = false;
                    show_unlock_hint = false;
                    input_opacity = 1.0;
                    input_radius = 6.0;
                  };
                };
            };

          widget =
            builtins.foldl' (acc: o: acc // clusterOn o outputs.${o}) { } (builtins.attrNames outputs)
            // builtins.foldl' (acc: o: acc // bareOn o) { } bare;
        in
        {
          enabled = true;
          schema_version = 2;
          widget_order = builtins.attrNames widget;
          grid = {
            cell_size = 16;
            major_interval = 4;
            visible = true;
          };
          inherit widget;
        };
      nightlight.enabled = true;
      shell = {
        # Installed system-wide in hosts/common/desktop.nix.
        font_family = "Inter";
        # Rounded screen corners, matching the bar's.
        screen_corners.enabled = true;
        polkit_agent = true;
        launch_apps_as_systemd_services = true;
        readline_shortcuts = true;
        greeter_sync.auto_sync = true;
        clipboard_enabled = false;
      };
      theme = {
        mode = "light";
        # Palette generated from the current wallpaper (default m3-content
        # scheme), so it changes with wallpaper.automation below, and every
        # template follows. `source = "builtin"; builtin = "Gruvbox";` was the
        # previous fixed palette.
        source = "wallpaper";
        # Apps whose colours noctalia owns.
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
          #
          # niri: renders ~/.config/niri/noctalia.kdl, included (optional=true)
          # from programs/niri.nix. umbriel: renders noctalia.toml, which
          # programs/umbriel.nix already includes. btop: writes a noctalia theme
          # and selects it in btop.conf (created by btop on first run).
          builtin_ids = [
            "btop"
            "ghostty"
            "gtk3"
            "gtk4"
            "niri"
            "umbriel"
          ];
          enable_community_templates = true;
          # discord: writes three stylesheets into the themes directory
          # of whichever clients are installed — programs/vesktop.nix enables
          # noctalia.theme.css (midnight). telegram: drops a .tdesktop-theme into
          # ~/.config/telegram-desktop/themes, which has to be picked once from
          # Settings → Chat Settings → Themes, as the client keeps that choice
          # in its own state. Neither has an apply hook, so read-only
          # settings files home-manager owns are untouched.
          #
          # claude-code: ~/.claude/themes/noctalia.json, picked once via /theme.
          # obsidian: a noctalia.css snippet in each vault, switched on in the
          # vault's appearance.json. brave-origin: an unpacked theme extension in
          # ~/.local/share/noctalia/brave-origin-theme — load it once from
          # brave://extensions (developer mode → Load unpacked); after palette
          # changes, Update there or restart Brave.
          #
          # neovim: renders ~/.config/nvim/lua/matugen.lua — inside this repo,
          # as programs/neovim.nix links the checkout, hence the .gitignore
          # entry — and SIGUSR1s running nvims to reload it. init.lua feeds the
          # palette to mini.base16 and already has the loader the hook would
          # otherwise append there.
          community_ids = [
            "brave-origin"
            "claude-code"
            "discord"
            "neovim"
            "obsidian"
            "telegram"
          ];
        };
      };
      wallpaper = {
        enabled = true;
        # `directory` is what the wallpaper picker browses; `default.path` is
        # the one it starts on, which home-manager links in below.
        directory = wallpapers;
        default.path = "${wallpapers}/${defaultWallpaper}";
        # Cycle through `directory` at random every hour; each change also
        # re-themes (theme.source) and syncs to the greeter. Hourly rather
        # than the 30-minute default since every change repaints all apps.
        automation = {
          enabled = true;
          interval_seconds = 3600;
        };
      };
      # Blur and tint the wallpaper behind open panels (launcher, control
      # centre, ...).
      backdrop.enabled = true;
      widget = {
        # The NixOS snowflake instead of noctalia's own logo, tinted like the
        # other bar icons (there is no NixOS glyph in its tabler icon set).
        control-center = {
          custom_image = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          custom_image_colorize = true;
        };
        media.hide_when_no_media = true;
        tray.hidden = [ "nm-applet" ];
        battery.hide_when_full = true;
        bluetooth = {
          show_label = true;
          # Bluetooth starts off (hosts/work-laptop), so keep the widget visible:
          # right-click toggles it.
          hide_when_adapter_off = false;
        };
        network = {
          show_label = false;
          vpn_status = "both";
        };
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
