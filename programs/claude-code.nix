{
  lib,
  pkgs,
  pkgs-unstable,
  me,
  ...
}:
let
  # A permission rule for a command and the forms it hides behind. Claude
  # Code strips sudo/env/nice/timeout before matching, but not our own
  # `lowprio` wrapper, and a `* ` after the tool catches global flags put
  # before the subcommand (`kubectl -n x apply`, `sops --input-type yaml -d`).
  bashRules =
    tool: verbs:
    lib.concatMap (v: [
      "Bash(${tool} ${v} *)"
      "Bash(${tool} * ${v} *)"
      "Bash(lowprio ${tool} ${v} *)"
      "Bash(lowprio ${tool} * ${v} *)"
    ]) verbs;
in
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
    # Lints an MR description (GitLab-flavoured Markdown) from stdin or files
    # before it's posted. No first-line heading rule: descriptions are prose;
    # bare URLs are fine (GitLab autolinks them, and the Asana link is one);
    # lines wrap at 80, but a lone URL may run past it.
    (writeShellScriptBin "mr-lint" ''
      exec ${lib.getExe markdownlint-cli2} \
        --config ${
          writeText "mr.markdownlint.json" (
            builtins.toJSON {
              default = true;
              MD041 = false;
              MD034 = false;
              MD013 = {
                line_length = 80;
                code_blocks = false;
              };
            }
          )
        } \
        "''${@:--}"
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
      - No python on PATH: edit files with the Edit tool, wrangle JSON/YAML with
        `jq` / `yq`. For a one-off script, `nix run nixpkgs#python3`.
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
      - Work Asana tasks are the memory shared between sessions: in a work repo,
        use the `asana-task` skill to load the task before starting and to
        record progress in it. `asana-sweep` closes tasks whose MRs are all merged.
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
      2. `lowprio nix flake check --no-build --all-systems` (evaluates every
         output, including other architectures' checks; nothing is built)
      3. Build the outputs the change affects for this machine's system:
         `lowprio nix build --no-link .#<output>`.
         In ~/Documents/flake (the NixOS config) that means work-laptop:
         `.#nixosConfigurations.work-laptop.config.system.build.toplevel`
         (home-manager only: `.#nixosConfigurations.work-laptop.config.home-manager.users.${me.user}.home.activationPackage`).
         Never build home-server or drake: step 2 already evaluates them,
         and deploy-rs builds both on their own hosts. Say they were
         evaluated but not built, and ask if a real build seems necessary.
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
      - Description: prose explaining why the change is needed and anything
        a reviewer can't see in the diff. No headings, no "Summary"/"Test plan"
        boilerplate. Skip the prose entirely for trivial changes (fmt, version
        bumps).
      - It is GitLab-flavoured Markdown, rendered, not plain text:
        - Wrap at ~72 columns; single newlines join into one paragraph, so
          separate paragraphs with a blank line and write lists as `- ` items
          with a blank line before them.
        - Anything code goes in backticks: file and directory paths
          (`archive/imports.tf`), branch names, commands, resource addresses,
          settings and values (`archived = true`, `destroy = false`),
          variables, env names, package versions. Prose words (GitLab,
          Terraform, service names used as names) stay plain.
        - Never backtick a GitLab reference: code spans aren't linked.
      - GitLab references:
        - Same project: `!19` (MR), `#19` (issue), a commit SHA, bare.
        - Another project: the full path, `aviata/devops/backstage!19` or
          `aviata/devops/backstage#19`, never a bare `!19` or
          `backstage !19`: GitLab links a bare `!19` to *this* project's
          MR 19, and a space breaks the reference. A commit in another
          project is `aviata/devops/backstage@<sha>`.
        - Before writing one, check it resolves:
          `glab api "projects/<path url-encoded>/merge_requests/<iid>"`
          returns the MR you mean (`web_url`, `title`).
      - The Asana URL goes alone on the **last line** of the description, after
        a blank line. If there's no prose, the URL is the whole description.

      ## 3. Create it

      Commit only what I asked for and push with `git push -u origin HEAD`.

      Write the description to a file in the scratchpad and lint it with
      `mr-lint <file>`. Fix every finding and re-run until it's clean; then
      reread it for code that isn't in backticks and for cross-project
      references without a full path, which the linter can't see. Then:

      ```sh
      glab mr create \
        --title "<title>" \
        --description "$(cat <file>)" \
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
      of opening a second one. Then add the MR URL to the task as a comment
      `MR: <url>` (whether step 1 found the task or created it), unless the
      task's notes or comments already contain it: `asana-sweep` finds a
      task's MRs through these links.

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

    skills.asana-task = ''
      ---
      name: asana-task
      description: Use the work Asana task as memory that carries over between sessions. Load its context before starting work in a work repo (gitlab.frhc.one), and record progress, decisions and next steps in it while working. Use at the start of any work-repo task, when I say "continue", "where were we" or name a task, and before finishing a turn that moved the work forward.
      ---

      # Asana task as memory between sessions

      A new session knows nothing about earlier ones. The Asana task is where
      that knowledge lives, so the next session (or a teammate) can pick up
      from it. Everything written to Asana is in **Russian**, technical names
      unchanged.

      ## 1. Load the task before starting work

      Find it in the same order as step 1 of the `gitlab-mr` skill: a URL or
      ID I gave you, then an `app.asana.com` URL in the branch's commits or
      its MR description, then a match among my incomplete tasks in
      Travel Infrastructure Tasks (`1210670586512180`) and Devops Support
      (`1210945785187568`), confirmed with me. The SessionStart hook
      may already have put the branch's Asana URLs in context.

      Read it with `get_task` (`comment_limit` 20 or more) and, if it is a
      subtask, its parent as well: the parent's notes usually hold the
      background and the subtasks hold the numbered plan. Before doing
      anything, tell me in two or three lines where things stand, based on
      the notes, the latest comments and which subtasks are done.

      No task, and the work is more than a quick question? Offer to create
      one (as in `gitlab-mr`) rather than creating it unasked.

      ## 2. Keep it up to date

      Write when something happens that the next session would need to know,
      not after every step:

      - **Comment** (`add_comment`) for things that happened, short and dated
        by Asana itself: an MR opened or merged (`MR: <url>`), an apply or
        deploy done, something found while debugging, a blocker or a question
        to someone, a decision and why it was made.
      - **Notes** (`update_tasks`) hold the current state: context, the
        current approach, what is left. Edit them when they stop being true
        and keep what is already there; don't append a running log to them.
      - **Subtasks** for a plan of several steps that will take more than one
        session: numbered names (`1. …`, `2. …`), the same way my existing
        tasks do it. Complete each one as it is finished.

      Before ending a turn in which the work moved forward and nothing has
      been recorded yet, add one comment: what was done and what comes next.
      Say in your reply what you wrote to Asana.

      Never put secrets, tokens, passwords or their values in Asana, not even
      in passing; name the secret and where it lives instead.

      ## 3. Status

      - Started work: move it to **В работе** if it is in Открыт or Backlog.
      - Every MR is merged and nothing else is left: complete it, as in the
        `asana-sweep` skill. Ask first if something remains to be applied or
        checked after merge; in Travel Infrastructure Tasks, a task waiting
        on that check goes to **Тестируется**.
      - Last open subtask completed: say so, and offer to complete the parent.
    '';

    skills.asana-sweep = ''
      ---
      name: asana-sweep
      description: Find my open work Asana tasks whose MRs are all merged (or which are otherwise finished) and close them, so no task stays open after the work is done. Use when I ask to clean up, sweep, sync or check the status of my Asana tasks or MRs.
      ---

      # Close Asana tasks whose work is finished

      ## 1. Collect the tasks

      `search_tasks` with `assignee_any=me`, `completed=false`,
      `projects_any=1210670586512180,1210945785187568` (Travel
      Infrastructure Tasks, Devops Support), `limit=100`; repeat with
      `is_subtask=true` and no project filter, since subtasks usually aren't
      in a project. Ask for `opt_fields=name,notes,parent.name,memberships.section.name,memberships.project.name,modified_at,permalink_url,num_subtasks`.

      Comments: one `get_task_stories` call with all the task IDs (up to 50
      per call) and `resource_subtype=comment_added`, `limit=50`.

      ## 2. Find each task's MRs

      - Every `gitlab.frhc.one/<path>/-/merge_requests/<iid>` URL in the
        notes and comments.
      - MRs whose description links the task: run
        `glab api "merge_requests?scope=created_by_me&state=all&search=<task gid>&in=description&per_page=100"`
        once per task, or once in all for an `app.asana.com` search if
        that's faster, and match on the task gid.

      For each MR, its state:
      `glab api "projects/<path url-encoded>/merge_requests/<iid>"` → `state`
      (`merged`, `opened`, `closed`), `merged_at`, `title`.

      ## 3. Classify

      - **Done**: at least one MR, every MR `merged` or deliberately `closed`
        in favour of a merged one, and the latest comments don't mention
        anything left (an apply, a deploy, a check, a next step).
      - **Done, but something is left**: all MRs merged, yet the notes or the
        last comments mention remaining work. Don't close; list what is left.
      - **Parent**: every subtask completed (`get_task` shows subtasks;
        check each with `completed`) → done, regardless of its own MRs.
      - **In progress**: an MR still `opened`. Note if it is a draft, has a
        failing pipeline or has had no activity for 14 days.
      - **Stuck**: an MR `closed` without being merged and no merged
        replacement, or no MRs and no activity (`modified_at`) for 14+ days.
      - Tasks created by someone else in Devops Support with no MR: leave
        alone, just list them.

      ## 4. Report, then act on one confirmation

      Show a table, grouped by class: task (name + link), MRs with state,
      and what you propose. Then ask once: "Close the N done tasks?" (I can
      exclude some). On yes, for each one:

      1. Add a comment: `Все MR смёрджены: <MR URLs>. Задача закрыта.`
         (adapted for parents: `Все подзадачи выполнены.`).
      2. Move it to the project's **Закрыт** section (Travel Infrastructure
         Tasks `1210670771566696`, Devops Support `1210941654277294`), if it
         is in one of those projects.
      3. Complete it (`update_tasks`, `completed=true`).

      Complete subtasks before their parent. Nothing gets completed without
      that confirmation, and stuck tasks are only reported. Finish with a list
      of what was closed and what still needs me.
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
      # Default model for every new session. The alias follows the latest
      # Opus (5.5 at the time of writing), whose context is natively 1M, so
      # no `[1m]` suffix is needed.
      model = "opus";
      # Most work here changes real systems (Terraform, Flux, NixOS), where a
      # shallow answer costs more than the extra thinking. Applies to every
      # model, not just Opus; `/effort` lasts only for the session. For a
      # hard session: `CLAUDE_CODE_EFFORT_LEVEL=xhigh claude`.
      effortLevel = "high";
      permissions = {
        # Start in Auto rather than Claude Code's own default of "ask each
        # time": no routine permission prompts, a reviewer model screens
        # actions instead.
        defaultMode = "auto";
        # Hard stops that hold regardless of what the auto-mode reviewer
        # thinks, or what Claude is told in chat. A backstop, not a sandbox:
        # prefix matching can't see through every wrapper.
        deny = [
          "Read(~/.config/sops/age/**)"
          "Read(~/.ssh/id_*)"
          # Secrets sops-nix has already decrypted (home-manager and system).
          # `//` makes the path absolute; a single `/` is relative to this file.
          "Read(~/.config/sops-nix/**)"
          "Read(//run/user/*/secrets.d/**)"
          "Read(//run/secrets/**)"
          "Read(//run/secrets.d/**)"
          # Never decrypt: sops has too many ways in (-d after any flag,
          # exec-env, exec-file, edit, or a bare file with EDITOR=cat), so
          # nothing of sops runs. Ask me for `updatekeys` or an encrypt.
          "Bash(sops *)"
          "Bash(lowprio sops *)"
          "Bash(nix shell * -c sops *)"
          "Bash(nix run nixpkgs#sops *)"
          "Bash(nixos-rebuild *)"
          "Bash(lowprio nixos-rebuild *)"
        ]
        ++ bashRules "age" [
          "-d"
          "--decrypt"
        ]
        ++ bashRules "terraform" [
          "apply"
          "destroy"
        ]
        ++ bashRules "tofu" [
          "apply"
          "destroy"
        ];
        # Writes to a cluster always prompt, even in auto mode, so "unless
        # told otherwise" in CLAUDE.md still works: I approve when I asked.
        ask =
          bashRules "kubectl" [
            "apply"
            "create"
            "replace"
            "patch"
            "edit"
            "delete"
            "scale"
            "autoscale"
            "rollout restart"
            "rollout undo"
            "rollout pause"
            "rollout resume"
            "set"
            "label"
            "annotate"
            "taint"
            "cordon"
            "uncordon"
            "drain"
            "expose"
            "run"
            "exec"
            "debug"
            "cp"
          ]
          ++ bashRules "flux" [
            "reconcile"
            "suspend"
            "resume"
            "create"
            "delete"
            "bootstrap"
            "install"
            "uninstall"
            "push"
            "tag"
          ]
          ++ bashRules "helm" [
            "install"
            "upgrade"
            "uninstall"
            "rollback"
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

      # In a work repo, put the branch and the Asana tasks its commits link
      # into context, so the session starts from the task (asana-task skill)
      # instead of from nothing. Silent everywhere else.
      hooks.SessionStart = [
        {
          matcher = "startup|resume|clear|compact";
          hooks = [
            {
              type = "command";
              command = toString (
                pkgs.writeShellScript "claude-asana-context" ''
                  git() { ${pkgs.git}/bin/git "$@"; }
                  git remote get-url origin 2>/dev/null | grep -q 'gitlab\.frhc\.one' || exit 0
                  branch=$(git branch --show-current 2>/dev/null)
                  base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
                  urls=""
                  if [[ -n $base && -n $branch && $branch != "''${base#origin/}" ]]; then
                    urls=$(git log --format=%B "$base..HEAD" 2>/dev/null |
                      grep -oE 'https://app\.asana\.com/[A-Za-z0-9/_-]*[0-9]{10,}' | sort -u)
                  fi
                  echo "Work repo (gitlab.frhc.one), branch ''${branch:-detached}."
                  if [[ -n $urls ]]; then
                    echo "Asana tasks linked from this branch's commits:"
                    echo "$urls"
                  fi
                  echo "Before starting work here, load its Asana task with the asana-task skill, and record progress in it."
                  exit 0
                ''
              );
            }
          ];
        }
      ];

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
                  if [[ $f == *.nix && -f $f ]]; then
                    ${pkgs.nixfmt}/bin/nixfmt "$f" || exit 2
                  fi
                  exit 0
                ''
              );
            }
            {
              # Same for Terraform / OpenTofu, so `fmt -check` doesn't fail on
              # Claude's own edits. tofu's formatter matches terraform's. A file
              # that doesn't parse exits 2, which hands tofu's error back to
              # Claude instead of swallowing it.
              type = "command";
              command = toString (
                pkgs.writeShellScript "claude-tofufmt" ''
                  f=$(${pkgs.jq}/bin/jq -r '.tool_input.file_path // empty')
                  if [[ $f =~ \.(tf|tfvars|tofu|tftest\.hcl|tofutest\.hcl)$ && -f $f ]]; then
                    ${pkgs.opentofu}/bin/tofu fmt -no-color "$f" >/dev/null || exit 2
                  fi
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
