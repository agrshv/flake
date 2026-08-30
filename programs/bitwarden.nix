{ config, pkgs, ... }:
let
  # Bitwarden Desktop's SSH agent socket (Linux, non-Flatpak install).
  agentSock = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
in
{
  home.packages = [ pkgs.bitwarden-desktop ];

  # Bitwarden Desktop is the SSH agent: keys live in the vault and each use is
  # approved in the app (Settings → Enable SSH agent). Point the whole session at
  # its socket — login shells via home.sessionVariables, the systemd user manager
  # and everything it spawns (compositor, terminals, git) via environment.d.
  # programs.ssh.startAgent is off in hosts/common/desktop.nix so nothing else
  # claims SSH_AUTH_SOCK.
  home.sessionVariables.SSH_AUTH_SOCK = agentSock;
  systemd.user.sessionVariables.SSH_AUTH_SOCK = agentSock;

  # Start with the session so the agent (and browser biometric unlock) are up
  # before anything needs them. Start-to-tray is an in-app setting.
  xdg.autostart.entries = [ "${pkgs.bitwarden-desktop}/share/applications/bitwarden.desktop" ];
}
