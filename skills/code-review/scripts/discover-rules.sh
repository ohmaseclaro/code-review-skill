#!/usr/bin/env bash
# discover-rules.sh: inventory the rule, convention and review-config files of a
# repository, then map the paths touched by a change to the rule files and code
# owners that apply to them.
#
# Touched paths come from the current branch (default), a base/head pair, one
# commit, a commit range, uncommitted or staged changes, a unified diff, a list
# of paths on stdin, or files and directories named on the command line.
#
# Read-only: runs git read commands and reads files; writes nothing.
# Compatible with bash 3.2 (macOS default). Needs git (optional outside a
# repository), find and grep plus POSIX sed, sort, uniq, head, wc, tr and cat.
# No jq, awk, python or network access.
#
# Glob matching (applyTo, globs, paths, CODEOWNERS) is an approximation.
# Confirm by reading the rule file before citing it.

set -u

PROG=discover-rules
DIR=.
BASE=
HEAD_REF=HEAD
HEAD_EXPLICIT=0
WORKTREE=0
STAGED=0
COMMIT=
RANGE=
DIFF_FILE=
PATHS_MODE=0
SOURCE=worktree
STDIN_PATHS=0
NO_DIFF=0
SHOW_ALL=0
SELF_TEST=0
MAX_PATHS=300
LIST_CAP=25

usage() {
  cat <<'EOF'
Usage: discover-rules.sh [options]

Touched paths (choose at most one; default is the current branch):
  (none)               merge-base(base, HEAD) to the working tree
  -b, --base <ref>     base ref (default: auto-detect origin/HEAD, origin/main,
                       origin/master, main, master)
  -H, --head <ref>     head ref; the working tree is then ignored
  -w, --worktree       uncommitted changes (staged + unstaged) vs HEAD
  -s, --staged         staged changes
  --commit <sha>       one commit against its parent
  --range <A..B>       explicit range; A...B uses the merge-base of A and B
  --diff-file <file>   paths named in a unified diff; "-" reads stdin
  --paths-from-stdin   one repository-relative path per line on stdin
  --paths <path>...    these files or directories; must come last
  --no-diff            inventory only, no touched-path mapping

Other:
  -C <dir>             repository directory (default: current directory);
                       relative --diff-file and --paths arguments resolve
                       against it
  --source <where>     where rule files are read from: "worktree" (default) or
                       "base" (the base commit; use for untrusted changes)
  --max-paths <n>      map at most n touched paths (default: 300)
  --all                do not truncate long lists
  --self-test          check the glob matcher and exit
  -h, --help           show this help

Examples:
  discover-rules.sh                                   # current branch
  discover-rules.sh -b origin/main -H <head-sha> --source base
  gh pr diff 123 --name-only | discover-rules.sh --paths-from-stdin
  discover-rules.sh --diff-file change.patch
  discover-rules.sh --paths src/billing
EOF
}

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -C) [ $# -ge 2 ] || die "-C needs a directory"; DIR=$2; shift 2 ;;
    -b|--base) [ $# -ge 2 ] || die "$1 needs a ref"; BASE=$2; shift 2 ;;
    -H|--head) [ $# -ge 2 ] || die "$1 needs a ref"; HEAD_REF=$2; HEAD_EXPLICIT=1; shift 2 ;;
    -w|--worktree) WORKTREE=1; shift ;;
    -s|--staged) STAGED=1; shift ;;
    --commit) [ $# -ge 2 ] || die "--commit needs a revision"; COMMIT=$2; shift 2 ;;
    --range) [ $# -ge 2 ] || die "--range needs A..B"; RANGE=$2; shift 2 ;;
    --diff-file) [ $# -ge 2 ] || die "--diff-file needs a file or -"; DIFF_FILE=$2; shift 2 ;;
    --paths) shift; PATHS_MODE=1; break ;;
    --source) [ $# -ge 2 ] || die "--source needs worktree or base"; SOURCE=$2; shift 2 ;;
    --paths-from-stdin) STDIN_PATHS=1; shift ;;
    --no-diff) NO_DIFF=1; shift ;;
    --max-paths) [ $# -ge 2 ] || die "--max-paths needs a number"; MAX_PATHS=$2; shift 2 ;;
    --all) SHOW_ALL=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done
case "$SOURCE" in worktree|base) ;; *) die "--source must be worktree or base" ;; esac
case "$MAX_PATHS" in ''|*[!0-9]*) die "--max-paths must be a number" ;; esac
SEL=0
if [ "$STAGED" = 1 ]; then SEL=$((SEL + 1)); fi
if [ "$WORKTREE" = 1 ]; then SEL=$((SEL + 1)); fi
if [ -n "$COMMIT" ]; then SEL=$((SEL + 1)); fi
if [ -n "$RANGE" ]; then SEL=$((SEL + 1)); fi
if [ -n "$DIFF_FILE" ]; then SEL=$((SEL + 1)); fi
if [ "$PATHS_MODE" = 1 ]; then SEL=$((SEL + 1)); fi
if [ "$STDIN_PATHS" = 1 ]; then SEL=$((SEL + 1)); fi
if [ "$NO_DIFF" = 1 ]; then SEL=$((SEL + 1)); fi
[ "$SEL" -le 1 ] || die "choose one of --worktree, --staged, --commit, --range, --diff-file, --paths-from-stdin, --paths, --no-diff"

