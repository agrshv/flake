# Formatters and linters behind `nix fmt` (via treefmt-nix, see flake.nix).
# `nix fmt` rewrites files in place; `nix fmt -- --ci` and the `treefmt` flake
# check fail instead, which is how CI enforces all of this.
{
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true;
    # Unused bindings and arguments, removed in place.
    deadnix.enable = true;
    statix = {
      enable = true;
      # Modules group settings per service (services.sonarr = …,
      # services.radarr = …, networking.nat = …) on purpose: folding them into
      # one attrset would separate each setting from the comment explaining it.
      disabled-lints = [ "repeated_keys" ];
    };
    # The neovim config under programs/nvim, in its existing (mini.nvim) style.
    stylua = {
      enable = true;
      settings = {
        indent_type = "Spaces";
        indent_width = 2;
        column_width = 100;
        collapse_simple_statement = "Always";
        quote_style = "AutoPreferSingle";
      };
    };
    actionlint.enable = true;
    yamlfmt = {
      enable = true;
      # Keep the blank lines that separate commented blocks.
      settings.formatter.retain_line_breaks_single = true;
    };
  };

  settings = {
    # sops-encrypted; their layout is sops' to write.
    formatter.yamlfmt.excludes = [ "secrets/*" ];
  };
}
