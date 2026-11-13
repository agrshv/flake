{ pkgs, lib, ... }:

let
  fd = "${lib.getExe pkgs.fd} --hidden --exclude .git";
in
{
  # `z <part of a path>` jumps to the best-ranked directory visited before.
  programs.zoxide.enable = true;

  # Ctrl-R history, Ctrl-T files, Alt-C directories, listed by fd so
  # .gitignore is respected and dotfiles are included.
  programs.fzf = {
    enable = true;
    defaultCommand = "${fd} --type f";
    fileWidgetCommand = "${fd} --type f";
    changeDirWidgetCommand = "${fd} --type d";
  };

  programs.bat.enable = true;
  programs.ripgrep.enable = true;
  programs.fd.enable = true;

  # `tldr tar`: short examples instead of the man page.
  programs.tealdeer = {
    enable = true;
    settings.updates.auto_update = true;
  };

  # rm moves to the freedesktop trash (the one file managers use) in
  # interactive shells; trash-put takes rm's -r/-f/-d and ignores them.
  # Scripts and `\rm` still delete for real; the hourly snapper snapshots
  # (hosts/common/desktop-backup.nix) cover those. Restore with
  # `trash-restore`, list with `trash-list`.
  home.packages = [ pkgs.trash-cli ];
  home.shellAliases.rm = "trash-put";

  # Items trashed more than 30 days ago are purged weekly, so the trash
  # (excluded from the restic backup) doesn't grow forever.
  systemd.user.services.trash-empty = {
    Unit.Description = "Purge trash older than 30 days";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.trash-cli}/bin/trash-empty -f 30";
    };
  };
  systemd.user.timers.trash-empty = {
    Unit.Description = "Purge trash older than 30 days";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
