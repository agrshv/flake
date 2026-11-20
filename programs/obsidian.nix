{
  programs.obsidian = {
    enable = true;
    vaults = {
      obsidian = {
        enable = true;
        # Named after the folder syncthing used to share with the phone,
        # rather than after the app.
        target = "Documents/obsidian";
      };
    };
  };
}
