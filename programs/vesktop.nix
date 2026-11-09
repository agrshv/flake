{ lib, pkgs, ... }:
let
  # Discord's Nov 2026 rspack build changed how modules export, and Vencord
  # before 1.15.16 leaves those exports undefined: the client throws
  # "i.A is not a constructor" at startup and Vesktop shows a white window.
  # nixpkgs still ships 1.15.13; drop this once it reaches 1.15.16.
  vencord =
    if lib.versionAtLeast pkgs.vencord.version "1.15.16" then
      pkgs.vencord
    else
      pkgs.vencord.overrideAttrs (
        finalAttrs: prev: {
          version = "1.15.16";
          src = prev.src.override {
            tag = "v${finalAttrs.version}";
            hash = "sha256-aUJubLJpyLAZWiOezqFxPY6oVPgWVPQpajFqrJvrO9U=";
          };
          # nixpkgs' lockfile patch and postPatch bump @types/react to 19;
          # upstream's pnpm catalog pins 19.2.3 itself now, so neither applies.
          patches = [ ];
          postPatch = "";
          pnpmDeps = prev.pnpmDeps.overrideAttrs {
            patches = [ ];
            postPatch = "";
            outputHash = "sha256-1HcQH0ZZixQvziehIDhyBUB8v5ckufxrS2yUq2BcMVQ=";
          };
        }
      );
in
{
  programs.vesktop = {
    enable = true;
    package = pkgs.vesktop.override { inherit vencord; };
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
      settings = {
        # The "midnight" variant of noctalia's discord template: it maps every
        # colour straight to a palette role, so contrast holds in light mode
        # and with wallpaper-generated palettes. The "material" variant
        # (noctalia-material.theme.css) derives most fills from the accent's
        # lightness with dark-mode factors, so a dark light-mode `primary`
        # turned the chat bar and buttons navy under dark text.
        # discord-system24.css is the third option; all three are
        # whole-client stylesheets, so only one belongs here.
        enabledThemes = [ "noctalia.theme.css" ];
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
