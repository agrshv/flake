{
  me,
  config,
  lib,
  pkgs,
  ...
}:
let
  host = config.networking.hostName;
  home = "/home/${me.user}";

  # Restic credentials, encrypted to the personal age key only (the desktops
  # decrypt with it, see ./desktop.nix). Until the file exists, and is
  # `git add`ed so the flake can see it, only the local snapshots run; a build
  # warning says so instead of the backup silently never happening.
  secretsFile = ../../secrets/desktop.yaml;
  hasSecrets = builtins.pathExists secretsFile;

  # restic reads a read-only btrfs snapshot of /home, not the live tree:
  # browsers and Electron apps write their SQLite databases constantly and
  # can't be paused the way home-server pauses its services. The snapshot
  # lives on the root subvolume (same filesystem, so it is instant) and is
  # bind-mounted over /home inside the backup unit, so restic records the
  # real /home/... paths and a restore needs no path juggling. It is replaced
  # at the start of the next run rather than deleted after this one: the bind
  # mount keeps it busy until the unit's namespace is gone.
  snapshot = "/var/lib/restic-home";
  btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
in
{
  imports = [ ./ntfy-alerts.nix ];

  config = lib.mkMerge [
    {
      # Local undo: hourly read-only snapshots of /home, browsable (and
      # restorable with a plain cp) under /home/.snapshots/<n>/snapshot. They live
      # on the same disk, so they cover "I deleted that", not a dead or stolen
      # laptop; restic below covers that.
      services.snapper = {
        persistentTimer = true; # a laptop asleep on the hour still gets one on wake
        configs.home = {
          SUBVOLUME = "/home";
          ALLOW_USERS = [ me.user ];
          SYNC_ACL = true; # lets ALLOW_USERS read /home/.snapshots
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
          TIMELINE_LIMIT_HOURLY = 48;
          TIMELINE_LIMIT_DAILY = 14;
          TIMELINE_LIMIT_WEEKLY = 4;
          TIMELINE_LIMIT_MONTHLY = 0;
          TIMELINE_LIMIT_QUARTERLY = 0;
          TIMELINE_LIMIT_YEARLY = 0;
        };
      };
      # snapper expects /home/.snapshots to exist as a subvolume; `v` creates one
      # on btrfs. Nested, so it stays out of the snapshots it holds and out of the
      # restic snapshot below.
      systemd.tmpfiles.rules = [ "v /home/.snapshots 0750 root root -" ];

      ntfyAlerts.enable = hasSecrets;

      warnings = lib.optional (!hasSecrets) ''
        ${host}: secrets/desktop.yaml is missing (or not git-added), so the
        off-site restic backup of /home is disabled; only local snapper
        snapshots run. See hosts/common/desktop-backup.nix.
      '';
    }
    (lib.mkIf hasSecrets {
      sops.secrets = lib.genAttrs [ "restic/repository" "restic/password" "restic/env" "ntfy/env" ] (_: {
        sopsFile = secretsFile;
      });

      # Only this backup alerts: a laptop has plenty of units that fail
      # harmlessly (offline at boot, devices unplugged), unlike the servers.
      ntfyAlerts = {
        allServices = false; # only this backup, see restic-backups-<host> below
        url = "https://ntfy.agrshv.dev:2443/alerts";
        environmentFile = config.sops.secrets."ntfy/env".path;
      };

      systemd.services.restic-home-snapshot = {
        description = "Read-only /home snapshot for restic";
        serviceConfig.Type = "oneshot";
        script = ''
          if [ -e ${snapshot} ]; then
            ${btrfs} subvolume delete ${snapshot}
          fi
          ${btrfs} subvolume snapshot -r /home ${snapshot}
        '';
      };

      services.restic.backups.${host} = {
        initialize = true;

        # secrets/desktop.yaml, same format as home-server's (see its restic.nix):
        #   restic/repository : "s3:https://<b2 s3 endpoint>/<bucket>/<host>"
        #   restic/password   : repo password — keep a copy in Bitwarden too
        #   restic/env        : AWS_ACCESS_KEY_ID=… / AWS_SECRET_ACCESS_KEY=… of a
        #                       B2 application key of its own, so a stolen laptop
        #                       can be revoked without touching the servers' key
        #   ntfy/env          : NTFY_TOKEN=… (the write token the servers use)
        repositoryFile = config.sops.secrets."restic/repository".path;
        passwordFile = config.sops.secrets."restic/password".path;
        environmentFile = config.sops.secrets."restic/env".path;

        paths = [
          # Everything personal, including ~/.ssh and ~/.config/sops/age/keys.txt.
          # The age key opens every secret in this repo, this one included, so a
          # restore needs the restic password from Bitwarden first.
          home
          "/etc/NetworkManager/system-connections" # Wi-Fi and VPN profiles
          "/var/lib/bluetooth" # pairings
        ];

        exclude = [
          # Re-downloadable or regenerable.
          "${home}/.cache"
          "${home}/.local/share/Trash"
          "${home}/.local/share/docker" # rootless docker: images and volumes
          "${home}/.local/share/containers" # podman
          "${home}/.ollama/models"
          "${home}/.npm"
          "${home}/.yarn"
          "${home}/go/pkg"
          "${home}/.local/share/TelegramDesktop/tdata/user_data*" # media cache; login is in tdata
          "node_modules"
          ".direnv"
          # Chromium/Electron caches inside ~/.config (Brave, Vesktop, Teams, …).
          "Cache"
          "Code Cache"
          "GPUCache"
          "CacheStorage"
          "ScriptCache"
          # Work code lives on gitlab.frhc.one; keep it out of a personal bucket.
          # Drop this line if your employer is fine with it.
          "${home}/Documents/aviata"
        ];

        # Skips any directory tagged with CACHEDIR.TAG: cargo's target/, and
        # the caches of most tools that follow the convention.
        extraBackupArgs = [ "--exclude-caches" ];

        # Don't let a lid close cut an upload short.
        inhibitsSleep = true;

        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 5"
          "--keep-monthly 12"
        ];
        checkOpts = [ "--read-data-subset=5%" ];

        timerConfig = {
          OnCalendar = "*-*-* 13:00:00"; # midday: the laptop is more likely awake
          Persistent = true; # missed while asleep or off: run on the next boot or wake
          RandomizedDelaySec = "30min";
        };
      };

      systemd.services."restic-backups-${host}" = {
        requires = [ "restic-home-snapshot.service" ];
        after = [ "restic-home-snapshot.service" ];
        onFailure = [ "ntfy-alert@%N.service" ];
        # A run right after wake often finds no network yet. Retry a few times
        # before giving up; ntfy-alert only fires once the unit stays failed.
        unitConfig = {
          StartLimitIntervalSec = "3h";
          StartLimitBurst = 4;
        };
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "20min";
          BindReadOnlyPaths = [ "${snapshot}:/home" ];
        };
      };
    })
  ];
}
