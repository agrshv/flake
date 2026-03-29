{ pkgs, inputs, ... }:

let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  programs.zed-editor = {
    enable = true;
    mutableUserDebug = false;
    mutableUserKeymaps = false;
    mutableUserSettings = false;
    mutableUserTasks = false;
    package = pkgs-unstable.zed-editor;
    extraPackages = with pkgs; [
      nixd
      nil
      package-version-server
    ];
    userSettings = {
      autosave.after_delay.milliseconds = 1000;
      agent_servers.claude-acp = {
        type = "registry";
        env.CLAUDE_CODE_EXECUTABLE = "${pkgs.claude-code}";
      };
      ui_font_size = 16;
      buffer_font_size = 15;
      colorize_brackets = true;
      auto_update = false;
      title_bar = {
        show_sign_in = false;
        show_onboarding_banner = true;
      };
      tabs.show_close_button = "hidden";
      
    };
  };
}
