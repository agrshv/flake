{
  # Interactive shell only. bash stays the login shell (programs/bash.nix hands
  # interactive terminals over to fish), so logins, `nix develop`, scripts and
  # tools that expect POSIX keep getting bash. starship, eza, direnv, zoxide,
  # fzf and nix-index hook in through home.shell.enableFishIntegration.
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting
    '';
  };
}
