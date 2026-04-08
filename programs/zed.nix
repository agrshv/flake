{ pkgs, inputs, ... }:

let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  home.sessionVariables.EDITOR = "${pkgs-unstable.zed-editor}/bin/zeditor -w";

  programs.zed-editor = {
    enable = true;
    mutableUserDebug = false;
    mutableUserKeymaps = false;
    mutableUserSettings = false;
    mutableUserTasks = false;
    package = pkgs-unstable.zed-editor;
    extensions = [
      "nix"
      "git-firefly"
      "opentofu"
      "dockerfile"
      "toml"
      "rego"
    ];
    extraPackages = with pkgs; [
      nixd
      nil
      package-version-server
    ];
    userSettings = {
      autosave.after_delay.milliseconds = 1000;
      agent_servers.claude-acp = {
        type = "registry";
        env.CLAUDE_CODE_EXECUTABLE = "${pkgs.claude-code}/bin/claude";
      };
      ui_font_size = 16;
      buffer_font_size = 15;
      colorize_brackets = true;
      auto_update = false;
      title_bar = {
        show_sign_in = false;
        show_onboarding_banner = false;
      };
      tabs.show_close_button = "hidden";
      lsp.nil.settings.nil.nix.flake.autoArchive = true;
    };
  };
}
