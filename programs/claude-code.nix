{ pkgs, inputs, ... }:

let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  programs.claude-code = {
    enable = true;
    package = pkgs-unstable.claude-code;
  };
}
