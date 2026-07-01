{ pkgs, ... }:
let
  # vesktop is built with pnpm-10.29.2, which the current nixpkgs marks insecure
  # (CVE-2026-48995 et al.). pnpm only runs inside the sandboxed build to assemble
  # node_modules — it never runs on the system — so the risk is nil. Permit it in a
  # throwaway pkgs instance used solely to build vesktop, rather than globally
  # permitting the insecure package system-wide.
  pkgs' = import pkgs.path {
    inherit (pkgs) system overlays;
    config = pkgs.config // {
      permittedInsecurePackages = [ "pnpm-10.29.2" ];
    };
  };
in
{
  programs.vesktop = {
    enable = true;
    package = pkgs'.vesktop;
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