# ---------------------------------------------------------------- helpers ---

g() { git -c core.quotepath=off "$@"; }

nlines() { if [ -z "$1" ]; then echo 0; else printf '%s' "$1" | grep -c ''; fi; }

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

unquote() {
  local s=$1
  case "$s" in
    \"*\") s=${s#\"}; s=${s%\"} ;;
    \'*\') s=${s#\'}; s=${s%\'} ;;
  esac
  printf '%s' "$s"
}

# brace_mark: protect {a,b} alternation so commas inside braces survive splitting
brace_mark() {
  local s=$1 out='' c i depth=0
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case "$c" in
      '{') depth=$((depth + 1)); out="$out@@LB@@" ;;
      '}') if [ "$depth" -gt 0 ]; then depth=$((depth - 1)); out="$out@@RB@@"; else out="$out}"; fi ;;
      ',') if [ "$depth" -gt 0 ]; then out="$out@@OR@@"; else out="$out,"; fi ;;
      *) out="$out$c" ;;
    esac
  done
  if [ "$depth" -ne 0 ]; then printf '%s' "$s"; else printf '%s' "$out"; fi
}

# glob_to_ere <glob>: convert a gitignore-style glob into an anchored ERE.
#   leading "/" or an inner "/" anchors at the repository root; otherwise the
#   pattern matches at any depth. A name without wildcards also matches
#   everything below it (directory semantics, as in CODEOWNERS).
glob_to_ere() {
  local gl=$1 anchored=0 isdir=0 last re
  gl=${gl#./}
  case "$gl" in /*) anchored=1; gl=${gl#/} ;; esac
  case "$gl" in */) isdir=1; gl=${gl%/} ;; esac
  if [ -z "$gl" ]; then printf '%s' '^.*$'; return 0; fi
  case "$gl" in */*) anchored=1 ;; esac
  case "$gl" in '**'*) anchored=1 ;; esac
  last=${gl##*/}
  case "$gl" in *"{"*) gl=$(brace_mark "$gl") ;; esac
  re=$(printf '%s' "$gl" | sed -E \
    -e 's/[.+(){}|^$]/\\&/g' \
    -e 's/\[!/[^/g' \
    -e 's#\*\*/#@@DSS@@#g' -e 's#\*\*#@@DS@@#g' \
    -e 's#\*#[^/]*#g' -e 's#\?#[^/]#g' \
    -e 's#@@DSS@@#(.*/)?#g' -e 's#@@DS@@#.*#g' \
    -e 's#@@LB@@#(#g' -e 's#@@RB@@#)#g' -e 's#@@OR@@#|#g')
  if [ "$anchored" = 1 ]; then re="^$re"; else re="(^|/)$re"; fi
  if [ "$isdir" = 1 ]; then
    re="$re/.*\$"
  else
    case "$last" in
      *[*?]*) re="$re\$" ;;
      *) re="$re(/.*)?\$" ;;
    esac
  fi
  printf '%s' "$re"
}

# split_globs <string>: print one glob per line from "a, b" or ["a", "b"]
split_globs() {
  local s=$1 part rest
  s=$(trim "$s")
  case "$s" in '['*']') s=${s#[}; s=${s%]} ;; esac
  s=$(brace_mark "$(unquote "$s")")
  rest=$s
  while [ -n "$rest" ]; do
    case "$rest" in
      *,*) part=${rest%%,*}; rest=${rest#*,} ;;
      *) part=$rest; rest='' ;;
    esac
    part=$(unquote "$(trim "$part")")
    part=${part//@@LB@@/\{}; part=${part//@@RB@@/\}}; part=${part//@@OR@@/,}
    if [ -n "$part" ]; then printf '%s\n' "$part"; fi
  done
}

# fm_globs: read a file on stdin; print "G<TAB>glob" per scoping glob found in
# its YAML front matter and "A" when it is marked always-on.
fm_globs() {
  local line n=0 val inlist=0 item
  while IFS= read -r line; do
    n=$((n + 1))
    line=${line%$'\r'}
    if [ "$n" = 1 ]; then
      if [ "$line" != "---" ]; then return 0; fi
      continue
    fi
    if [ "$line" = "---" ] || [ "$n" -gt 60 ]; then break; fi
    case "$line" in
      applyTo:*|globs:*|paths:*|fileMatchPattern:*)
        val=$(trim "${line#*:}")
        if [ -z "$val" ]; then
          inlist=1
        else
          inlist=0
          split_globs "$val" | while IFS= read -r item; do printf 'G\t%s\n' "$item"; done
        fi ;;
      alwaysApply:*true*|"inclusion: always"*|"trigger: always_on"*) printf 'A\n'; inlist=0 ;;
      [[:space:]]*-*|-*)
        if [ "$inlist" = 1 ]; then
          item=$(unquote "$(trim "${line#*-}")")
          if [ -n "$item" ]; then printf 'G\t%s\n' "$item"; fi
        fi ;;
      *) inlist=0 ;;
    esac
  done
}

