{ ... }:
{
  programs.direnv = {
    enable = true;
    # Caches nix-shell/flake environments in .direnv/ so entering a directory
    # doesn't re-evaluate the flake every time, and keeps envs alive across GC.
    nix-direnv.enable = true;
  };
}
