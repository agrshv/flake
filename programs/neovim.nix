{ config, pkgs, ... }:

{
  home.sessionVariables.EDITOR = "${pkgs.neovim}/bin/nvim";

  # MiniMax (github.com/nvim-mini/MiniMax, configs/nvim-0.12) — a starter
  # config, not a distribution: ./nvim is ours to edit and never syncs back.
  home.packages = with pkgs; [
    neovim
    # mini.pick greps with ripgrep; git (for vim.pack) comes from git.nix.
    ripgrep
    # nvim-treesitter's main branch builds parsers locally.
    tree-sitter
    gcc
    # Language servers enabled in ./nvim/plugin/40_plugins.lua. On PATH, not
    # Mason: its downloaded binaries don't run on NixOS.
    dockerfile-language-server
    lua-language-server
    nixd
    pyright
    regal
    taplo
    tofu-ls
    yaml-language-server
  ];

  # Link the checkout, not a store copy: vim.pack rewrites
  # nvim-pack-lock.json in the config dir on every install/update, and edits
  # should apply without a rebuild. Commit the lockfile to pin plugins.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.programs.nh.flake}/programs/nvim";
}
