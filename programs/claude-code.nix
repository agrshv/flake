{ pkgs, pkgs-unstable, ... }:
{
  # Tools Claude reaches for in its own shell; without them it falls back to
  # clumsier python/sed one-liners.
  home.packages = with pkgs; [
    jq
    fd
    yq-go
  ];

  programs.claude-code = {
    enable = true;
    package = pkgs-unstable.claude-code;

    # ~/.claude/CLAUDE.md — loaded into every session, in every project.
    context = ''
      # Conventions

      - Commit messages: Conventional Commits, `type(scope): lowercase summary`
        (e.g. `feat(noctalia): show the phone's battery as a percentage`). Types:
        feat, fix, refactor, perf, docs, test, build, ci, chore, revert; `!` after
        the scope for breaking changes. Only commit or push when asked.
      - Before saying a change is done, use the `verify` skill.
      - Nix: format with `nix fmt`; rebuild with `nh os switch` / `nh home switch`,
        never call `nixos-rebuild` directly.
      - Secrets are sops-encrypted (`secrets/*.yaml`); never decrypt or print them.
      - Terraform: `terraform fmt` and `terraform validate` freely; never `apply` or
        `destroy` without asking.
      - Kubernetes / Flux: read-only (`get`, `describe`, `logs`, `flux get`) unless
        told otherwise. Never `flux reconcile`, `kubectl apply/delete/edit` on your own.
      - Work GitLab is self-hosted at gitlab.frhc.one; use `glab` for MRs, pipelines
        and issues. Open MRs with the `gitlab-mr` skill: every MR links its Asana task.
    '';

    # Language servers give Claude go-to-definition and diagnostics instead of
    # grepping. Bundled into a plugin passed via the wrapper's --plugin-dir.
    lspServers = {
      nix = {
        command = "${pkgs.nixd}/bin/nixd";
        extensionToLanguage.".nix" = "nix";
      };
      terraform = {
        command = "${pkgs.terraform-ls}/bin/terraform-ls";
        args = [ "serve" ];
        extensionToLanguage = {
          ".tf" = "terraform";
          ".tfvars" = "terraform-vars";
        };
      };
      yaml = {
        command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
        args = [ "--stdio" ];
        extensionToLanguage = {
          ".yaml" = "yaml";
          ".yml" = "yaml";
        };
      };
      python = {
        command = "${pkgs.pyright}/bin/pyright-langserver";
        args = [ "--stdio" ];
        extensionToLanguage.".py" = "python";
      };
    };

    skills.verify = ''
      ---
      name: verify
      description: Check that a change actually works before calling it done — formatting, evaluation, builds, Terraform validate/plan, Kubernetes manifest rendering. Use after editing Nix, Terraform, Kubernetes/Flux YAML or Python, and before committing or reporting a task as finished.
      ---

      # Verify

      Run the checks for every kind of file you touched, from the repo root.
      Stop at the first failure, fix it, and re-run from that step. Report
      what ran and what passed; never claim success for a check you skipped,
      and say why it was skipped.

      ## Nix flake

      1. `nix fmt -- --ci` (fails if anything needs formatting)
      2. `nix flake check --no-build` (evaluates every output)
      3. Build each host the change can affect. For a NixOS host:
         `nix build --no-link .#nixosConfigurations.<host>.config.system.build.toplevel`.
         If the host's system differs from this machine's (e.g. aarch64), only
         evaluate it: `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
         Home-manager only: `.#nixosConfigurations.<host>.config.home-manager.users.<user>.home.activationPackage`.
      4. Do not run `nh os switch` or anything that activates a configuration
         unless asked.

      ## Terraform / OpenTofu

      1. `terraform fmt -check -recursive`
      2. `terraform init -backend=false` if `.terraform/` is missing, then `terraform validate`
      3. `terraform plan` only when credentials and state access are already
         set up; summarize what it adds, changes and destroys, and call out
         anything destroyed or replaced. Never `apply`.

      ## Kubernetes / Flux YAML

      1. `kustomize build <dir>` (or `kubectl kustomize <dir>`) for every
         kustomization containing a changed file.
      2. Pipe the output through `kubeconform -strict -ignore-missing-schemas -summary`
         if available.
      3. With cluster access: `flux diff kustomization <name> --path <dir>` to
         show what would change. Never `flux reconcile`, `kubectl apply` or
         anything that writes to a cluster.

      ## Python

      1. `ruff check` and `ruff format --check` if ruff is available.
      2. `pyright <files>` if a pyright config or virtualenv exists.
      3. Run the project's tests (`pytest`) if there are any.

      Tools that aren't on PATH can be pulled ad hoc with
      `nix shell nixpkgs#<pkg> -c <cmd>`.
    '';

    skills.gitlab-mr = ''
      ---
      name: gitlab-mr
      description: Open a merge request on the work GitLab (gitlab.frhc.one) with the Asana task linked in its description. Use whenever asked to create, open or submit an MR / merge request / PR in a work repo.
      ---

      # GitLab merge request with an Asana link

      ## 1. Find the Asana task. Never invent or guess a URL.

      In order, stop at the first hit:
      1. A task URL or ID the user gave in this conversation.
      2. An `app.asana.com` URL in the branch's commit messages
         (`git log <default>..HEAD`), or in an earlier MR from this branch.
      3. A task ID in the branch name (e.g. `DEVOPSSUP-6951`): look it up with
         the Asana tools if they're available.
      4. If the Asana tools are available, search the tasks assigned to me for
         one matching the change, and ask me to confirm the match.
      5. Otherwise ask me for it. If I say there is none, open the MR without one.

      Use the task's permalink, in the form
      `https://app.asana.com/1/1208507351529750/project/<project>/task/<task>`.

      ## 2. Write the MR

      - Title: Conventional Commits, `type(scope): lowercase summary`, same as
        the commit title when the branch has a single commit.
      - Description: plain prose, wrapped at ~72 columns, explaining why the
        change is needed and anything a reviewer can't see in the diff.
        No headings, no "Summary"/"Test plan" boilerplate. Skip the prose
        entirely for trivial changes (fmt, version bumps).
      - The Asana URL goes alone on the **last line** of the description, after
        a blank line. If there's no prose, the URL is the whole description.

      ## 3. Create it

      Commit only what I asked for, push with `git push -u origin HEAD`, then:

      ```sh
      glab mr create \
        --title "<title>" \
        --description "<description>" \
        --target-branch <default branch> \
        --assignee anton.groshev \
        --squash-before-merge=true \
        --remove-source-branch=true \
        --yes
      ```

      The default branch is `git symbolic-ref --short refs/remotes/origin/HEAD`
      minus `origin/`; if that ref is missing, run `git remote set-head origin --auto`
      first.

      No reviewers, labels or `--draft` unless I ask. If an MR for the branch
      already exists (`glab mr view`), update it with `glab mr update` instead
      of opening a second one. Finish by printing the MR URL.
    '';

    # Live Terraform Registry docs (providers, modules, resource schemas), so
    # it stops guessing argument names from training data. The official
    # marketplace's terraform plugin does the same through docker; this is the
    # nixpkgs build of the same server.
    mcpServers.terraform = {
      command = "${pkgs.terraform-mcp-server}/bin/terraform-mcp-server";
      args = [ "stdio" ];
    };

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
        # Hard stops that hold regardless of what the auto-mode reviewer thinks.
        deny = [
          "Read(~/.config/sops/age/**)"
          "Read(~/.ssh/id_*)"
          "Bash(terraform apply:*)"
          "Bash(terraform destroy:*)"
        ];
      };
      # Stop it appending a "Co-Authored-By: Claude" trailer to commits it
      # writes (and the matching footer on pull request descriptions).
      includeCoAuthoredBy = false;

      # `/plugin install` can't record these itself (settings.json is
      # read-only), so they're enabled here. Most come from the official
      # marketplace, which Claude Code registers on its own; any other
      # marketplace has to be declared too, since `/plugin marketplace add`
      # can't record it either.
      extraKnownMarketplaces.cloudflare.source = {
        source = "github";
        repo = "cloudflare/skills";
      };
      enabledPlugins = {
        # Cloudflare skills (Workers, Wrangler, etc.) plus the Cloudflare API
        # MCP server, which asks for OAuth on first use.
        "cloudflare@cloudflare" = true;
        # /revise-claude-md etc.: audit CLAUDE.md files and fold session
        # learnings back into them.
        "claude-md-management@claude-plugins-official" = true;
        # Up-to-date library/framework docs on demand; asks to authenticate
        # with Context7 on first use.
        "context7@claude-plugins-official" = true;
      };

      # Real hooks live here. The module's own `hooks` option only drops
      # scripts into ~/.claude/hooks/ without registering them anywhere.
      hooks.PostToolUse = [
        {
          # Keep .nix files in the flake's own style (see `formatter` in
          # flake.nix) after every edit Claude makes.
          matcher = "Edit|MultiEdit|Write";
          hooks = [
            {
              type = "command";
              command = toString (
                pkgs.writeShellScript "claude-nixfmt" ''
                  f=$(${pkgs.jq}/bin/jq -r '.tool_input.file_path // empty')
                  [[ $f == *.nix && -f $f ]] && ${pkgs.nixfmt}/bin/nixfmt "$f"
                  exit 0
                ''
              );
            }
          ];
        }
      ];

      # model · dir · git branch (* if dirty) · context used · 5h rate limit.
      statusLine = {
        type = "command";
        command = toString (
          pkgs.writeShellScript "claude-statusline" ''
            in=$(cat)
            jqr() { ${pkgs.jq}/bin/jq -r "$1" <<<"$in"; }
            dir=$(jqr '.workspace.current_dir')
            out="$(jqr '.model.display_name') · ''${dir/#$HOME/\~}"
            if branch=$(${pkgs.git}/bin/git -C "$dir" branch --show-current 2>/dev/null) && [[ -n $branch ]]; then
              [[ -n $(${pkgs.git}/bin/git -C "$dir" status --porcelain 2>/dev/null) ]] && branch+="*"
              out+=" · $branch"
            fi
            ctx=$(jqr '.context_window.used_percentage // empty | floor')
            [[ -n $ctx ]] && out+=" · ctx $ctx%"
            limit=$(jqr '.rate_limits.five_hour.used_percentage // empty | floor')
            [[ -n $limit ]] && out+=" · 5h $limit%"
            echo "$out"
          ''
        );
      };

      tui = "fullscreen";
      theme = "auto";
      agentPushNotifEnabled = true;
    };
  };
}
