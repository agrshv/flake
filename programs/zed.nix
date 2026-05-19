{
  pkgs,
  lib,
  pkgs-unstable,
  ...
}:
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
        env.CLAUDE_CODE_EXECUTABLE = "${lib.getExe pkgs-unstable.claude-code}";
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
      show_whitespaces = "trailing";
      use_system_path_prompts = false;
      ensure_final_newline_on_save = true;
      buffer_font_family = "JetBrains Mono";
      ui_font_family = "JetBrains Mono";
      collaboration_panel.button = false;
    };
  };
}
