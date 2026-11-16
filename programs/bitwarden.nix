{
  config,
  pkgs,
  lib,
  ...
}:
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
  # before anything needs them. Start-to-tray is an in-app setting. A unit
  # rather than an XDG autostart entry: Hyprland doesn't start
  # xdg-desktop-autostart.target, and turning that on would also run a second
  # kdeconnectd next to its service. Quitting from the tray exits 0, so it
  # stays closed; a launcher click reaches this instance (single-instance lock).
  systemd.user.services.bitwarden = {
    Unit = {
      Description = "Bitwarden (SSH agent)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe pkgs.bitwarden-desktop;
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
