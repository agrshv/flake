{ pkgs-unstable, ... }:

{
  home.packages = [
    (pkgs-unstable.brave-origin.override {
      commandLineArgs = [
        "--enable-features=TouchpadOverscrollHistoryNavigation"
        "--ozone-platform=wayland"
      ];
    })
  ];
}
