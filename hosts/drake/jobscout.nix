{ config, ... }:
{
  # The scout itself lives in github.com/agrshv/jobscout (moved 2026-11-03);
  # this file keeps what depends on drake.
  services.jobscout = {
    enable = true;
    # Loopback, like the alert units: no dependency on the cert or firewall.
    ntfyUrl = "http://127.0.0.1:2586/jobs";
    # NTFY_TOKEN, as used by ntfy-alert@ (see ./ntfy.nix).
    environmentFile = config.sops.secrets."ntfy/env".path;
    # 05:00 UTC = 10:00 Almaty: yesterday's German ads, read over breakfast.
    # Clear of postgresqlBackup (02:00) and restic (03:00).
    onCalendar = "*-*-* 05:00:00";
  };

  # MemoryMax keeps a runaway context from squeezing stalwart and the exit
  # node out of the shared 12 GB — qwen3:4b at Q4 needs ~3–4 GB; raise the
  # cap before trying an 8B. The cap held RAM but not swap until swap was
  # capped too: the OOM-killed runner had 3.9G swapped out (2026-10-16).
  systemd.services.ollama.serviceConfig = {
    MemoryMax = "5G";
    MemorySwapMax = "1G";
  };
}
