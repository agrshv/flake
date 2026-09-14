{ pkgs, pkgs-unstable, ... }:

{
  # Themed by noctalia instead (the `ghostty` builtin template in
  # programs/noctalia.nix), so the terminal follows the shell's palette.
  catppuccin.ghostty.enable = false;

  programs.ghostty = {
    enable = true;
    package = pkgs-unstable.ghostty;
    settings = {
      # noctalia writes the palette to ~/.config/ghostty/themes/noctalia and
      # its apply hook then points the config at it — except this config is a
      # read-only store symlink, so the pointer is set here instead. The hook
      # sees it is already correct and leaves the file alone.
      theme = "noctalia";
      custom-shader = toString (
        pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/0xhckr/ghostty-shaders/aa6121ba2ddd5251ac75b92729c758fe41256e55/cursor_blaze.glsl";
          sha256 = "0g2lgqjdrn3c51glry7x2z30y7ml0y61arl5ykmf4yj0p85s5f41";
        }
      );
    };
  };
}
