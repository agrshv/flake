{
  pkgs,
  lib,
  pkgs-unstable,
  ...
}:
{
  # Themed by noctalia instead: its community `zed` template (enabled in
  # programs/noctalia.nix) renders ~/.config/zed/themes/noctalia.json.
  catppuccin.zed.enable = false;

  home.sessionVariables.EDITOR = "${pkgs-unstable.zed-editor}/bin/zeditor -w";

  programs.zed-editor = {
    enable = true;
    mutableUserDebug = false;
    mutableUserKeymaps = false;
    mutableUserSettings = false;
    mutableUserTasks = false;
    package = pkgs-unstable.zed-editor;
    userKeymaps = [
      {
        # ctrl-tab cycles tabs in visible left-to-right order instead of Zed's
        # default MRU tab switcher (tab_switcher::Toggle), which feels unintuitive.
        context = "Pane";
        bindings = {
          "ctrl-tab" = "pane::ActivateNextItem";
          "ctrl-shift-tab" = "pane::ActivatePreviousItem";
        };
      }
      {
        # Disable the collaboration ("GitHub") panel toggle so it stops opening.
        # Scoped to Workspace so the terminal's ctrl-shift-c copy still works.
        context = "Workspace";
        bindings = {
          "ctrl-shift-c" = null;
        };
      }
      {
        # shift-enter sends ESC+CR (meta-enter) in the terminal, for REPLs/TUIs
        # that expect that escape sequence. Nix double-quoted strings have no unicode escape, so decode
        # the exact JSON string ("\u001b\r") via fromJSON.
        context = "Terminal";
        bindings = {
          "shift-enter" = [
            "terminal::SendText"
            (builtins.fromJSON ''"\u001b\r"'')
          ];
        };
      }
    ];
    extensions = [
      "nix"
      "git-firefly"
      "opentofu"
      "dockerfile"
      "toml"
      "rego"
      "sql"
    ];
    userSettings = {
      # NixOS can't run Zed's auto-downloaded generic-linux node binary
      # (~/.local/share/zed/node/...); point Zed at the Nix-provided one.
      node = {
        ignore_system_version = false;
        path = lib.getExe pkgs.nodejs;
        npm_path = "${lib.getExe' pkgs.nodejs "npm"}";
      };
      # Theme names inside ~/.config/zed/themes/noctalia.json. Zed watches that
      # directory, so a palette change lands without a restart. Both modes are
      # named even though noctalia is pinned to dark, so flipping it there is
      # all it takes. ("Noctalia {Dark,Light} Transparent" also exist.)
      theme = {
        mode = "dark";
        dark = "Noctalia Dark";
        light = "Noctalia Light";
      };
      autosave.after_delay.milliseconds = 1000;
      agent_servers.claude-acp = {
        type = "registry";
        # NB: a per-agent `default_mode` is NOT a setting Zed 1.16 understands
        # (its per-agent keys are command/env/default_model/favorite_models/
        # default_config_options/favorite_config_option_values), so it was
        # silently ignored. A new thread's starting model and permission mode
        # come from Claude Code's own ~/.claude/settings.json (`model` and
        # `permissions.defaultMode`); picking either from the panel dropdowns
        # can't stick, because Zed persists that choice by rewriting
        # ~/.config/zed/settings.json, which mutableUserSettings = false makes
        # a read-only /nix/store symlink.
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
      lsp.nil = {
        binary.path = "${lib.getExe pkgs.nil}";
        settings.nil.nix.flake.autoArchive = true;
      };
      lsp.nixd.binary.path = "${lib.getExe pkgs.nixd}";
      lsp.package-version-server.binary.path = "${lib.getExe pkgs.package-version-server}";
      lsp.yaml-language-server = {
        binary.path = "${lib.getExe pkgs.yaml-language-server}";
        # The Nix binary is the raw vscode-languageserver entrypoint, which
        # refuses to start without a transport flag. Zed only injects --stdio
        # for its bundled server, not for an overridden binary.path.
        binary.arguments = [ "--stdio" ];
        settings.yaml = {
          # Auto-associate well-known files (kustomization.yaml, Helm Chart.yaml,
          # GitHub Actions, compose, ...) with schemas from the JSON Schema Store.
          schemaStore.enable = true;
          # Apply the bundled Kubernetes schema only within manifest dirs, so
          # plain k8s resources get completions without redlining other YAML.
          schemas.kubernetes = [
            "k8s/**/*.{yaml,yml}"
            "manifests/**/*.{yaml,yml}"
            "deploy/**/*.{yaml,yml}"
            "kube/**/*.{yaml,yml}"
          ];
        };
      };
      show_whitespaces = "trailing";
      use_system_path_prompts = false;
      ensure_final_newline_on_save = true;
      buffer_font_family = "JetBrains Mono";
      ui_font_family = "JetBrains Mono";
      collaboration_panel.button = false;
    };
  };
}
