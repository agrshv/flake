{ pkgs, ... }:

{
  programs.ghostty = {
    enable = true;
    settings = {
      custom-shader = toString (pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/0xhckr/ghostty-shaders/aa6121ba2ddd5251ac75b92729c758fe41256e55/cursor_blaze.glsl";
        sha256 = "0g2lgqjdrn3c51glry7x2z30y7ml0y61arl5ykmf4yj0p85s5f41";
      });
    };
  };
}
