{ pkgs, lib, ... }:
{
  services.swayidle = {
    enable = false;
    timeouts = [
      {
        timeout = 300;
        command = "${lib.getExe pkgs.swaylock} -f";
      }
      {
        timeout = 600;
        command = "${lib.getExe' pkgs.sway "swaymsg"} 'output * dpms off'";
        resumeCommand = "${lib.getExe' pkgs.sway "swaymsg"} 'output * dpms on'";
      }
    ];
    events = [
      {
        event = "before-sleep";
        command = "${lib.getExe pkgs.swaylock} -f";
      }
      {
        event = "lock";
        command = "${lib.getExe pkgs.swaylock} -f";
      }
    ];
  };
}
