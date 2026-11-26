#!/usr/bin/env bash
# install.sh: install the code-review agent skill into AI coding agent hosts.
# Bash 3.2+, macOS and Linux, coreutils only. See INSTALL.md for the host table.
#
# From a clone:   ./install.sh [flags]
# Piped:          curl -fsSL <raw url>/install.sh | bash -s -- --host all --yes
#
# Exit codes:
#   0 ok (including nothing to do and --dry-run)
#   1 runtime error
#   2 usage error, or no hosts detected, or confirmation needed but no terminal (pass --yes)
#   3 collision: a different skill or file is in the way (re-run with --force to back it up)
#   4 --check found a problem with the package
#   5 refused to run as root (pass --force)
#   6 download or tarball problem
#   7 declined at the prompt

set -eu

REPO_URL="${REPO_URL:-https://github.com/ohmaseclaro/code-review-skill}"
REF="${REF:-main}"
SKILL_NAME="code-review"
MARKER_FILE=".code-review-skill.installed"
BEGIN_TAG="<!-- BEGIN code-review-skill"
END_TAG="<!-- END code-review-skill -->"
TAB="$(printf '\t')"

HOST=""
SCOPE="global"
MODE=""
ACTION="install"
DRY=0
YES=0
FORCE=0
UPDATE=0
CUSTOM_PATH=""
TMPDIR_DL=""
SRC=""
PIPED=0

die() { printf 'install.sh: %s\n' "$2" >&2; exit "$1"; }
say() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage: install.sh [flags]

  --host LIST        comma list of hosts, or "all" (claude, cline, agents), or "detected" (default)
  --scope S          global (default) or project (the current git repo, else the current directory)
  --mode M           symlink (default from a clone) or copy (default when piped)
  --path DIR         also install into DIR/code-review, for any Agent Skills compatible folder
  --update           replace an outdated copy that this installer made
  --uninstall        remove what this installer made, nothing else
  --list             show install state for every target, both scopes
  --check            validate package integrity and exit
  --dry-run          print the plan and write nothing
  --yes              do not ask for confirmation
  --force            back up and replace a different existing skill; allow running as root
  -h, --help         this text

Skill hosts: claude, cline, agents. Host names that read the shared agents folder
(codex cursor gemini copilot opencode windsurf amp roo kilo goose junie zed) map to "agents".
Adapters (project scope only, for hosts without skills): agents-md, copilot-instructions,
cursor-rule, aider.

Environment: REPO_URL (default placeholder repo), REF (default main). A file:// REPO_URL
pointing at a .tar.gz is accepted for testing.
EOF
}

# ---- args ----------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --host) [ $# -ge 2 ] || die 2 "--host needs a value"; HOST="$2"; shift 2 ;;
    --scope) [ $# -ge 2 ] || die 2 "--scope needs a value"; SCOPE="$2"; shift 2 ;;
    --mode) [ $# -ge 2 ] || die 2 "--mode needs a value"; MODE="$2"; shift 2 ;;
    --path) [ $# -ge 2 ] || die 2 "--path needs a value"; CUSTOM_PATH="$2"; shift 2 ;;
    --update) UPDATE=1; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --list) ACTION="list"; shift ;;
    --check) ACTION="check"; shift ;;
    --dry-run) DRY=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die 2 "unknown argument: $1" ;;
  esac
done

case "$SCOPE" in global|project) ;; *) die 2 "--scope must be global or project" ;; esac
case "$MODE" in ""|symlink|copy) ;; *) die 2 "--mode must be symlink or copy" ;; esac

if [ "$(id -u)" = "0" ] && [ "$FORCE" -ne 1 ]; then
  die 5 "refusing to run as root; run as your own user, or pass --force"
fi
[ -n "${HOME:-}" ] || die 1 "HOME is not set"

# ---- locate or fetch the source -------------------------------------------
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
  SELF_DIR="$(cd "$(dirname "$SELF")" && pwd -P)"
  PKG_ROOT="$SELF_DIR"
else
  PIPED=1
  PKG_ROOT=""
fi

# shellcheck disable=SC2329  # invoked by trap
cleanup() { [ -z "$TMPDIR_DL" ] || rm -rf "$TMPDIR_DL"; }
trap cleanup EXIT