if [ "$SELF_TEST" = 1 ]; then
  fails=0
  t() { # t <glob> <path> <yes|no>
    local re got=no
    re=$(glob_to_ere "$1")
    if [[ $2 =~ $re ]]; then got=yes; fi
    if [ "$got" != "$3" ]; then
      printf 'FAIL glob=%s path=%s expected=%s regex=%s\n' "$1" "$2" "$3" "$re"; fails=$((fails + 1))
    fi
  }
  t '*' 'a/b/c.ts' yes
  t '*.js' 'src/a.js' yes
  t '*.js' 'src/a.jsx' no
  t '/docs' 'docs/x/y.md' yes
  t '/docs' 'src/docs/y.md' no
  t 'docs/*' 'docs/a.md' yes
  t 'docs/*' 'docs/sub/a.md' no
  t 'apps/' 'x/apps/y/z.go' yes
  t '/build/logs/' 'build/logs/a.txt' yes
  t '**/*.test.ts' 'a/b/c.test.ts' yes
  t '**/*.test.ts' 'c.test.ts' yes
  t 'src/**' 'src/a/b.py' yes
  t 'src/**' 'lib/src/a.py' no
  t 'src/**/*.{ts,tsx}' 'src/a/b.tsx' yes
  t 'src/**/*.{ts,tsx}' 'src/a/b.js' no
  t '{api,web}/**' 'web/x.ts' yes
  t 'packages/api/**/*.ts' 'packages/api/src/x.ts' yes
  t 'file?.md' 'file1.md' yes
  t 'a.b' 'axb' no
  got=$(printf -- '---\napplyTo: "src/**/*.{ts,tsx}, docs/**"\n---\n' | fm_globs | tr '\n\t' '|:')
  if [ "$got" != 'G:src/**/*.{ts,tsx}|G:docs/**|' ]; then printf 'FAIL fm_globs inline: %s\n' "$got"; fails=$((fails + 1)); fi
  got=$(printf -- '---\nglobs:\n  - "*.py"\n  - tests/**\nalwaysApply: true\n---\n' | fm_globs | tr '\n\t' '|:')
  if [ "$got" != 'G:*.py|G:tests/**|A|' ]; then printf 'FAIL fm_globs list: %s\n' "$got"; fails=$((fails + 1)); fi
  if [ "$fails" -eq 0 ]; then printf 'self-test: ok\n'; exit 0; fi
  printf 'self-test: %s failure(s)\n' "$fails"; exit 1
fi

# ------------------------------------------------------------ repository ---

cd "$DIR" 2>/dev/null || die "cannot enter directory: $DIR"

