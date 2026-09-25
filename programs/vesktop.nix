{
  # Themed by noctalia instead: its community `discord` template (enabled in
  # programs/noctalia.nix) writes ~/.config/vesktop/themes/noctalia.theme.css.
  # The catppuccin module did the same job by pinning enabledThemes at a file
  # that @imported the theme from catppuccin.github.io at runtime.
  catppuccin.vesktop.enable = false;

  programs.vesktop = {
    enable = true;
    settings = {
      appBadge = false;
      arRPC = true;
      checkUpdates = false;
      customTitleBar = false;
      disableMinSize = true;
      minimizeToTray = true;
      tray = true;
      splashTheming = true;
      staticTitle = true;
      hardwareAcceleration = true;
      discordBranch = "stable";
      clickTrayToShowHide = true;
      enableTaskbarFlashing = true;
      enableSplashScreen = false;
    };
    vencord = {
      useSystem = true;

      # TEMPORARY, pending a fix upstream in noctalia's discord template.
      #
      # That template takes every colour from the palette except one:
      # --text-tertiary (read channels, category headers) is computed as
      # accent-lightness * --lightness-modifier * 3. --lightness-modifier is
      # 0.225 in dark mode but 2.125 in light, so the light result is ~216%,
      # clamps to white, and the text vanishes into the background. The fix
      # there is to use {{colors.outline}} like every neighbouring line —
      # which is also the token the midnight variant uses for these elements.
      #
      # Until then, pin that one variable to `outline` as resolved for the
      # current palette. Being a literal it will not follow a palette change,
      # so drop this file once the template is fixed. Dark mode is left alone,
      # where the computed value works as intended.
      themes."noctalia-material-light-fix" = ''
        /**
         * @name Noctalia Material light-mode fix
         * @description Restores dimmed text contrast in light mode.
         */

        :root.theme-light,
        .theme-light {
          --text-tertiary: #98896f !important;
        }
      '';

      settings = {
        # The "material" variant of the discord template, plus a local patch
        # for its light mode (see themes below). noctalia.theme.css
        # ("midnight") and discord-system24.css are the alternatives; those are
        # whole-client stylesheets, so only one of the three belongs here — the
        # patch is additive and has to come after the theme it corrects.
        enabledThemes = [
          "noctalia-material.theme.css"
          "noctalia-material-light-fix.css"
        ];
        autoUpdate = false;
        autoUpdateNotification = false;
        notifyAboutUpdates = false;
        winCtrlQ = false;
        plugins = {
          SilentTyping = {
            enabled = true;
            showIcon = true;
            contextMenu = true;
            isEnabled = true;
          };
          FakeNitro.enabled = true;
          ClearURLs.enabled = true;
          AnonymiseFileNames.enabled = true;
          AlwaysTrust = {
            enabled = true;
            domain = true;
            file = false;
          };
        };
      };
    };
  };
}
