{ pkgs, ... }:
{
  services.paperless = {
    enable = true;
    # paperless-ngx isn't in cache.nixos.org, so it always builds from source on
    # nixpkgs bumps. The stock derivation runs the full pytest suite at build time
    # (doInstallCheck); skip it so the from-source build is fast.
    package = pkgs.paperless-ngx.overrideAttrs (_: { doInstallCheck = false; });
    domain = "docs.agrshv.dev";
    database.createLocally = true;
    configureTika = true;
    configureNginx = true;
    settings = {
      PAPERLESS_OCR_LANGUAGE = "rus+kaz";
    };
  };
}
