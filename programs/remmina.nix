{
  services.remmina = {
    enable = true;
    systemdService.enable = false;
  };

  # Remmina's "start in tray" preference writes this file itself, which is
  # what kept launching the applet at login (systemd's xdg-autostart generator
  # turns it into app-remmina\x2dapplet@autostart.service). Owning it here with
  # Hidden=true turns that off for good: the toggle in Remmina can no longer
  # flip it back, since the file is now a read-only store symlink.
  xdg.configFile."autostart/remmina-applet.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Remmina Applet
    Exec=remmina -i
    Hidden=true
  '';
}