fetch_source() {
  TMPDIR_DL="$(mktemp -d "${TMPDIR:-/tmp}/code-review-skill.XXXXXX")" || die 6 "mktemp failed"
  tarball="$TMPDIR_DL/src.tar.gz"
  case "$REPO_URL" in
    file://*) cp "${REPO_URL#file://}" "$tarball" || die 6 "cannot read ${REPO_URL}" ;;
    https://*)
      url="${REPO_URL%/}/archive/refs/heads/${REF}.tar.gz"
      say "Downloading $url"
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --proto-redir '=https' --max-filesize 52428800 -o "$tarball" "$url" \
          || die 6 "download failed: $url"
      elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only --max-redirect=3 -O "$tarball" "$url" || die 6 "download failed: $url"
      else
        die 6 "need curl or wget"
      fi ;;
    *) die 6 "REPO_URL must be https:// (or file:// for tests): $REPO_URL" ;;
  esac
  # Refuse archives with absolute paths or parent-directory entries before extracting.
  tar -tzf "$tarball" > "$TMPDIR_DL/list.txt" 2>/dev/null || die 6 "not a valid tar.gz"
  if grep -E '^/|(^|/)\.\.(/|$)' "$TMPDIR_DL/list.txt" >/dev/null; then
    die 6 "archive contains unsafe paths; refusing"
  fi
  mkdir "$TMPDIR_DL/x"
  tar -xzf "$tarball" -C "$TMPDIR_DL/x" || die 6 "extract failed"
  found=""
  for d in "$TMPDIR_DL"/x/*; do
    [ -f "$d/skills/$SKILL_NAME/SKILL.md" ] && { found="$d"; break; }
  done
  [ -n "$found" ] || die 6 "archive does not contain skills/$SKILL_NAME/SKILL.md"
  PKG_ROOT="$(cd "$found" && pwd -P)"
}

need_source=0
case "$ACTION" in install|check) need_source=1 ;; esac
if [ "$need_source" -eq 1 ] && [ "$PIPED" -eq 1 ]; then fetch_source; fi
if [ "$need_source" -eq 1 ]; then
  SRC="$PKG_ROOT/skills/$SKILL_NAME"
  [ -f "$SRC/SKILL.md" ] || die 1 "cannot find $SRC/SKILL.md"
fi

# Mode default: symlink from a clone, copy when piped (the temp checkout is deleted).
if [ -z "$MODE" ]; then
  if [ "$PIPED" -eq 1 ]; then MODE="copy"; else MODE="symlink"; fi
fi
if [ "$PIPED" -eq 1 ] && [ "$MODE" = "symlink" ] && [ "$ACTION" = "install" ]; then
  die 2 "--mode symlink needs a clone; piped installs always copy"
fi

# ---- --check ----------------------------------------------------------------
json_ok() {
  if command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then jq -e . "$1" >/dev/null 2>&1
  else return 0; fi
}

run_check() {
  bad=0
  fail() { say "FAIL: $*"; bad=1; }
  sk="$SRC/SKILL.md"
  head -n1 "$sk" | grep -q '^---$' || fail "SKILL.md has no frontmatter"
  fm="$(sed -n '2,/^---$/p' "$sk")"
  fname="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
  [ "$fname" = "$SKILL_NAME" ] || fail "frontmatter name '$fname' is not '$SKILL_NAME'"
  [ "$(basename "$SRC")" = "$fname" ] || fail "directory name '$(basename "$SRC")' does not match frontmatter name"
  printf '%s\n' "$fm" | grep -q '^description:' || fail "frontmatter has no description"
  refs="$(grep -o 'references/[A-Za-z0-9_.-]*\.md' "$sk" | sort -u)"
  n=0
  for r in $refs; do
    n=$((n + 1))
    [ -f "$SRC/$r" ] || fail "SKILL.md names $r but the file is missing"
  done
  say "references named in SKILL.md: $n"
  for f in "$SRC"/references/*.md; do
    b="references/$(basename "$f")"
    printf '%s\n' "$refs" | grep -qx "$b" || say "note: $b is not named in SKILL.md"
  done
  for s in "$SRC"/scripts/*.sh; do
    [ -f "$s" ] || continue
    [ -x "$s" ] || fail "$(basename "$s") is not executable"
    bash -n "$s" || fail "$(basename "$s") has a syntax error"
  done
  for j in "$SRC"/templates/*.json "$PKG_ROOT/.claude-plugin/plugin.json" "$PKG_ROOT/.claude-plugin/marketplace.json"; do
    [ -f "$j" ] || continue
    json_ok "$j" || fail "invalid JSON: ${j#"$PKG_ROOT"/}"
  done
  if [ -f "$PKG_ROOT/.claude-plugin/plugin.json" ]; then
    pn="$(sed -n 's/^[[:space:]]*"name":[[:space:]]*"\([^"]*\)".*/\1/p' "$PKG_ROOT/.claude-plugin/plugin.json" | head -n1)"
    grep -q "\"name\": *\"$pn\"" "$PKG_ROOT/.claude-plugin/marketplace.json" 2>/dev/null \
      || fail "plugin name '$pn' not found in marketplace.json"
    grep -q '"hooks"' "$PKG_ROOT/.claude-plugin/plugin.json" && fail "plugin.json declares hooks"
    [ ! -d "$PKG_ROOT/hooks" ] || fail "package root has a hooks/ directory"
  fi
  if ! command -v python3 >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
    say "note: no python3 or jq, JSON files were not parsed"
  fi
  if [ "$bad" -eq 0 ]; then say "check: ok"; return 0; fi
  return 4
}

