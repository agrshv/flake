{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:

let
  mango = pkgs-unstable.mangowc;
  ghostty = lib.getExe pkgs.ghostty;
  noctalia = "noctalia msg";

  # Fixed tag per app, whatever is plugged in: the Lenovo gets 1-2, the laptop
  # 3-5. Undocked, the Lenovo rules find no monitor and everything lands on
  # the laptop as 1-5 (the order the niri reorder script used to force).
  # Docked, tags are per monitor, so Mod+3 on the laptop is code.
  lenovo = "model:N27q";
  startup = [
    {
      app_id = ''^com\.mitchellh\.ghostty$'';
      tag = 1;
      monitor = lenovo;
    }
    {
      app_id = "^brave-origin$";
      tag = 2;
      monitor = lenovo;
    }
    {
      app_id = ''^dev\.agrshv\.nvim$'';
      tag = 3;
      monitor = "^eDP-1$";
    }
    {
      app_id = "^vesktop$";
      tag = 4;
      monitor = "^eDP-1$";
    }
    {
      app_id = ''^org\.telegram\.desktop$'';
      tag = 5;
      monitor = "^eDP-1$";
    }
  ];

  tags = lib.range 1 5;

  # A script rather than inline: mango caps a config value at 255 bytes.
  startSession = pkgs.writeShellScript "mango-start-session" ''
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
      NIXOS_OZONE_WL XCURSOR_THEME XCURSOR_SIZE
    systemctl --user reset-failed
    systemctl --user start mango-session.target
  '';

  # Everything but the noctalia colour include, so it can be checked at build
  # time without the runtime-rendered file.
  body = ''
    # --- Input ------------------------------------------------------------
    xkb_rules_layout=us,ru,de
    xkb_rules_options=grp:alt_shift_toggle
    repeat_delay=300
    repeat_rate=50
    tap_to_click=1
    trackpad_natural_scrolling=1
    trackpad_disable_while_typing=1
    mouse_accel_profile=1
    sloppy_focus=1
    warp_cursor=1
    cursor_theme=Adwaita
    cursor_size=24

    # --- Outputs ----------------------------------------------------------
    # The Lenovo above the laptop, as in the greeter (hosts/common/desktop.nix).
    # DP-2 is left for mango to place.
    monitor_rule=name:^DP-2$,width:1920,height:1080,refresh:239.757,vrr:1
    monitor_rule=name:^HDMI-A-1$,width:2560,height:1440,refresh:99.946,x:0,y:0
    monitor_rule=name:^eDP-1$,x:0,y:1440,scale:1

    # --- Layout -----------------------------------------------------------
    # One app per tag, so a single window fills the screen; a second one
    # splits it instead of scrolling off to the side.
    tag_rule=id:*,layout_name:dwindle
    gap_inner_horizontal=8
    gap_inner_vertical=8
    gap_outer_horizontal=8
    gap_outer_vertical=8
    border_px=2
    border_radius=20

    # --- Effects ----------------------------------------------------------
    # Blur behind apps and noctalia's translucent bar/panels; not optimized,
    # which would only blur the wallpaper (niri's xray). Noctalia draws its
    # own shadows and layer animations.
    blur=1
    blur_layer=1
    blur_optimized=0
    shadows=0
    layer_animations=0
    # slurp's selection overlay, so screenshots aren't blurred or ghosted.
    layer_rule=no_blur:1,no_animation:1,layer_name:^selection$

    # --- Windows ----------------------------------------------------------
    # _once: only the first matching window, i.e. the one started below, so
    # later terminals open on the focused tag (niri's at-startup=true).
    ${lib.concatMapStrings (
      s: "window_rule_once=tags:${toString s.tag},monitor:${s.monitor},app_id:${s.app_id}\n"
    ) startup}
    window_rule=is_floating:1,width:1080,height:920,app_id:^dev\.noctalia\.Noctalia\.Settings$
    # Notification actions and window activation from noctalia (niri's
    # honor-xdg-activation-with-invalid-serial).
    window_rule=activation_bypass:1,app_id:.*

    # --- Autostart --------------------------------------------------------
    # nixpkgs' mango module only installs the session; this is what upstream's
    # home-manager module does to bring up graphical-session.target, which
    # starts noctalia (and every other graphical user service).
    exec_once=${startSession}
    exec_once=${ghostty}
    exec_once=${ghostty} --class=dev.agrshv.nvim -e nvim
    exec_once=brave-origin
    exec_once=vesktop
    exec_once=Telegram

    # --- Binds ------------------------------------------------------------
    bind=SUPER,Return,spawn,${ghostty}
    bind=SUPER+SHIFT,q,killclient
    bind=SUPER+SHIFT,e,quit
    bind=SUPER+CTRL,r,reload_config

    bind=SUPER,Escape,spawn,${noctalia} session lock
    bind=SUPER,d,spawn,${noctalia} panel-toggle launcher
    bind=SUPER,s,spawn,${noctalia} panel-toggle control-center
    bind=SUPER,comma,spawn,${noctalia} settings-toggle
    bind=SUPER+SHIFT,s,spawn,${noctalia} screenshot-region
    # Start/stop noctalia's screen_recorder plugin (programs/noctalia.nix).
    bind=SUPER+SHIFT,r,spawn,${noctalia} plugin noctalia/screen_recorder:service all toggle

    bindl=NONE,XF86AudioRaiseVolume,spawn,${noctalia} volume-up
    bindl=NONE,XF86AudioLowerVolume,spawn,${noctalia} volume-down
    bindl=NONE,XF86AudioMute,spawn,${noctalia} volume-mute
    bindl=NONE,XF86MonBrightnessUp,spawn,${noctalia} brightness-up
    bindl=NONE,XF86MonBrightnessDown,spawn,${noctalia} brightness-down

    bind=SUPER,Left,focusdir,left
    bind=SUPER,Right,focusdir,right
    bind=SUPER,Up,focusdir,up
    bind=SUPER,Down,focusdir,down
    bind=SUPER+SHIFT,Left,exchange_client,left
    bind=SUPER+SHIFT,Right,exchange_client,right
    bind=SUPER+SHIFT,Up,exchange_client,up
    bind=SUPER+SHIFT,Down,exchange_client,down

    ${lib.concatMapStrings (t: ''
      bind=SUPER,${toString t},view,${toString t}
      bind=SUPER+SHIFT,${toString t},tag,${toString t}
    '') tags}
    bind=SUPER,f,togglefullscreen
    bind=SUPER,space,togglefloating
    bind=SUPER,r,dwindle_toggle_current_split
    bind=SUPER,minus,resizewin,-50,0
    bind=SUPER,equal,resizewin,+50,0
  '';

  # Noctalia palette, rendered by its `mango` template (programs/noctalia.nix);
  # last, so it wins. A plain `source=` (not source_optional) because that's
  # the spelling the template's apply hook looks for; without it the hook
  # tries to append to this read-only file. The activation step below makes
  # sure the file exists before noctalia first renders it.
  include = ''

    source=~/.config/mango/noctalia.conf
  '';

  # `mango -p` parses without starting the compositor and exits non-zero on
  # unknown keywords and bad values, so a typo fails the build. Checked
  # without the include, which only exists at runtime.
  config =
    pkgs.runCommand "mango-config.conf"
      {
        passAsFile = [
          "body"
          "include"
        ];
        inherit body include;
      }
      ''
        HOME=$TMPDIR ${lib.getExe' mango "mango"} -c "$bodyPath" -p
        cat "$bodyPath" "$includePath" > $out
      '';
in
{
  home.packages = [
    pkgs.grim
    pkgs.slurp
  ];

  xdg.configFile."mango/config.conf".source = config;

  systemd.user.targets.mango-session.Unit = {
    Description = "mango compositor session";
    Documentation = [ "man:systemd.special(7)" ];
    BindsTo = [ "graphical-session.target" ];
    Wants = [ "graphical-session-pre.target" ];
    After = [ "graphical-session-pre.target" ];
  };

  home.activation.mangoNoctaliaConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/mango"
    [ -e "$HOME/.config/mango/noctalia.conf" ] || run touch "$HOME/.config/mango/noctalia.conf"
  '';
}
