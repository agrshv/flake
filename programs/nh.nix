{ config, ... }:

{
  programs.nh = {
    enable = true;
    flake = "${config.xdg.userDirs.documents}/flake";
  };
}