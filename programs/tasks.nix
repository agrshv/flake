{ config, pkgs, ... }:
let
  # Tasks live in Stalwart's CalDAV (Tasks.org on the phone, iOS Reminders for
  # the shared lists). vdirsyncer mirrors them into plain .ics files, todoman
  # (`todo`) reads and writes those files. Tasks only: events stay in the
  # phone's calendar and Noctalia.
  #
  # Own app password, so this client can be revoked on its own.
  passwordFile = config.sops.secrets."stalwart/vdirsyncer".path;

  # One account is enough: Stalwart lists the shared group's collections
  # (Shopping, To buy later) in d3spair's own calendar home, since d3spair is
  # a member of the group.
  stalwart = home: {
    remote = {
      type = "caldav";
      url = "https://mail.agrshv.dev/dav/cal/${home}/";
      userName = "d3spair@agrshv.dev";
      passwordCommand = [
        "cat"
        passwordFile
      ];
    };
    local = {
      type = "filesystem";
      fileExt = ".ics";
    };
    vdirsyncer = {
      enable = true;
      # The task lists by name on the server (UUID = made by a client). Listed
      # rather than "from a", which would also bring both event calendars down
      # as two empty lists named "Calendar". A new list needs a line here.
      collections = [
        "221496e8-8680-42a3-a991-7ecb12d73ac5" # Inbox
        "c5104b41-1df6-4a35-90f6-3e58a671d585" # Projects
        "658d60a4-b112-4551-b6dd-ae77cf3a61f7" # Someday
        "shopping" # Shopping (shared group)
        "to-buy-later" # To buy later (shared group)
      ];
      itemTypes = [ "VTODO" ];
      # The server name is the list name in `todo`; collection directories
      # are UUIDs.
      metadata = [
        "displayname"
        "color"
      ];
      # A task edited on both sides: the server wins.
      conflictResolution = "remote wins";
    };
  };
in
{
  sops.secrets."stalwart/vdirsyncer".sopsFile = ../secrets/common.yaml;

  accounts.calendar = {
    basePath = ".local/share/tasks";
    accounts.stalwart = stalwart "d3spair@agrshv.dev";
  };

  programs.vdirsyncer.enable = true;
  services.vdirsyncer.enable = true; # every 5 minutes

  # The module only runs metasync and sync; without discover, a list created
  # in `collections` (or the first run) never gets a local directory. `yes`
  # answers its "create the local collection?" prompts; the lists above exist
  # on the server, so only local directories ever get created.
  systemd.user.services.vdirsyncer.Service.ExecStartPre = [
    "${pkgs.writeShellScript "vdirsyncer-discover" ''
      ${pkgs.coreutils}/bin/yes | ${config.services.vdirsyncer.package}/bin/vdirsyncer discover
    ''}"
  ];

  programs.todoman = {
    enable = true;
    glob = "*/*"; # <account>/<list>
    extraConfig = ''
      default_list = "Inbox"
      default_due = 0
      date_format = "%Y-%m-%d"
      time_format = "%H:%M"
      humanize = True
      # Hide tasks whose start date is still ahead (Someday items parked
      # until a date, like Tasks.org's "hide until").
      startable = True
    '';
  };
}