if [ "$ACTION" = "check" ]; then run_check || exit 4; exit 0; fi

# ---- targets ------------------------------------------------------------------
if [ "$SCOPE" = "project" ]; then
  if command -v git >/dev/null 2>&1 && ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    PROJ="$ROOT"
  else
    PROJ="$(pwd -P)"
  fi
  BASE_ROOT="$PROJ"
else
  PROJ=""
  BASE_ROOT="$HOME"
fi

skill_base() { # key -> skills directory for the current scope
  case "$1" in
    claude) printf '%s/.claude/skills' "$BASE_ROOT" ;;
    cline)  printf '%s/.cline/skills' "$BASE_ROOT" ;;
    agents) printf '%s/.agents/skills' "$BASE_ROOT" ;;
  esac
}

host_to_key() {
  case "$1" in
    claude|cline|agents) printf '%s' "$1" ;;
    codex|cursor|gemini|copilot|opencode|windsurf|amp|roo|kilo|goose|junie|zed) printf 'agents' ;;
    agents-md|copilot-instructions|cursor-rule|aider) printf 'adapter:%s' "$1" ;;
    *) return 1 ;;
  esac
}

detected_hosts() {
  out=""
  chk() { # name, path...
    n="$1"; shift
    for p in "$@"; do
      if [ -d "$p" ]; then out="$out $n"; return 0; fi
    done
    return 0
  }
  chk claude "$HOME/.claude" ${PROJ:+"$PROJ/.claude"}
  chk cline "$HOME/.cline" ${PROJ:+"$PROJ/.cline"}
  chk codex "$HOME/.codex" ${PROJ:+"$PROJ/.codex"}
  chk cursor "$HOME/.cursor" ${PROJ:+"$PROJ/.cursor"}
  chk gemini "$HOME/.gemini" ${PROJ:+"$PROJ/.gemini"}
  chk copilot "$HOME/.copilot"
  chk opencode "$HOME/.config/opencode" ${PROJ:+"$PROJ/.opencode"}
  chk windsurf "$HOME/.codeium/windsurf" "$HOME/.config/devin" ${PROJ:+"$PROJ/.windsurf"}
  chk amp "$HOME/.config/amp" "$HOME/.config/agents"
  chk roo "$HOME/.roo" ${PROJ:+"$PROJ/.roo"}
  chk kilo "$HOME/.kilo" ${PROJ:+"$PROJ/.kilo"}
  chk goose "$HOME/.config/goose"
  chk junie "$HOME/.junie" ${PROJ:+"$PROJ/.junie"}
  chk zed "$HOME/.config/zed"
  chk agents "$HOME/.agents" ${PROJ:+"$PROJ/.agents"}
  printf '%s' "$out"
}

# KEYS: space-separated unique list of "claude cline agents adapter:x"
KEYS=""
add_key() { case " $KEYS " in *" $1 "*) ;; *) KEYS="$KEYS $1" ;; esac; }

if [ "$ACTION" = "list" ]; then
  HOST="claude,cline,agents"
