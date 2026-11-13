{ pkgs, ... }:
{
  programs.bash = {
    enable = true;
    # Hand interactive terminals over to fish (programs/fish.nix), the pattern
    # the NixOS wiki recommends over making fish the login shell. Skipped when
    # the parent already is fish (so `bash` from fish stays bash) and for
    # `bash -c ...`, which tools use to run commands.
    initExtra = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]; then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;
}
