# Install

The skill is the folder `skills/code-review/`. Every host below loads that same folder; the installers only put it in the right place.

## Quick start

```bash
git clone https://github.com/ohmaseclaro/code-review-skill && cd code-review-skill
./install.sh --dry-run          # show the plan for the hosts found on this machine, write nothing
./install.sh                    # global install for detected hosts, symlinks, asks Y/n
./install.sh --scope project    # install into the current repository instead
```

Without a clone (copies, never symlinks):

```bash
curl -fsSL https://raw.githubusercontent.com/ohmaseclaro/code-review-skill/main/install.sh | bash -s -- --host all --yes
```

The piped form makes one request, to `$REPO_URL/archive/refs/heads/$REF.tar.gz` over https only. It rejects archives with absolute or `..` paths before extracting and runs `--check` on the result. Read the script first if you prefer.

## Hosts and targets

`--host` takes `claude`, `cline`, `agents`, `detected` (default), `all` (`claude,cline,agents`), or any name in the table below. Hosts that read the shared `agents` folder are installed there once, so a host never sees the skill twice.

| Flag | Writes to (global) | Writes to (`--scope project`) |
| --- | --- | --- |
| `claude` | `~/.claude/skills/code-review` | `<repo>/.claude/skills/code-review` |
| `cline` | `~/.cline/skills/code-review` | `<repo>/.cline/skills/code-review` |
| `agents`, `codex`, `cursor`, `gemini`, `copilot`, `opencode`, `windsurf`, `amp`, `roo`, `kilo`, `goose`, `junie`, `zed` | `~/.agents/skills/code-review` | `<repo>/.agents/skills/code-review` |
| `--path DIR` | `DIR/code-review` | same |

Adapters for hosts or modes without skills (project scope only; each also installs the skill into `.agents/skills`):

| Flag | Writes | Notes |
| --- | --- | --- |
| `agents-md` | marked block in `AGENTS.md` | pointer to `.agents/skills/code-review/SKILL.md` |
| `copilot-instructions` | marked block in `.github/copilot-instructions.md` | pointer only |
| `cursor-rule` | `.cursor/rules/code-review.mdc` | whole file, `alwaysApply: false` |
| `aider` | marked block in `CONVENTIONS.md` | Aider does not load it by itself; the installer prints the `read:` line for `.aider.conf.yml` and does not edit that file |

A marked block sits between `<!-- BEGIN code-review-skill ... -->` and `<!-- END code-review-skill -->`. Uninstall removes only that block, and the rest of the file comes back byte for byte (a file the installer created is deleted when nothing else is left in it).

## Flags and behaviour

| Flag | Meaning |
| --- | --- |
| `--scope global\|project` | home directory (default) or the current git repo, else the current directory |
| `--mode symlink\|copy` | symlink from a clone (default; `git pull` updates it), copy when piped |
| `--update` | replace a copy this installer made when it is outdated |
| `--uninstall` | remove only what this installer made |
| `--list` | state of every skill target, both scopes |
| `--check` | validate the package: frontmatter name matches the folder, every `references/` file named in SKILL.md exists, scripts parse, JSON parses, plugin has no hooks |
| `--dry-run` | print the plan, write nothing |
| `--yes` | skip the Y/n prompt. With no terminal and no `--yes` it exits 2 |
| `--force` | back up and replace a different item of the same name; also allows running as root |

The plan is always printed before anything is written. A different skill, symlink or file with the same name is never overwritten without `--force`; with it, the old item is moved to `~/.code-review-skill-backups/<timestamp>/`. Re-running is a no-op. Uninstall leaves anything it did not create, and removes the empty `.agents` folder and, in a project, empty `.claude` or `.cline` folders it leaves behind.

Exit codes: 0 ok, 1 runtime error, 2 usage error or nothing detected or no terminal to confirm on, 3 collision, 4 `--check` failed, 5 refused as root, 6 download or archive problem, 7 declined at the prompt.

Windows: `install.ps1` (copy by default, symlink needs privileges). It is untested on Windows, covers only `claude`, `cline`, `agents` and `--path`, and has no adapters or piped mode.

## Claude Code plugin

```text
/plugin marketplace add ohmaseclaro/code-review-skill
/plugin install code-review-skill@code-review-skill
```

The plugin is this repository root (`.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/`). It declares no hooks. Plugin skills are namespaced by the plugin name. Checked here with `claude plugin validate` and a local `marketplace add` and `install` in a throwaway config directory; not tested against a GitHub remote because nothing is published.

## Other installers

`npx skills add <owner>/<repo> -g -a <agent>` (the `skills` CLI from Vercel Labs) installs Agent Skills into many hosts, symlinking from one canonical copy unless `--copy` is given. It exists and is documented, but it has not been tried against this repository, so treat that route as untested.

## Verified host facts

Checked 2026-11-25 against the official pages listed. "Reads" means what the page itself states. Where a page was only seen through a search excerpt it says so.