elif [ -z "$HOST" ]; then
  HOST="detected"
fi

case "$HOST" in
  all) list="claude cline agents" ;;
  detected) list="$(detected_hosts)" ;;
  *) list="$(printf '%s' "$HOST" | tr ',' ' ')" ;;
esac
for h in $list; do
  k="$(host_to_key "$h")" || die 2 "unknown host: $h (see --help)"
  case "$k" in
    adapter:*) [ "$SCOPE" = "project" ] || die 2 "adapter '$h' is project scope only; add --scope project"
               [ "$ACTION" = "uninstall" ] || add_key agents
               add_key "$k" ;;
    *) add_key "$k" ;;
  esac
done
if [ -z "$KEYS" ] && [ -z "$CUSTOM_PATH" ]; then
  die 2 "no hosts detected; pass --host <name> or --path <dir>"
fi

# True when DST holds exactly SRC plus our marker file (portable: busybox diff has no -x).
same_tree() {
  local rest
  rest="$(diff -rq "$1" "$2" 2>&1 | grep -v -x "Only in $2: $MARKER_FILE" || true)"
  [ -z "$rest" ]
}

# ---- helpers: state of one skill destination ------------------------------------
# state: absent | ours-ok | ours-old | foreign
skill_state() { # dest
  local d="$1" t
  if [ ! -e "$d" ] && [ ! -L "$d" ]; then printf 'absent'; return; fi
  if [ -L "$d" ]; then
    t="$(readlink "$d")"
    case "$t" in
      */skills/$SKILL_NAME) ;;
      *) printf 'foreign'; return ;;
    esac
    if [ -e "$d" ] && [ ! -f "$d/scripts/diff-triage.sh" ]; then printf 'foreign'; return; fi
    if [ "$MODE" = "symlink" ] && [ -n "$SRC" ] && [ "$t" = "$SRC" ]; then printf 'ours-ok'; else printf 'ours-old'; fi
    return
  fi
  if [ -d "$d" ] && [ -f "$d/$MARKER_FILE" ]; then
    if [ "$MODE" = "copy" ] && [ -n "$SRC" ] && same_tree "$SRC" "$d"; then
      printf 'ours-ok'
    elif [ -z "$SRC" ]; then printf 'ours-ok'
    else printf 'ours-old'; fi
    return
  fi
  printf 'foreign'
}

