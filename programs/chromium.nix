{ pkgs, ... }:

{
  home.packages = [
    (pkgs.brave.override {
      commandLineArgs = [
        "--enable-features=TouchpadOverscrollHistoryNavigation"
        "--ozone-platform=wayland"
      ];
    })
  ];

  programs.brave.nativeMessagingHosts = [ pkgs.keepassxc ];
}