| Host | Mechanism | Global path | Project path | Caveats | Status and source |
| --- | --- | --- | --- | --- | --- |
| Claude Code | Skills; also plugins | `~/.claude/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` | Follows symlinks. Docs do not mention `.agents/skills`, so it is not relied on. Plugin install: `/plugin marketplace add`, `/plugin install name@marketplace` | VERIFIED. [skills](https://code.claude.com/docs/en/skills), [marketplaces](https://code.claude.com/docs/en/plugin-marketplaces), [plugin reference](https://code.claude.com/docs/en/plugins-reference) |
| Cursor | Skills; rules; AGENTS.md | `~/.cursor/skills`, `~/.agents/skills` | `.cursor/skills`, `.agents/skills` | Also loads `.claude/skills` and `.codex/skills`. Rules are `.cursor/rules/*.mdc` with `description`, `globs`, `alwaysApply`; `AGENTS.md` supported. User-level skills are not synced to cloud agents. Symlinks not documented | VERIFIED. [skills](https://cursor.com/docs/skills), [rules](https://cursor.com/docs/rules) |
| Codex CLI | Skills | `~/.agents/skills` (also `/etc/codex/skills`) | `.agents/skills` in the working directory and every parent up to the repo root | Follows symlinks. `~/.codex/skills` is not on the current page. AGENTS.md is not covered by the page I read | Skills VERIFIED, AGENTS.md UNVERIFIED. [build skills](https://learn.chatgpt.com/docs/build-skills) (redirect target of developers.openai.com/codex/skills) |
| Gemini CLI | Skills | `~/.gemini/skills`, alias `~/.agents/skills` | `.gemini/skills`, alias `.agents/skills` | The page carries a banner saying Gemini CLI was replaced by Antigravity CLI on 2026-06-18, so it may be stale. `.agents` wins within a tier. `GEMINI.md` import and Antigravity paths not checked | Skills VERIFIED, GEMINI.md and Antigravity UNVERIFIED. [skills](https://geminicli.com/docs/cli/skills/) |
| GitHub Copilot | Skills; instruction files | `~/.copilot/skills`, `~/.agents/skills` | `.github/skills`, `.claude/skills`, `.agents/skills` | Same folders for CLI, cloud agent and agent mode in VS Code; one Microsoft page still says stable VS Code support is coming. Instructions: `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md` (`applyTo`), `AGENTS.md` | VERIFIED. [add skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills), [repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions) |
| OpenCode | Skills | `~/.config/opencode/skills`, plus `~/.claude/skills`, `~/.agents/skills` | `.opencode/skills`, plus `.claude/skills`, `.agents/skills`, searched up to the project root | Later source wins on duplicate names | VERIFIED. [skills](https://opencode.ai/docs/skills) |
| Windsurf (now Devin Desktop) | Skills | `~/.config/devin/skills`, also `~/.agents/skills` | `.devin/skills`, also `.agents/skills`, legacy `.windsurf/skills` | Docs moved to docs.devin.ai after a rebrand; an earlier Windsurf page listed `~/.codeium/windsurf/skills` | VERIFIED for `.agents`. [skills](https://docs.devin.ai/desktop/cascade/skills) |
| Amp | Skills | `~/.config/agents/skills`, `~/.agents/skills`, `~/.config/amp/skills` | `.agents/skills`, `.claude/skills` | First skill with a given `name` wins | VERIFIED. [manual](https://ampcode.com/manual/agent-skills) |
| Cline | Skills | `~/.cline/skills` | `.cline/skills`, `.clinerules/skills`, `.claude/skills` | Does not read `.agents/skills`, hence its own target. A global skill beats a project skill of the same name. `name` must equal the folder name | VERIFIED. [skills](https://docs.cline.bot/customization/skills) |
| Roo Code | Skills | `~/.roo/skills`, `~/.agents/skills` | `.roo/skills`, `.agents/skills` | Follows symlinks. Docs page last updated 2026-05-15; one third-party site claims the project shut down that day, which I could not confirm | VERIFIED, product status UNVERIFIED. [skills](https://roocodeinc.github.io/Roo-Code/features/skills) |
| Kilo Code | Skills | `~/.kilo/skills`, also `~/.agents/skills` | `.kilo/skills`, also `.agents/skills` | `.agents` is loaded by default. The older `.kilocode/skills` seen in third-party posts is not confirmed and not used | VERIFIED. [skills](https://kilo.ai/docs/customize/skills) |
| Goose | Skills | `~/.agents/skills` | `.agents/skills` | Also discovers `.goose/skills` and `.claude/skills`; no precedence stated | VERIFIED. [using skills](https://goose-docs.ai/docs/guides/context-engineering/using-skills) |
| JetBrains Junie | Skills; guidelines | `~/.junie/skills`, `~/.agents/skills`; `~/.junie/AGENTS.md` | `.junie/skills`, `.agents/skills` (trusted project); `.junie/AGENTS.md` or `AGENTS.md` | Project beats user on duplicate names | VERIFIED. [agent skills](https://junie.jetbrains.com/docs/agent-skills.html), [guidelines](https://junie.jetbrains.com/docs/guidelines-and-memory.html) |
| Zed | Skills; AGENTS.md; rules | `~/.agents/skills`; `~/.config/zed/AGENTS.md` | `<worktree>/.agents/skills`; first of `.rules`, `.cursorrules`, `.windsurfrules`, `.clinerules`, `.github/copilot-instructions.md`, `AGENT.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Skills apply to the Zed agent only; project skills load only from trusted worktrees | VERIFIED. [skills](https://zed.dev/docs/ai/skills), [instructions](https://zed.dev/docs/ai/instructions) |
| Aider | Conventions file, no skills | none | `CONVENTIONS.md` | Not auto-loaded: use `aider --read CONVENTIONS.md` or `read: CONVENTIONS.md` in `.aider.conf.yml` | VERIFIED. [conventions](https://aider.chat/docs/usage/conventions.html) |
| Cross-agent convention | `.agents/skills` | `~/.agents/skills` | `.agents/skills` | A convention for sharing skills across clients, not a guarantee any one host reads it; see rows above | VERIFIED. [client implementation guide](https://agentskills.io/client-implementation/adding-skills-support) |
| `npx skills` | Installer CLI | `-g` | default | Symlink by default, `--copy` available; not tried here | Exists, VERIFIED from its [README](https://github.com/vercel-labs/skills); use with this repo UNVERIFIED |

No install target is generated for anything marked UNVERIFIED: Codex `AGENTS.md`, Gemini `GEMINI.md`, and Antigravity CLI.
