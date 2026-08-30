{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    signing.format = "ssh";
    settings = {
      core.pager = "${pkgs.delta}/bin/delta";
      commit.gpgsign = true;
      interactive.diffFilter = "${pkgs.delta}/bin/delta --color-only";
      delta.navigate = true;
      merge.conflictStyle = "zdiff3";
      push.autoSetupRemote = true;
      fetch.parallel = 10;
      init.defaultBranch = "master";
      alias.co = "checkout";
      pull.rebase = true;
    };
    includes = [
      {
        condition = "hasconfig:remote.*.url:ssh://git@codeberg.org/*/**";
        contents.user = {
          name = "agrshv";
          email = "anton@agrshv.dev";
          signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb";
        };
      }
      {
        condition = "hasconfig:remote.*.url:ssh://forgejo@git.agrshv.dev/*/**";
        contents.user = {
          name = "agrshv";
          email = "anton@agrshv.dev";
          signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb";
        };
      }
      {
        condition = "hasconfig:remote.*.url:ssh://git@github.com/*/**";
        contents.user = {
          name = "agrshv";
          email = "anton@agrshv.dev";
          signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb";
        };
      }
    ];
  };
}
