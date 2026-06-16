{
  services.mako = {
    enable = false;
    settings = {
      default-timeout = 5000;
      # ignore-timeout = true;
      border-size = 2;
      padding = "10";
      margin = "10";
      width = 300;
      height = 100;
      max-visible = 5;
      layer = "overlay";
      anchor = "top-right";

      "urgency=low" = {
        default-timeout = 3000;
      };
      "urgency=critical" = {
        default-timeout = 0;
        border-color = "#fab387";
      };
    };
  };
}
