{ pkgs, pkgs-unstable, ... }:
{
  # Tools Claude reaches for in its own shell; without them it falls back to
  # clumsier python/sed one-liners.
  home.packages = with pkgs; [
    jq
    fd
    yq-go
    # Runs a heavy command (flake evaluation, builds) at the back of the CPU
    # and IO queue in its own cgroup. Over the memory cap it gets OOM-killed
    # instead of pushing the desktop into swap. `nix flake check` peaks
    # around 3.5G.
    (writeShellScriptBin "lowprio" ''
      exec systemd-run --user --scope --quiet \
        -p MemoryMax=6G -p MemorySwapMax=0 -p CPUWeight=20 -p IOWeight=20 \
        -- nice -n 19 "$@"
    '')
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
      - Terraform / OpenTofu: use `tofu` where the lock file pins
        `registry.opentofu.org` (all work repos), `terraform` otherwise. `fmt` and
        `validate` freely; never `apply` or `destroy` without asking.
      - Kubernetes / Flux: read-only (`get`, `describe`, `logs`, `flux get`) unless
        told otherwise. Never `flux reconcile`, `kubectl apply/delete/edit` on your own.
      - Work GitLab is self-hosted at gitlab.frhc.one; use `glab` for MRs, pipelines
        and issues. Open MRs with the `gitlab-mr` skill: every MR links its Asana task.
      - Asana tasks are written in Russian (title and description), whatever
        language the conversation is in. Technical names (GitLab, Terraform,
        service names, MR numbers) stay as they are.
    '';

    # Language servers give Claude go-to-definition and diagnostics instead of
    # grepping. Bundled into a plugin passed via the wrapper's --plugin-dir.
    lspServers = {
      nix = {
        command = "${pkgs.nixd}/bin/nixd";
        extensionToLanguage.".nix" = "nix";
      };
      # OpenTofu's fork of terraform-ls: work repos are OpenTofu, and it also
      # serves plain Terraform code.
      opentofu = {
        command = "${pkgs.tofu-ls}/bin/tofu-ls";
        args = [ "serve" ];
        extensionToLanguage = {
          ".tf" = "opentofu";
          ".tofu" = "opentofu";
          ".tfvars" = "opentofu-vars";
          ".tofuvars" = "opentofu-vars";
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
      Prefix every evaluation or build (`nix flake check`, `nix build`,
      `nix eval`, `tofu plan`) with `lowprio` so it can't freeze the
      desktop; if one gets OOM-killed under it, report that rather than
      retrying without it.

      Stop at the first failure, fix it, and re-run from that step. Report
      what ran and what passed; never claim success for a check you skipped,
      and say why it was skipped.

      ## Nix flake

      1. `nix fmt -- --ci` (fails if anything needs formatting)
      2. `lowprio nix flake check --no-build` (evaluates every output)
      3. Build each host the change can affect. For a NixOS host:
         `lowprio nix build --no-link .#nixosConfigurations.<host>.config.system.build.toplevel`.
         If the host's system differs from this machine's (e.g. aarch64), only
         evaluate it: `lowprio nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
         Home-manager only: `.#nixosConfigurations.<host>.config.home-manager.users.<user>.home.activationPackage`.
      4. Do not run `nh os switch` or anything that activates a configuration
         unless asked.

      ## Terraform / OpenTofu

      Use `tofu` if `.terraform.lock.hcl` pins providers from
      `registry.opentofu.org` (every work repo does), `terraform` otherwise;
      `<tf>` below is whichever applies. Neither is on PATH globally: use the
      repo's dev shell if it has one, else `nix shell nixpkgs#opentofu`.

      1. `<tf> fmt -check -recursive`
      2. `<tf> init -backend=false` if `.terraform/` is missing, then `<tf> validate`
      3. `lowprio <tf> plan` only when credentials and state access are already
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
      description: Open a merge request on the work GitLab (gitlab.frhc.one) with the Asana task linked in its description, creating the task (in Russian) when there is none. Use whenever asked to create, open or submit an MR / merge request / PR in a work repo.
      ---

      # GitLab merge request with an Asana link

      ## 1. Find the Asana task, or create one. Never invent or guess a URL.

      In order, stop at the first hit:
      1. A task URL or ID the user gave in this conversation.
      2. An `app.asana.com` URL in the branch's commit messages
         (`git log <default>..HEAD`), or in an earlier MR from this branch.
      3. A task ID in the branch name (e.g. `DEVOPSSUP-6951`): look it up with
         the Asana tools if they're available.
      4. If the Asana tools are available, search the incomplete tasks assigned
         to me for one matching the change, and ask me to confirm the match.
      5. Still nothing (no candidates, or I said none of them fits): create the
         task as below.
      6. Only if the Asana tools aren't available: ask me for the task. If I say
         there is none, open the MR without one.

      ### Creating the task

      Write it in **Russian**, like the rest of my tasks; technical names
      (GitLab, Terraform, service and repo names) stay as they are.

      - Name: `<область>: <что сделано>`, sentence case, no trailing period,
        e.g. `Бэкап PostgreSQL: не выдавать упавший pg_dump за успешный` or
        `CI devops: заменить переменные ручного запуска на pipeline inputs`.
      - Notes: two or three plain sentences on what the change does and why —
        the MR description's prose, in Russian. No headings.
      - Assignee: `me`.
      - Project: **Travel Infrastructure Tasks** (`1210670586512180`), section
        **В работе** (`1210670771566690`), the MR being open. If the change
        answers someone else's request (a developer asking for a variable, an
        access, a CI fix in their repo), use **Devops Support**
        (`1210945785187568`) instead and ask me which section.

      Tell me the task's name and URL when it's created.

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
      of opening a second one. If step 1 created the task, add the MR URL to it
      as a comment.

      ## 4. Add dependencies on MRs that must merge first

      Use GitLab's merge request dependencies whenever ordering matters, so
      the MR can't be merged before what it relies on. Treat this as the
      default whenever any of these is true, not as an extra:

      - **Stacked branch**: the branch is built on another branch with an
        open MR. Check my open MRs in this project
        (`glab mr list --author=@me`) and, for each source branch, whether
        `git merge-base --is-ancestor origin/<branch> HEAD` holds while that
        branch isn't merged into the default. Target that parent branch
        (`--target-branch <parent>`) so the diff shows only this change, and
        add the parent MR as a dependency.
      - **Cross-repo order**: the change uses something another open MR
        introduces: a Terraform module version, a CI template or component,
        a Helm chart, a Flux/infra change an app needs, a new variable or
        secret. Search my open MRs (`glab api "merge_requests?scope=created_by_me&state=opened"`)
        for it, or ask me which MR it is when I mention one.
      - I say "after !123", "once X is merged", "depends on", or the work was
        split into several MRs meant to land in sequence: each MR depends on
        the previous one.

      If one of these looks likely but you can't find the blocking MR, ask me
      rather than skipping it.

      Add the dependency through the API (glab has no flag for it). `:id` is
      the project path URL-encoded or its numeric ID, and
      `blocking_merge_request_id` is the blocking MR's **global** `id` (not
      its `iid`), taken from `glab api projects/<blocking project>/merge_requests/<iid>`:

      ```sh
      glab api --method POST \
        "projects/:id/merge_requests/<iid>/blocks" \
        -f blocking_merge_request_id=<global id>
      ```

      Then read it back with `glab api "projects/:id/merge_requests/<iid>/blocks"`
      and check that the blocking MR's `iid` and `web_url` are the ones you
      meant. If they're wrong, delete the entry
      (`--method DELETE ".../blocks/<block id>"`) and retry with the other ID
      form. Don't add one that's already listed.

      When a blocking MR is closed without merging, it still blocks: ask me
      whether to remove the dependency. When a stacked parent merges, GitLab
      retargets this MR to the parent's target; since parents are squashed,
      rebase onto the default branch
      (`git rebase --onto origin/<default> <old parent tip>`) and force-push
      with `--force-with-lease`, after asking.

      Finish by printing the MR URL and any dependencies you added.
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
      # Default model for every new session. `[1m]` picks the
      # 1M-context Opus 5; it counts 5x against rate limits, plain "opus" is the
      # regular 200k one.
      model = "opus[1m]";
      permissions = {
        # Start in Auto rather than Claude Code's own default of "ask each
        # time": no routine permission prompts, a reviewer model screens
        # actions instead.
        defaultMode = "auto";
        # Hard stops that hold regardless of what the auto-mode reviewer thinks.
        deny = [
          "Read(~/.config/sops/age/**)"
          "Read(~/.ssh/id_*)"
          "Bash(terraform apply:*)"
          "Bash(terraform destroy:*)"
          "Bash(tofu apply:*)"
          "Bash(tofu destroy:*)"
        ];
      };
      # No attribution in commits or PRs/MRs it writes: no "Co-Authored-By:
      # Claude" trailer or "Generated with Claude Code" footer (empty strings),
      # and no claude.ai session link (the Claude-Session trailer and PR-body
      # link). Replaces the deprecated includeCoAuthoredBy = false.
      attribution = {
        commit = "";
        pr = "";
        sessionUrl = false;
      };

      # No "How is Claude doing this session?" rating prompt.
      env.CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";

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

      # No "while you were away" session recap after 5+ idle minutes.
      awaySummaryEnabled = false;
      tui = "fullscreen";
      theme = "auto";
      agentPushNotifEnabled = true;
    };
  };
}