# ---- helpers: managed block in a shared text file -----------------------------------
block_body() { # relpath of SKILL.md from project root
  cat <<EOF
## Code review (adapter)

This block only points at an installed skill. For any request to review code, a diff,
a pull request or a branch, read and follow \`$1\` before answering. Open files under
its \`references/\` folder only when SKILL.md says to.
EOF
}

has_block() { grep -q "^$BEGIN_TAG" "$1" 2>/dev/null; }

file_flag() { # file -> "", nonl, empty, created
  local f="$1"
  if [ ! -e "$f" ]; then printf 'created'; return; fi
  if [ ! -s "$f" ]; then printf 'empty'; return; fi
  if [ -n "$(tail -c1 "$f")" ]; then printf 'nonl'; else printf ''; fi
}

# Writes the file without our block to $2 and echoes the flag recorded in the BEGIN line.
strip_block() { # file out
  local f="$1" out="$2" b e flag cut_from sz
  b="$(grep -n "^$BEGIN_TAG" "$f" | head -n1 | cut -d: -f1)"
  e="$(grep -n "^$END_TAG" "$f" | head -n1 | cut -d: -f1)"
  [ -n "$e" ] && [ "$e" -gt "$b" ] || return 1
  flag="$(sed -n "${b}p" "$f" | sed -n 's/.*code-review-skill\(.*\) (managed.*/\1/p' | tr -d ' ')"
  cut_from="$b"
  case "$flag" in ""|nonl) cut_from=$((b - 1)) ;; esac
  : > "$out"
  [ "$cut_from" -gt 1 ] && head -n $((cut_from - 1)) "$f" >> "$out"
  tail -n +$((e + 1)) "$f" >> "$out"
  if [ "$flag" = "nonl" ] && [ -s "$out" ]; then
    sz="$(wc -c < "$out" | tr -d ' ')"
    dd if="$out" of="$out.n" bs=1 count=$((sz - 1)) 2>/dev/null
    mv "$out.n" "$out"
  fi
  printf '%s' "$flag"
}

make_with_block() { # file rel out [flag] -> writes new content to out
  local f="$1" rel="$2" out="$3" flag
  if [ $# -ge 4 ]; then flag="$4"; else flag="$(file_flag "$f")"; fi
  : > "$out"
  [ -e "$f" ] && cat "$f" >> "$out"
  case "$flag" in
    nonl) printf '\n\n' >> "$out" ;;
    "") printf '\n' >> "$out" ;;
  esac
  {
    if [ -n "$flag" ]; then printf '%s %s (managed by install.sh, do not edit) -->\n' "$BEGIN_TAG" "$flag"
    else printf '%s (managed by install.sh, do not edit) -->\n' "$BEGIN_TAG"; fi
    block_body "$rel"
    printf '%s\n' "$END_TAG"
  } >> "$out"
}

adapter_file() { # adapter -> path relative to project root
  case "$1" in
    agents-md) printf 'AGENTS.md' ;;
    copilot-instructions) printf '.github/copilot-instructions.md' ;;
    cursor-rule) printf '.cursor/rules/code-review.mdc' ;;
    aider) printf 'CONVENTIONS.md' ;;
  esac
}
SKILL_REL=".agents/skills/$SKILL_NAME/SKILL.md"

cursor_rule_text() {
  cat <<EOF
---
description: Code review. Use when asked to review code, a diff, a pull request or a branch.
alwaysApply: false
---
<!-- managed by code-review-skill install.sh (adapter, safe to delete) -->
This rule only points at an installed skill. Read and follow \`$SKILL_REL\` before reviewing,
and open files under its \`references/\` folder only when SKILL.md says to.
EOF
}

# ---- plan -----------------------------------------------------------------------------
PLAN=""        # lines: ACTION<TAB>KIND<TAB>PATH<TAB>NOTE
COLLISIONS=0
plan() { PLAN="$PLAN$1$TAB$2$TAB$3$TAB$4
"; }

plan_skill_dest() { # label base
  local label="$1" d="$2/$SKILL_NAME" st
  st="$(skill_state "$d")"
  if [ "$ACTION" = "uninstall" ]; then
    case "$st" in
      absent) plan skip "$label" "$d" "not installed" ;;
      foreign) plan skip "$label" "$d" "not created by this installer, left alone" ;;
      *) plan remove "$label" "$d" "" ;;
    esac
    return
  fi
  case "$st" in
    absent) plan "create-$MODE" "$label" "$d" "" ;;
    ours-ok) plan ok "$label" "$d" "already installed ($MODE)" ;;
    ours-old)
      if [ "$UPDATE" -eq 1 ]; then plan "replace-$MODE" "$label" "$d" "update"
      else plan ok "$label" "$d" "installed but outdated or another mode; use --update"; fi ;;
    foreign)
      if [ "$FORCE" -eq 1 ]; then plan "force-$MODE" "$label" "$d" "existing item is backed up first"
      else plan collision "$label" "$d" "a different item exists; use --force to back it up"; COLLISIONS=1; fi ;;
  esac
}

plan_adapter() { # name
  local a="$1" rel f tmp1 tmp2 oflag
  rel="$(adapter_file "$a")"; f="$PROJ/$rel"
  if [ "$a" = "cursor-rule" ]; then
    if [ "$ACTION" = "uninstall" ]; then
      if [ -f "$f" ] && grep -q 'managed by code-review-skill install.sh' "$f"; then plan remove "adapter:$a" "$f" ""
      elif [ -e "$f" ]; then plan skip "adapter:$a" "$f" "not created by this installer, left alone"
      else plan skip "adapter:$a" "$f" "not installed"; fi
    elif [ ! -e "$f" ]; then plan file-create "adapter:$a" "$f" ""
    elif grep -q 'managed by code-review-skill install.sh' "$f"; then
      if [ "$(cursor_rule_text)" = "$(cat "$f")" ]; then plan ok "adapter:$a" "$f" "already installed"
      else plan file-replace "adapter:$a" "$f" "update"; fi
    elif [ "$FORCE" -eq 1 ]; then plan file-force "adapter:$a" "$f" "existing file is backed up first"
    else plan collision "adapter:$a" "$f" "a different file exists; use --force to back it up"; COLLISIONS=1; fi
    return
  fi
  if [ "$ACTION" = "uninstall" ]; then
    if [ -f "$f" ] && has_block "$f"; then plan block-remove "adapter:$a" "$f" "only the marked block"
    else plan skip "adapter:$a" "$f" "no managed block"; fi
    return
  fi
  if [ -f "$f" ] && has_block "$f"; then
    tmp1="$(mktemp "${TMPDIR:-/tmp}/crs.XXXXXX")"; tmp2="$(mktemp "${TMPDIR:-/tmp}/crs.XXXXXX")"
    oflag="$(strip_block "$f" "$tmp1")" || oflag="?"
    if make_with_block "$tmp1" "$SKILL_REL" "$tmp2" "$oflag" && cmp -s "$tmp2" "$f"; then
      plan ok "adapter:$a" "$f" "block already present"
    else plan block-replace "adapter:$a" "$f" "refresh the marked block"; fi
    rm -f "$tmp1" "$tmp2"
  else
    plan block-add "adapter:$a" "$f" "append a marked block"
  fi
}

for k in $KEYS; do
  case "$k" in
    adapter:*) plan_adapter "${k#adapter:}" ;;
    *) plan_skill_dest "$k ($SCOPE)" "$(skill_base "$k")" ;;
  esac
done
if [ -n "$CUSTOM_PATH" ]; then
  case "$CUSTOM_PATH" in
    /*) cp_abs="$CUSTOM_PATH" ;;
    *) cp_abs="$(pwd -P)/$CUSTOM_PATH" ;;
  esac
  [ ! -e "$cp_abs" ] || [ -d "$cp_abs" ] || die 1 "--path is not a directory: $CUSTOM_PATH"
  plan_skill_dest "path" "$cp_abs"
fi

# ---- --list --------------------------------------------------------------------------------
if [ "$ACTION" = "list" ]; then
  for sc in global project; do
    SCOPE="$sc"
    if [ "$sc" = "project" ]; then
      if command -v git >/dev/null 2>&1 && ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then BASE_ROOT="$ROOT"; else BASE_ROOT="$(pwd -P)"; fi
    else BASE_ROOT="$HOME"; fi
    for k in claude cline agents; do
      d="$(skill_base "$k")/$SKILL_NAME"
      st="$(skill_state "$d")"
      case "$st" in
        absent) desc="not installed" ;; ours-ok|ours-old) desc="installed by this installer" ;;
        foreign) desc="a different item is present" ;;
      esac
      printf '%-8s %-8s %s  [%s]\n' "$sc" "$k" "$d" "$desc"
    done
  done
  exit 0
fi

# ---- print plan --------------------------------------------------------------------------------
say "Plan ($ACTION, scope=$SCOPE, mode=$MODE):"
printf '%s' "$PLAN" | while IFS="$TAB" read -r a kind path note; do
  [ -n "$a" ] || continue
  if [ -n "$note" ]; then printf '  %-15s %s  %s  (%s)\n' "$a" "$kind" "$path" "$note"
  else printf '  %-15s %s  %s\n' "$a" "$kind" "$path"; fi
done
if [ "$FORCE" -eq 1 ]; then say "  backups go to: $HOME/.code-review-skill-backups/"; fi

if [ "$COLLISIONS" -eq 1 ]; then
  say "Nothing written: resolve the collisions above, or re-run with --force."
  exit 3
fi
if [ "$DRY" -eq 1 ]; then say "Dry run: nothing written."; exit 0; fi

todo="$(printf '%s' "$PLAN" | grep -v "^ok$TAB" | grep -v "^skip$TAB" || true)"
if [ -z "$todo" ]; then say "Nothing to do."; exit 0; fi

if [ "$YES" -ne 1 ]; then
  if ( : < /dev/tty ) 2>/dev/null; then
    printf 'Proceed? [Y/n] ' > /dev/tty
    read -r ans < /dev/tty || ans="n"
    case "$ans" in ""|y|Y|yes|YES) ;; *) say "Declined."; exit 7 ;; esac
  else
    die 2 "no terminal to confirm on; re-run with --yes"
  fi
fi

# ---- execute -----------------------------------------------------------------------------------------
BACKUP_DIR=""
backup() { # path
  local n
  if [ -z "$BACKUP_DIR" ]; then
    BACKUP_DIR="$HOME/.code-review-skill-backups/$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$BACKUP_DIR"
  fi
  n="$(printf '%s' "$1" | tr '/' '_')"
  mv "$1" "$BACKUP_DIR/$n"
  say "  backed up $1 -> $BACKUP_DIR/$n"
}

put_skill() { # dest
  local d="$1" t
  mkdir -p "$(dirname "$d")"
  if [ "$MODE" = "symlink" ]; then
    ln -s "$SRC" "$d"
  else
    t="$d.tmp.$$"
    rm -rf "$t"
    cp -R "$SRC" "$t"
    printf 'managed by code-review-skill install.sh\n' > "$t/$MARKER_FILE"
    mv "$t" "$d"
  fi
}

# Drop the empty skills dir, and its parent when we made it likely: always .agents, others only in a project.
prune_empty() {
  rmdir "$1" 2>/dev/null || true
  case "$(basename "$(dirname "$1")")" in
    .agents) rmdir "$(dirname "$1")" 2>/dev/null || true ;;
    .claude|.cline) [ "$SCOPE" = "project" ] && { rmdir "$(dirname "$1")" 2>/dev/null || true; } ;;
  esac
  return 0
}

PLANFILE="$(mktemp "${TMPDIR:-/tmp}/crs-plan.XXXXXX")"
printf '%s' "$PLAN" | grep -v '^$' > "$PLANFILE"
while IFS="$TAB" read -r a kind path note; do
  case "$a" in
    create-*) put_skill "$path"; say "installed $path" ;;
    replace-*) rm -rf "$path"; put_skill "$path"; say "updated $path" ;;
    force-symlink|force-copy) backup "$path"; put_skill "$path"; say "installed $path" ;;
    remove)
      case "$kind" in
        adapter:cursor-rule) rm -f "$path"; rmdir "$(dirname "$path")" 2>/dev/null || true; rmdir "$(dirname "$(dirname "$path")")" 2>/dev/null || true ;;
        path) if [ -L "$path" ]; then rm "$path"; else rm -rf "$path"; fi ;;
        *) if [ -L "$path" ]; then rm "$path"; else rm -rf "$path"; fi; prune_empty "$(dirname "$path")" ;;
      esac
      say "removed $path" ;;
    file-create) mkdir -p "$(dirname "$path")"; cursor_rule_text > "$path"; say "wrote $path" ;;
    file-replace) cursor_rule_text > "$path"; say "updated $path" ;;
    file-force) backup "$path"; mkdir -p "$(dirname "$path")"; cursor_rule_text > "$path"; say "wrote $path" ;;
    block-add|block-replace)
      tmp1="$(mktemp "${TMPDIR:-/tmp}/crs.XXXXXX")"; tmp2="$(mktemp "${TMPDIR:-/tmp}/crs.XXXXXX")"
      if [ "$a" = "block-replace" ]; then
        oflag="$(strip_block "$path" "$tmp1")"
        make_with_block "$tmp1" "$SKILL_REL" "$tmp2" "$oflag"
      else
        make_with_block "$path" "$SKILL_REL" "$tmp2"
      fi
      mkdir -p "$(dirname "$path")"
      cat "$tmp2" > "$path"
      rm -f "$tmp1" "$tmp2"
      say "wrote block in $path" ;;
    block-remove)
      tmp1="$(mktemp "${TMPDIR:-/tmp}/crs.XXXXXX")"
      flag="$(strip_block "$path" "$tmp1")"
      if [ "$flag" = "created" ] && [ ! -s "$tmp1" ]; then
        rm -f "$path"; rmdir "$(dirname "$path")" 2>/dev/null || true
        say "removed $path (it only held our block)"
      else
        cat "$tmp1" > "$path"; say "removed block from $path"
      fi
      rm -f "$tmp1" ;;
  esac
done < "$PLANFILE"
rm -f "$PLANFILE"

if [ "$ACTION" = "install" ]; then
  case "$KEYS" in
    *adapter:aider*)
      say "Aider note: aider does not load CONVENTIONS.md by itself. Add to .aider.conf.yml:"
      say "  read: [CONVENTIONS.md, $SKILL_REL]" ;;
  esac
  say "Restart or reload your agent so it rescans skills."
fi
exit 0
