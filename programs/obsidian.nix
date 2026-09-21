{
  programs.obsidian = {
    enable = true;
    vaults = {
      obsidian = {
        enable = true;
        # Shared with the phone by syncthing (hosts/common/desktop.nix), which
        # is why the directory is named after the folder rather than the app.
        target = "Documents/obsidian";
      };
    };
  };
}
