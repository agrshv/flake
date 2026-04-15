{
  services.paperless = {
    enable = true;
    domain = "docs.agrshv.dev";
    database.createLocally = true;
    configureTika = true;
    configureNginx = true;
    settings = {
      PAPERLESS_OCR_LANGUAGE = "rus+kaz";
    };
  };
}
