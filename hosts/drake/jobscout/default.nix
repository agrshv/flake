{
  config,
  lib,
  pkgs,
  ...
}:
let
  model = "qwen3:4b";

  # nixpkgs has 1.1.82 (`jobspy`, PyPI July 2025), which predates the fixes
  # this relies on: Glassdoor returning jobs again and the `fetch_description`
  # flag (1.2.0), and `hours_old` no longer returning older jobs on Indeed
  # (1.3.0). Upstream pins curl_cffi>=0.16.2; relaxed to the 0.14 in
  # nixos-26.05, since the API used is long-stable. Its Chrome fingerprint is
  # what Glassdoor's Cloudflare rejects, and unstable's 0.16.0 is no better —
  # jobscout.py switches Glassdoor to Safari instead.
  python-jobspy = pkgs.python3Packages.buildPythonPackage rec {
    pname = "python-jobspy";
    version = "1.3.0";
    pyproject = true;
    src = pkgs.fetchPypi {
      pname = "python_jobspy";
      inherit version;
      hash = "sha256-uEDENCYuBXq4romJW2wrJx2G3p2VBdnalXdyBUxhc2o=";
    };
    build-system = [ pkgs.python3Packages.poetry-core ];
    dependencies = with pkgs.python3Packages; [
      beautifulsoup4
      curl-cffi
      markdownify
      pandas
      pydantic
      requests
    ];
    pythonRelaxDeps = [ "curl_cffi" ];
    pythonImportsCheck = [ "jobspy" ];
  };

  python = pkgs.python3.withPackages (_: [ python-jobspy ]);
in
{
  # Local scorer. CPU-only on the Ampere cores; one model, one request at a
  # time. MemoryMax keeps a runaway context from squeezing stalwart and the
  # exit node out of the shared 12 GB — qwen3:4b at Q4 needs ~3–4 GB; raise
  # the cap before trying an 8B.
  services.ollama = {
    enable = true;
    loadModels = [ model ];
    environmentVariables = {
      OLLAMA_NUM_PARALLEL = "1";
      OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };
  systemd.services.ollama.serviceConfig.MemoryMax = "5G";

  # Nightly scrape → dedupe → hard-filter regexes → LLM score → ntfy "jobs".
  # A failed run alerts through ../common/ntfy-alerts.nix like any unit;
  # jobscout.py exits non-zero when every board comes back empty, which is
  # how a scraper silently broken by a site change shows up.
  systemd.services.jobscout = {
    description = "Job-ad scout (JobSpy + ${model})";
    wants = [
      "network-online.target"
      "ollama-model-loader.service"
    ];
    after = [
      "network-online.target"
      "ollama.service"
      "ollama-model-loader.service"
    ];
    environment = {
      JOBSCOUT_PROFILE = ./profile.md;
      JOBSCOUT_MODEL = model;
      OLLAMA_URL = "http://127.0.0.1:${toString config.services.ollama.port}";
      # Loopback, like the alert units: no dependency on the cert or firewall.
      NTFY_URL = "http://127.0.0.1:2586/jobs";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${python}/bin/python ${./jobscout.py}";
      # NTFY_TOKEN, as used by ntfy-alert@ (see ../ntfy.nix).
      EnvironmentFile = config.sops.secrets."ntfy/env".path;
      DynamicUser = true;
      StateDirectory = "jobscout";
      # ~35 s per scored ad on a 16-thread x86 laptop (2026-10-13); the Ampere
      # cores are slower, and the first night scores a backlog. Each verdict
      # is committed as it lands, so a timeout only defers the rest a night.
      TimeoutStartSec = "4h";
      Nice = 10;
    };
  };

  # 05:00 UTC = 10:00 Almaty: yesterday's German ads, read over breakfast.
  # Clear of postgresqlBackup (02:00) and restic (03:00).
  systemd.timers.jobscout = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };
}