GIVEN=
TARGET=
if [ "$PATHS_MODE" = 1 ]; then
  [ $# -gt 0 ] || die "--paths needs at least one file or directory"
  for arg in "$@"; do
    [ -e "$arg" ] || die "path not found: $arg"
  done
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    GIVEN=$(g ls-files --full-name -co --exclude-standard -- "$@")
  else
    GIVEN=$(find "$@" -type d \( -name .git -o -name node_modules -o -name vendor -o -name dist \
      -o -name build -o -name target -o -name .venv -o -name __pycache__ \) -prune \
      -o -type f -print 2>/dev/null | sed 's#^\./##')
  fi
  TARGET="files and directories named on the command line"
elif [ -n "$DIFF_FILE" ]; then
  if [ "$DIFF_FILE" = - ]; then
    RAW=$(cat)
    TARGET="unified diff from stdin"
  else
    [ -f "$DIFF_FILE" ] || die "diff file not found: $DIFF_FILE"
    RAW=$(cat -- "$DIFF_FILE")
    TARGET="unified diff from $DIFF_FILE"
  fi
  GIVEN=$(printf '%s\n' "$RAW" | grep '^diff --git ' | sed -E 's#^diff --git a/.* b/##')
  if [ -z "$GIVEN" ]; then
    # plain unified diff without git headers: fall back to the +++ lines
    GIVEN=$(printf '%s\n' "$RAW" | grep -E '^\+\+\+ ' | sed -E -e 's#^\+\+\+ ##' -e $'s#\t.*$##' -e 's#^b/##' | grep -v '^/dev/null$')
  fi
  RAW=
  [ -n "$GIVEN" ] || die "no file paths found in the diff"
fi

IS_GIT=0
if ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  IS_GIT=1
  cd "$ROOT" || die "cannot enter repository root"
else
  ROOT=$(pwd)
fi
if [ "$IS_GIT" = 0 ]; then
  if [ -n "$COMMIT" ] || [ -n "$RANGE" ] || [ "$STAGED" = 1 ] || [ "$WORKTREE" = 1 ]; then
    die "not a git repository: $DIR"
  fi
fi

detect_base() {
  local ref
  ref=$(g symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$ref" ]; then printf '%s\n' "$ref"; return 0; fi
  for ref in origin/main origin/master main master origin/develop develop trunk; do
    if g rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1; then
      printf '%s\n' "$ref"; return 0
    fi
  done
  return 1
}

# MB is the commit rule files are read from with --source base, and the start of the range.
MB=
HAVE_RANGE=0
if [ "$IS_GIT" = 1 ]; then
  if [ -n "$COMMIT" ]; then
    HEAD_REF=$(g rev-parse -q --verify "$COMMIT^{commit}" 2>/dev/null) || die "commit not found: $COMMIT"
    if MB=$(g rev-parse -q --verify "$HEAD_REF^" 2>/dev/null); then :; else MB=$(g hash-object -t tree /dev/null); fi
    BASE="$COMMIT^"; HEAD_EXPLICIT=1; HAVE_RANGE=1
    TARGET="commit $COMMIT"
  elif [ -n "$RANGE" ]; then
    three=0
    case "$RANGE" in
      *...*) ra=${RANGE%%...*}; rb=${RANGE#*...}; three=1 ;;
      *..*) ra=${RANGE%%..*}; rb=${RANGE#*..} ;;
      *) die "--range needs A..B or A...B" ;;
    esac
    [ -n "$ra" ] || die "--range needs a start revision"
    [ -n "$rb" ] || rb=HEAD
    HEAD_REF=$(g rev-parse -q --verify "$rb^{commit}" 2>/dev/null) || die "revision not found: $rb"
    if [ "$three" = 1 ]; then
      MB=$(g merge-base "$ra" "$rb" 2>/dev/null) || die "no merge base between $ra and $rb"
    else
      MB=$(g rev-parse -q --verify "$ra^{commit}" 2>/dev/null) || die "revision not found: $ra"
    fi
    BASE=$ra; HEAD_EXPLICIT=1; HAVE_RANGE=1
    TARGET="range $RANGE"
  elif [ "$STAGED" = 1 ] || [ "$WORKTREE" = 1 ]; then
    if MB=$(g rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null); then BASE=HEAD; HAVE_RANGE=1; fi
    if [ "$STAGED" = 1 ]; then TARGET="staged changes"; else TARGET="uncommitted changes vs HEAD"; fi
  else
    if [ -z "$BASE" ]; then BASE=$(detect_base) || BASE=; fi
    if [ -n "$BASE" ] && g rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 \
      && g rev-parse -q --verify "$HEAD_REF^{commit}" >/dev/null 2>&1; then
      if MB=$(g merge-base "$BASE" "$HEAD_REF" 2>/dev/null); then HAVE_RANGE=1; fi
    fi
    if [ -z "$TARGET" ] && [ "$STDIN_PATHS" = 0 ] && [ "$NO_DIFF" = 0 ] && [ "$HAVE_RANGE" = 1 ]; then
      if [ "$HEAD_EXPLICIT" = 1 ]; then TARGET="$BASE...$HEAD_REF"; else TARGET="$BASE...HEAD plus the working tree"; fi
    fi
  fi
fi
if [ "$STDIN_PATHS" = 1 ]; then TARGET="paths from stdin"; fi
if [ "$NO_DIFF" = 1 ]; then TARGET="none (inventory only)"; fi
if [ "$SOURCE" = base ] && [ "$HAVE_RANGE" = 0 ]; then
  die "--source base needs a resolvable base ref; pass --base <ref>"
fi

if [ "$IS_GIT" = 1 ]; then
  if [ "$SOURCE" = base ]; then
    FILES=$(g ls-tree -r --name-only "$MB")
  else
    FILES=$(g ls-files -co --exclude-standard)
  fi
else
  FILES=$(find . -type d \( -name .git -o -name node_modules -o -name vendor -o -name dist \
    -o -name build -o -name target -o -name .venv -o -name venv -o -name __pycache__ \) -prune \
    -o -type f -print 2>/dev/null | sed 's#^\./##')
fi

show() {
  if [ "$SOURCE" = base ]; then
    g show "$MB:$1" 2>/dev/null
  elif [ -f "$1" ]; then
    cat -- "$1" 2>/dev/null
  fi
}

pick() { printf '%s\n' "$FILES" | grep -E -- "$1" | sort; }
ipick() { printf '%s\n' "$FILES" | grep -iE -- "$1" | sort; }

# ------------------------------------------------------------ categories ---

RE_AGENT='(^|/)(AGENTS\.md|AGENTS\.override\.md|AGENT\.md|CLAUDE\.md|CLAUDE\.local\.md|GEMINI\.md|QWEN\.md|WARP\.md|CONVENTIONS\.md|\.cursorrules|\.windsurfrules|\.clinerules|\.goosehints|\.rules|\.augment-guidelines)$|(^|/)\.cursor/rules/.+\.(mdc|md)$|(^|/)\.claude/rules/.+\.md$|(^|/)\.windsurf/rules/.+\.md$|(^|/)\.clinerules/.+|(^|/)\.roo/rules[^/]*/.+|(^|/)\.github/copilot-instructions\.md$|(^|/)\.github/instructions/.+\.instructions\.md$|(^|/)\.junie/guidelines\.md$|(^|/)\.kiro/steering/.+\.md$|(^|/)\.amazonq/rules/.+\.md$|(^|/)\.aiassistant/rules/.+\.md$|(^|/)\.augment/rules/.+|(^|/)\.continue/rules/.+\.md$'
RE_REVIEWER='(^|/)(REVIEW\.md|\.review-rules\.md|BUGBOT\.md|APPROVAL_POLICY\.md|AUTOAPPROVE\.md|\.coderabbit\.ya?ml|greptile\.json|\.pr_agent\.toml|pr_agent\.toml|best_practices\.md|pantoai\.md|cubic\.ya?ml|\.sourcery\.yaml|\.reviewdog\.yml|\.codeclimate\.yml|\.deepsource\.toml|sonar-project\.properties|[Dd]angerfile(\.(js|ts|rb))?|review-context\.toml|kodus-config\.ya?ml)$|(^|/)\.coderabbit/.+|(^|/)\.greptile/.+|(^|/)\.gemini/(styleguide\.md|config\.ya?ml)$|(^|/)\.gitlab/duo/.+\.ya?ml$|(^|/)\.ellipsis/.+|(^|/)\.macroscope/.+|(^|/)\.factory/review\.ya?ml$|(^|/)\.gitar/.+|(^|/)\.codeant/.+|(^|/)\.continue/checks/.+|(^|/)\.cursor/(BUGBOT\.md|config/bugbot\.ya?ml|approval-policies/.+)$|(^|/)\.qodo/.+'
RE_SKILLS='(^|/)\.(claude|github|agents|codex|cursor|factory|gemini|opencode)/skills/[^/]+/SKILL\.md$|(^|/)\.(claude|cursor|opencode|codex)/(commands|agents|prompts)/[^/]*(review|security|audit|lint|style|test)[^/]*\.md$'
RE_DOCS='(^|/)(contributing|code_review|code-review|reviewing|style_?guide|styleguide|coding[_-]?(standards|guidelines|style|conventions)|conventions|development|developing|hacking|architecture|security|testing|maintainers|governance)[^/]*\.(md|rst|adoc|txt)$|(^|/)(docs?|documentation)/(adrs?|decisions|architecture|rfcs?|design|standards|conventions|guidelines|engineering|contributing)/.+\.(md|rst|adoc)$|(^|/)(adrs?|rfcs?|decisions)/.+\.(md|rst|adoc)$'
RE_TEMPLATES='(^|/)\.github/(pull_request_template(/.+)?(\.md)?|issue_template/.+)$|(^|/)(docs/)?pull_request_template\.md$|(^|/)\.gitlab/(merge_request_templates|issue_templates)/.+|(^|/)\.azuredevops/pull_request_template.*'
RE_OWNERS='^(\.github/|docs/|\.gitlab/)?CODEOWNERS$|(^|/)OWNERS$'
RE_LINT='(^|/)(\.eslintrc[^/]*|eslint\.config\.[a-z]+|\.prettierrc[^/]*|prettier\.config\.[a-z]+|biome\.jsonc?|\.oxlintrc\.json|tsconfig[^/]*\.json|\.editorconfig|ruff\.toml|\.ruff\.toml|pyproject\.toml|setup\.cfg|\.flake8|mypy\.ini|pyrightconfig\.json|\.pylintrc|tox\.ini|\.golangci\.ya?ml|rustfmt\.toml|\.rustfmt\.toml|clippy\.toml|deny\.toml|\.rubocop\.yml|phpcs\.xml(\.dist)?|phpstan\.neon(\.dist)?|psalm\.xml|\.php-cs-fixer[^/]*|\.stylelintrc[^/]*|checkstyle[^/]*\.xml|detekt\.ya?ml|\.swiftlint\.yml|\.clang-format|\.clang-tidy|\.shellcheckrc|\.hadolint\.ya?ml|\.tflint\.hcl|\.checkov\.ya?ml|\.semgrep\.ya?ml|\.semgrepignore|sgconfig\.yml|\.markdownlint[^/]*|\.yamllint[^/]*|\.pre-commit-config\.yaml|lefthook\.ya?ml|commitlint\.config\.[a-z]+|\.commitlintrc[^/]*|\.gitleaks\.toml|\.trivyignore|\.snyk|codecov\.ya?ml|\.codecov\.ya?ml|\.lintstagedrc[^/]*|\.sqlfluff|\.squawk\.toml|buf\.ya?ml|\.spectral\.ya?ml)$|(^|/)\.husky/[^/_][^/]*$|(^|/)\.semgrep/.+'
RE_CI='^\.github/workflows/.+\.ya?ml$|^\.gitlab-ci\.yml$|^\.gitlab/ci/.+|^\.circleci/config\.yml$|(^|/)Jenkinsfile[^/]*$|(^|/)azure-pipelines[^/]*\.ya?ml$|^bitbucket-pipelines\.yml$|^\.buildkite/.+|^\.drone\.yml$|^\.travis\.yml$|^\.woodpecker(\.ya?ml|/.+)$|(^|/)cloudbuild\.ya?ml$|^\.github/dependabot\.yml$|(^|/)renovate\.json5?$'

AGENT=$(pick "$RE_AGENT")
REVIEWER=$(pick "$RE_REVIEWER")
SKILLS=$(pick "$RE_SKILLS")
DOCS=$(ipick "$RE_DOCS")
TEMPLATES=$(ipick "$RE_TEMPLATES")
OWNERS=$(pick "$RE_OWNERS")
LINT=$(pick "$RE_LINT")
CI=$(pick "$RE_CI")

# ------------------------------------------------------- scoped rule data ---

ROOT_RULES=
UNSCOPED=
NEST_N=0
GLOB_N=0
SCOPE_NOTE=

add_glob() { # add_glob <glob> <label> <scope-dir>
  GLOB_RE[GLOB_N]=$(glob_to_ere "$1")
  GLOB_F[GLOB_N]=$2
  GLOB_D[GLOB_N]=$3
  GLOB_N=$((GLOB_N + 1))
}

scope_dir() { # directory a rule file governs: its own directory, or the parent of the dot-directory it lives in
  local rest=$1 pre='' seg
  while :; do
    case "$rest" in
      */*) seg=${rest%%/*}; rest=${rest#*/} ;;
      *) break ;;
    esac
    case "$seg" in .?*) break ;; esac
    if [ -z "$pre" ]; then pre=$seg; else pre="$pre/$seg"; fi
  done
  printf '%s' "${pre:-.}"
}

