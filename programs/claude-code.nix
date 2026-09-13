{ pkgs-unstable, ... }:
{
  programs.claude-code = {
    enable = true;
    package = pkgs-unstable.claude-code;

    # Declaring `settings` turns ~/.claude/settings.json into a read-only
    # /nix/store symlink, so the CLI can no longer persist its own writes to it:
    # `/model`, `/theme` and the notification toggle still work, but only for
    # the running session. Change them here instead.
    settings = {
      # Default model for every new session — including the threads Zed starts
      # through the claude-acp agent server (see programs/zed.nix), which get no
      # model from Zed and so fall back to whatever this says. `[1m]` picks the
      # 1M-context Opus 5; it counts 5x against rate limits, plain "opus" is the
      # regular 200k one.
      model = "opus[1m]";
      permissions = {
        # Start in Auto rather than Claude Code's own default of "ask each
        # time": no routine permission prompts, a reviewer model screens
        # actions instead. Read at session creation, so it covers Zed threads
        # too — Zed 1.16 has no per-agent mode setting of its own.
        defaultMode = "auto";
      };
      tui = "fullscreen";
      theme = "auto";
      agentPushNotifEnabled = true;
    };
  };
}
