{ ... }:
{
  # security.lockKernelModules = true;

  services.netbird.enable = true;

  services.openssh = {
    enable = true;
    startWhenNeeded = true;
    settings.PasswordAuthentication = false;
  };

  # Show asterisks while typing the sudo password.
  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';
}
