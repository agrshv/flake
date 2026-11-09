{ pkgs, ... }:
{
  services.paperless = {
    enable = true;
    # paperless-ngx isn't in cache.nixos.org, so it always builds from source on
    # nixpkgs bumps. The stock derivation runs the full pytest suite at build time
    # (doInstallCheck); skip it so the from-source build is fast.
    package = pkgs.paperless-ngx.overrideAttrs (_: {
      doInstallCheck = false;
    });
    domain = "docs.agrshv.dev";
    database.createLocally = true;
    configureTika = true;
    configureNginx = true;
    exporter.enable = true;
    settings = {
      PAPERLESS_OCR_LANGUAGE = "rus+kaz";
      PAPERLESS_FILENAME_FORMAT = "{{ created_year }}/{{ correspondent }}/{{ created }}_{{ title }}_{{ doc_pk }}";
      PAPERLESS_FILENAME_FORMAT_REMOVE_NONE = true;
    };
  };

  # Tika (from configureTika) is a JVM: it exits 128+SIGTERM on a normal stop,
  # which would count every deploy that restarts it as a failure.
  systemd.services.tika.serviceConfig.SuccessExitStatus = [ 143 ];
}
