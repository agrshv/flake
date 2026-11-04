{ config, ... }:
{
  # OPENROUTER_API_KEY=<key>: a drake-only key with a monthly credit limit, so
  # a runaway loop can't drain the account.
  sops.secrets."jobscout/env" = { };

  # The scout itself lives in github.com/agrshv/jobscout (moved 2026-11-03);
  # this file keeps what depends on drake. It scores through OpenRouter
  # (Gemini 3.7 Flash on Vertex) since 2026-11-04, so ollama is off here: the
  # local qwen3:4b ranked his applications worse than chance.
  services.jobscout = {
    enable = true;
    # Loopback, like the alert units: no dependency on the cert or firewall.
    ntfyUrl = "http://127.0.0.1:2586/jobs";
    environmentFiles = [
      # NTFY_TOKEN, as used by ntfy-alert@ (see ./ntfy.nix).
      config.sops.secrets."ntfy/env".path
      config.sops.secrets."jobscout/env".path
    ];
    # 05:00 UTC = 10:00 Almaty: yesterday's German ads, read over breakfast.
    # Clear of postgresqlBackup (02:00) and restic (03:00).
    onCalendar = "*-*-* 05:00:00";
  };
}
