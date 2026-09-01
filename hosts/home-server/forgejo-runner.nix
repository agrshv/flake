{ config, pkgs, ... }:
{
  # Forgejo Actions runner (forgejo-runner, the maintained `act` fork). Registers
  # against the local Forgejo at git.agrshv.dev and runs workflow jobs in
  # ephemeral containers via podman's docker-compatible socket. Actions
  # themselves are enabled in ./forgejo.nix (services.forgejo.settings.actions).
  #
  # The runner reaches Forgejo over the public HTTPS URL (not http://127.0.0.1:3001)
  # so the server URL injected into jobs — used by actions/checkout to clone from
  # inside the job container — resolves the same way everywhere. The KZ GeoIP gate
  # in ./nginx.nix passes because the host's own egress IP is in Kazakhstan.
  #
  # ── One-time bootstrap on the host ──────────────────────────────────────────
  # 1. Grab a runner registration token from Forgejo, either:
  #      • Site admin → Actions → Runners → "Create new runner"  (instance-wide), or
  #      • as the forgejo user:  forgejo actions generate-runner-token
  # 2. The NixOS module loads `tokenFile` as a systemd EnvironmentFile, so the
  #    secret must be in KEY=VALUE form, not the bare token. Put it in sops:
  #        sops secrets/home-server.yaml
  #    under `forgejo-runner: token: "TOKEN=<registration-token>"`.
  #    (Changing the token or labels later triggers automatic re-registration.)
  # 3. Deploy; the sops restartUnits below re-registers the runner.
  # ────────────────────────────────────────────────────────────────────────────

  # Named after the instance attribute below: `instances.home` produces
  # gitea-runner-home.service. Keep the two in step — a stale name here fails
  # silently, leaving a new token undeployed until something else restarts it.
  sops.secrets."forgejo-runner/token".restartUnits = [ "gitea-runner-home.service" ];

  # Container runtime for job execution. The runner module auto-detects podman,
  # points DOCKER_HOST at /run/podman/podman.sock, and adds the runner to the
  # `podman` group. Rootful is fine — this is a headless single-user box.
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.home = {
      enable = true;
      name = "home";
      url = "https://git.agrshv.dev";
      tokenFile = config.sops.secrets."forgejo-runner/token".path;
      # "<label>:docker://<image>" — a job's `runs-on: <label>` runs in that image.
      labels = [
        "ubuntu-latest:docker://node:20-bookworm"
        "docker:docker://node:20-bookworm"
      ];
    };
  };
}