SCOPED_FILES=$(printf '%s\n%s\n' "$AGENT" "$REVIEWER" | grep -v '^$')
NEST_LINES=
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    .github/instructions/*|*/.github/instructions/*|.cursor/rules/*|*/.cursor/rules/*|.claude/rules/*|*/.claude/rules/*|.coderabbit/instructions/*|.continue/rules/*|*/.continue/rules/*|.windsurf/rules/*|.kiro/steering/*|.amazonq/rules/*|.clinerules/*|.roo/rules*/*|.aiassistant/rules/*|.augment/rules/*)
      sd=$(scope_dir "$f")
      meta=$(show "$f" | head -n 60 | fm_globs)
      if [ -z "$meta" ]; then
        case "$f" in
          .roo/rules-*|*/.roo/rules-*) UNSCOPED="$UNSCOPED$f"$'\n' ;;
          *.claude/rules/*|.amazonq/*|.clinerules/*|.roo/*|.aiassistant/*|.augment/*|.coderabbit/*)
            if [ "$sd" = . ]; then ROOT_RULES="$ROOT_RULES$f"$'\n'; else NEST_LINES="$NEST_LINES$sd"$'\t'"$f"$'\n'; fi ;;
          *) UNSCOPED="$UNSCOPED$f"$'\n' ;;
        esac
      else
        while IFS=$'\t' read -r kind val; do
          case "$kind" in
            A) if [ "$sd" = . ]; then ROOT_RULES="$ROOT_RULES$f"$'\n'; else NEST_LINES="$NEST_LINES$sd"$'\t'"$f"$'\n'; fi ;;
            G) add_glob "$val" "$f" "$sd" ;;
          esac
        done <<EOF
$meta
EOF
      fi ;;
    .coderabbit.yaml|.coderabbit.yml)
      ROOT_RULES="$ROOT_RULES$f"$'\n'
      while IFS= read -r gl; do
        gl=$(unquote "$(trim "$gl")")
        [ -n "$gl" ] || continue
        add_glob "$gl" "$f#path_instructions[$gl]" .
      done <<EOF
$(show "$f" | grep -E '^[[:space:]]*-[[:space:]]*path:' | sed -E 's/^[^:]*:[[:space:]]*//')
EOF
      ;;
    *.gitlab/duo/*|greptile.json|.greptile/*|.macroscope/*|.ellipsis/*|.continue/checks/*|.codeant/*|.gitar/*|.qodo/*)
      ROOT_RULES="$ROOT_RULES$f"$'\n'
      SCOPE_NOTE=1 ;;
    *)
      sd=$(scope_dir "$f")
      if [ "$sd" = . ]; then ROOT_RULES="$ROOT_RULES$f"$'\n'; else NEST_LINES="$NEST_LINES$sd"$'\t'"$f"$'\n'; fi ;;
  esac
done <<EOF
$SCOPED_FILES
EOF

# deepest directory first, so the nearest rule file is listed first
if [ -n "$NEST_LINES" ]; then
  while IFS=$'\t' read -r depth d f; do
    [ -n "$f" ] || continue
    NEST_D[NEST_N]=$d
    NEST_F[NEST_N]=$f
    NEST_N=$((NEST_N + 1))
  done <<EOF
$(printf '%s' "$NEST_LINES" | while IFS=$'\t' read -r d f; do
    [ -n "$f" ] || continue
    slashes=${d//[!\/]/}
    printf '%s\t%s\t%s\n' "${#slashes}" "$d" "$f"
  done | sort -t$'\t' -k1,1nr -k2,2)
EOF
fi

# --------------------------------------------------------------- output ---

printf 'discover-rules v1\n'
if [ "$IS_GIT" = 1 ]; then
  if [ "$HAVE_RANGE" = 1 ]; then
    printf 'repo: %s  rule source: %s  base: %s (%s)\n' "$ROOT" "$SOURCE" "$BASE" "$(g rev-parse --short "$MB" 2>/dev/null || printf '%s' "${MB:0:8}")"
  else
    printf 'repo: %s  rule source: %s  base: (not resolved)\n' "$ROOT" "$SOURCE"
  fi
else
  printf 'repo: %s  (not a git repository: no code history, rule files read from disk)\n' "$ROOT"
fi
printf 'target: %s\n' "${TARGET:-not resolved}"

fsize() { show "$1" | wc -l | tr -d ' '; }

section() { # section <title> <list> <with-size 0|1>
  local title=$1 list=$2 withsize=$3 total n=0 f
  total=$(nlines "$list")
  printf '\n== %s (%s) ==\n' "$title" "$total"
  if [ "$total" -eq 0 ]; then printf '  (none found)\n'; return 0; fi
  if [ "$SHOW_ALL" = 0 ] && [ "$total" -gt "$LIST_CAP" ]; then
    printf '%s\n' "$list" | head -n 8 | while IFS= read -r f; do
      if [ "$withsize" = 1 ]; then printf '  %s  (%s lines)\n' "$f" "$(fsize "$f")"; else printf '  %s\n' "$f"; fi
    done
    printf '  ... %s more, by directory (use --all for the full list):\n' "$((total - 8))"
    printf '%s\n' "$list" | sed -e '1,8d' -e 's#/[^/]*$#/#' -e '/\//!s#.*#./#' | sort | uniq -c | sort -rn | head -n 12 \
      | while read -r cnt dname; do printf '    %s  (%s files)\n' "$dname" "$cnt"; done
    return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    if [ "$withsize" = 1 ]; then printf '  %s  (%s lines)\n' "$f" "$(fsize "$f")"; else printf '  %s\n' "$f"; fi
  done <<EOF
$list
EOF
}

section 'agent instruction files: the nearest directory wins' "$AGENT" 1
section 'reviewer configs and review rule files' "$REVIEWER" 1
section 'skills, commands and agents about review, tests or style' "$SKILLS" 0
section 'contribution, style, security and architecture docs' "$DOCS" 0
section 'PR and issue templates' "$TEMPLATES" 0
section 'ownership files' "$OWNERS" 0
section 'lint, format, type and hook configs: skip what these enforce' "$LINT" 0
section 'CI and automation' "$CI" 0

GA=$(printf '%s\n' "$FILES" | grep -E '(^|/)\.gitattributes$' | head -n 5)
if [ -n "$GA" ]; then
  gen=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    c=$(show "$f" | grep -cE 'linguist-generated|linguist-vendored')
    gen=$((gen + c))
  done <<EOF
$GA
EOF
  printf '\n== generated or vendored markers ==\n  .gitattributes entries with linguist-generated or linguist-vendored: %s\n' "$gen"
fi

# ------------------------------------------------------- touched paths ---

TOUCHED=
if [ "$STDIN_PATHS" = 1 ]; then
  TOUCHED=$(cat)
elif [ -n "$GIVEN" ]; then
  TOUCHED=$GIVEN
elif [ "$NO_DIFF" = 0 ] && [ "$IS_GIT" = 1 ]; then
  if [ "$STAGED" = 1 ]; then
    TOUCHED=$(g diff --cached --name-only -M)
  elif [ "$WORKTREE" = 1 ]; then
    TOUCHED=$(g diff HEAD --name-only -M 2>/dev/null; g ls-files --others --exclude-standard)
  elif [ "$HAVE_RANGE" = 1 ]; then
    if [ "$HEAD_EXPLICIT" = 1 ]; then
      TOUCHED=$(g diff "$MB" "$HEAD_REF" --name-only -M)
    else
      TOUCHED=$(g diff "$MB" --name-only -M; g ls-files --others --exclude-standard)
    fi
  fi
fi
TOUCHED=$(printf '%s\n' "$TOUCHED" | grep -v '^$' | sort -u)
T_TOTAL=$(nlines "$TOUCHED")

if [ "$NO_DIFF" = 1 ] && [ "$STDIN_PATHS" = 0 ]; then exit 0; fi
if [ "$T_TOTAL" -eq 0 ]; then
  printf '\n== touched paths (0) ==\n  (nothing to map: no change resolved; pass --base, --commit, --range, --diff-file, --paths or --paths-from-stdin)\n'
  exit 0
fi

T_USED=$TOUCHED
if [ "$T_TOTAL" -gt "$MAX_PATHS" ]; then T_USED=$(printf '%s\n' "$TOUCHED" | head -n "$MAX_PATHS"); fi

printf '\n== touched paths (%s) -> rule files that apply ==\n' "$T_TOTAL"
if [ "$T_TOTAL" -gt "$MAX_PATHS" ]; then
  printf '  (mapping only the first %s paths; raise --max-paths to see more)\n' "$MAX_PATHS"
fi
if [ -n "$ROOT_RULES" ]; then
  printf '  every path: %s\n' "$(printf '%s' "$ROOT_RULES" | sort -u | tr '\n' ' ' | sed -e 's/ $//' -e 's/ /, /g')"
else
  printf '  every path: (no repository-wide rule file)\n'
fi
if [ -n "$SCOPE_NOTE" ]; then
  printf '  note: some reviewer configs above carry their own path scoping; read them\n'
fi

map_paths() {
  local p chain i re sd hit rel
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    chain=
    i=0
    while [ "$i" -lt "$NEST_N" ]; do
      case "$p" in
        "${NEST_D[i]}"/*) if [ -z "$chain" ]; then chain=${NEST_F[i]}; else chain="$chain | ${NEST_F[i]}"; fi ;;
      esac
      i=$((i + 1))
    done
    i=0
    while [ "$i" -lt "$GLOB_N" ]; do
      re=${GLOB_RE[i]}
      sd=${GLOB_D[i]}
      hit=0
      if [ "$sd" = . ]; then
        if [[ $p =~ $re ]]; then hit=1; fi
      else
        case "$p" in
          "$sd"/*)
            rel=${p#"$sd"/}
            if [[ $p =~ $re ]] || [[ $rel =~ $re ]]; then hit=1; fi ;;
        esac
      fi
      if [ "$hit" = 1 ]; then
        case " | $chain | " in
          *" | ${GLOB_F[i]} | "*) ;;
          *) if [ -z "$chain" ]; then chain=${GLOB_F[i]}; else chain="$chain | ${GLOB_F[i]}"; fi ;;
        esac
      fi
      i=$((i + 1))
    done
    if [ -z "$chain" ]; then chain='(no additional scoped rule file)'; fi
    printf '%s\t%s\n' "$chain" "$p"
  done <<EOF
$T_USED
EOF
}
MAPPED=$(map_paths)

print_groups() { # stdin: "key<TAB>path" sorted by key
  local key p prev='' n=0 shown='' first=1
  flush() {
    if [ "$first" = 0 ]; then
      if [ "$n" -gt 4 ]; then printf '     %s (+%s more)\n' "$shown" "$((n - 4))"; else printf '     %s\n' "$shown"; fi
    fi
  }
  while IFS=$'\t' read -r key p; do
    [ -n "$p" ] || continue
    if [ "$key" != "$prev" ] || [ "$first" = 1 ]; then
      flush
      printf '  [%s]\n' "$key"
      prev=$key; n=0; shown=''; first=0
    fi
    n=$((n + 1))
    if [ "$n" -le 4 ]; then
      if [ -z "$shown" ]; then shown=$p; else shown="$shown, $p"; fi
    fi
  done
  flush
}
printf '%s\n' "$MAPPED" | sort -t$'\t' -k1,1 -k2,2 | print_groups

if [ -n "$UNSCOPED" ]; then
  printf '  unscoped rule files (applied on request or by description; skim their titles): %s\n' \
    "$(printf '%s' "$UNSCOPED" | sort -u | head -n 12 | tr '\n' ' ' | sed -e 's/ $//' -e 's/ /, /g')"
fi

# ---------------------------------------------------------- code owners ---

OWN_FILE=
for c in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS .gitlab/CODEOWNERS; do
  if printf '%s\n' "$FILES" | grep -qxF -- "$c"; then OWN_FILE=$c; break; fi
done
if [ -n "$OWN_FILE" ]; then
  OWN_N=0
  while IFS= read -r line; do
    line=${line%%#*}
    line=$(trim "$line")
    [ -n "$line" ] || continue
    case "$line" in '['*|'^['*) continue ;; esac
    pat=${line%%[[:space:]]*}
    own=$(trim "${line#"$pat"}")
    OWN_RE[OWN_N]=$(glob_to_ere "$pat")
    OWN_OW[OWN_N]=${own:-(no owner)}
    OWN_N=$((OWN_N + 1))
    if [ "$OWN_N" -ge 1500 ]; then break; fi
  done <<EOF
$(show "$OWN_FILE")
EOF
  printf '\n== code owners of touched paths (%s, %s rules; last matching rule wins) ==\n' "$OWN_FILE" "$OWN_N"
  budget=60000
  limit=$T_TOTAL
  if [ "$OWN_N" -gt 0 ] && [ "$((OWN_N * T_TOTAL))" -gt "$budget" ]; then
    limit=$((budget / OWN_N))
    [ "$limit" -ge 1 ] || limit=1
    printf '  (large CODEOWNERS: resolving only the first %s paths)\n' "$limit"
  fi
  printf '%s\n' "$TOUCHED" | head -n "$limit" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    i=$((OWN_N - 1))
    who='(no owner)'
    while [ "$i" -ge 0 ]; do
      re=${OWN_RE[i]}
      if [[ $p =~ $re ]]; then who=${OWN_OW[i]}; break; fi
      i=$((i - 1))
    done
    printf '%s\t%s\n' "$who" "$p"
  done | sort -t$'\t' -k1,1 -k2,2 | print_groups
fi

# ------------------------------------------------- rule files in the diff ---

CHANGED_RULES=$(printf '%s\n' "$TOUCHED" | grep -E -- "$RE_AGENT|$RE_REVIEWER|$RE_SKILLS|$RE_OWNERS" | sort -u)
CHANGED_TOOLING=$(printf '%s\n' "$TOUCHED" | grep -E -- "$RE_LINT|$RE_CI" | sort -u)
if [ -n "$CHANGED_RULES" ]; then
  if [ "$PATHS_MODE" = 1 ]; then
    printf '\n== rule files among these paths: here they are review targets, not only guidance ==\n'
  else
    printf '\n== rule files changed by this diff: apply the base version, review the edit as a change ==\n'
  fi
  printf '%s\n' "$CHANGED_RULES" | sed 's/^/  /'
fi
if [ -n "$CHANGED_TOOLING" ]; then
  if [ "$PATHS_MODE" = 1 ]; then
    printf '\n== lint or CI config among these paths ==\n'
  else
    printf '\n== lint or CI config changed by this diff: check for weakened gates ==\n'
  fi
  printf '%s\n' "$CHANGED_TOOLING" | head -n 20 | sed 's/^/  /'
fi
exit 0
