#!/usr/bin/env bash
# diff-triage.sh: classify a change by size and risk area, suggest a review
# depth tier, and list the reference files worth loading.
#
# Targets: the current branch (default), a base/head pair, one commit, a commit
# range, uncommitted or staged changes, a unified diff from a file or stdin, or
# plain files and directories (whole-file review, no diff).
#
# Read-only: runs git read commands and reads files; writes nothing.
# Compatible with bash 3.2 (macOS default). Needs git (optional for --diff-file
# and --paths), find and grep plus POSIX sed, sort, uniq, head and cat.
# No jq, awk, python or network access.
#
# Output is a heuristic. Path and keyword matches are signals, not findings.

set -u

PROG=diff-triage
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
MAX_SCAN_LINES=20000
MAX_PATCH_LINES=300000
MAX_PATH_FILES=2000

usage() {
  cat <<'EOF'
Usage: diff-triage.sh [options]

Target (choose at most one; default is the current branch):
  (none)              merge-base(base, HEAD) to the working tree: committed,
                      staged and unstaged changes of the current branch
  -b, --base <ref>    base ref (default: auto-detect origin/HEAD, origin/main,
                      origin/master, main, master)
  -H, --head <ref>    head ref; the working tree is then ignored
  -w, --worktree      only uncommitted changes (staged + unstaged) vs HEAD
  -s, --staged        only staged changes
  --commit <sha>      one commit against its parent
  --range <A..B>      explicit range; A...B uses the merge-base of A and B
  --diff-file <file>  a unified diff or patch file; "-" reads stdin
                      (works outside a repository)
  --paths <path>...   whole files or directories, no diff; must come last

Other:
  -C <dir>            directory to run in (a repository, a worktree, or any
                      directory for --diff-file and --paths); relative
                      --diff-file and --paths arguments resolve against it
  -h, --help          show this help

Examples:
  diff-triage.sh                               # current branch vs default base
  diff-triage.sh -b origin/main -H <head-sha>  # a fetched pull request
  gh pr diff 123 | diff-triage.sh --diff-file - # a pull request without checkout
  diff-triage.sh --commit HEAD
  diff-triage.sh --range v1.2.0..HEAD
  diff-triage.sh --paths src/billing docs/api.md
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
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

SEL=0
if [ "$STAGED" = 1 ]; then SEL=$((SEL + 1)); fi
if [ "$WORKTREE" = 1 ]; then SEL=$((SEL + 1)); fi
if [ -n "$COMMIT" ]; then SEL=$((SEL + 1)); fi
if [ -n "$RANGE" ]; then SEL=$((SEL + 1)); fi
if [ -n "$DIFF_FILE" ]; then SEL=$((SEL + 1)); fi
if [ "$PATHS_MODE" = 1 ]; then SEL=$((SEL + 1)); fi
[ "$SEL" -le 1 ] || die "choose one target: --worktree, --staged, --commit, --range, --diff-file or --paths"

cd "$DIR" 2>/dev/null || die "cannot enter directory: $DIR"

g() { git -c core.quotepath=off "$@"; }

MODE=range
RAW=
PATH_FILES=
if [ -n "$DIFF_FILE" ]; then
  MODE='patch'
  if [ "$DIFF_FILE" = - ]; then
    RAW=$(cat)
  else
    [ -f "$DIFF_FILE" ] || die "diff file not found: $DIFF_FILE"
    RAW=$(cat -- "$DIFF_FILE")
  fi
  [ -n "$RAW" ] || die "the diff is empty"
elif [ "$PATHS_MODE" = 1 ]; then
  MODE=paths
  [ $# -gt 0 ] || die "--paths needs at least one file or directory"
  for arg in "$@"; do
    [ -e "$arg" ] || die "path not found: $arg"
  done
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    PATH_FILES=$(g ls-files --full-name -co --exclude-standard -- "$@" | sort -u)
  else
    PATH_FILES=$(find "$@" -type d \( -name .git -o -name node_modules -o -name vendor -o -name dist \
      -o -name build -o -name target -o -name .venv -o -name __pycache__ \) -prune \
      -o -type f -print 2>/dev/null | sed 's#^\./##' | sort -u)
  fi
  [ -n "$PATH_FILES" ] || die "no files found under the given paths (ignored files are skipped)"
elif [ "$STAGED" = 1 ]; then
  MODE=staged
elif [ "$WORKTREE" = 1 ]; then
  MODE=worktree
fi

IS_GIT=0
if ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  IS_GIT=1
  cd "$ROOT" || die "cannot enter repository root"
else
  ROOT=$(pwd)
fi
case "$MODE" in
  patch|paths) ;;
  *) [ "$IS_GIT" = 1 ] || die "not a git repository: $DIR (use --diff-file or --paths outside a repository)" ;;
esac

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

MB=
HEAD_SHA=
if [ "$MODE" = range ]; then
  if [ -n "$COMMIT" ]; then
    HEAD_SHA=$(g rev-parse -q --verify "$COMMIT^{commit}" 2>/dev/null) || die "commit not found: $COMMIT"
    if MB=$(g rev-parse -q --verify "$HEAD_SHA^" 2>/dev/null); then :; else MB=$(g hash-object -t tree /dev/null); fi
    BASE="$COMMIT^"; HEAD_REF=$COMMIT; HEAD_EXPLICIT=1
  elif [ -n "$RANGE" ]; then
    three=0
    case "$RANGE" in
      *...*) ra=${RANGE%%...*}; rb=${RANGE#*...}; three=1 ;;
      *..*) ra=${RANGE%%..*}; rb=${RANGE#*..} ;;
      *) die "--range needs A..B or A...B" ;;
    esac
    [ -n "$ra" ] || die "--range needs a start revision"
    [ -n "$rb" ] || rb=HEAD
    HEAD_SHA=$(g rev-parse -q --verify "$rb^{commit}" 2>/dev/null) || die "revision not found: $rb"
    if [ "$three" = 1 ]; then
      MB=$(g merge-base "$ra" "$rb" 2>/dev/null) || die "no merge base between $ra and $rb"
    else
      MB=$(g rev-parse -q --verify "$ra^{commit}" 2>/dev/null) || die "revision not found: $ra"
    fi
    BASE=$ra; HEAD_REF=$rb; HEAD_EXPLICIT=1
  else
    if [ -z "$BASE" ]; then
      BASE=$(detect_base) || die "cannot determine a base ref; pass --base <ref>"
    fi
    g rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || die "base ref not found: $BASE"
    HEAD_SHA=$(g rev-parse -q --verify "$HEAD_REF^{commit}" 2>/dev/null) || die "head ref not found: $HEAD_REF"
    MB=$(g merge-base "$BASE" "$HEAD_REF" 2>/dev/null) || die "no merge base between $BASE and $HEAD_REF; pass an explicit --base"
  fi
elif [ "$MODE" = staged ] || [ "$MODE" = worktree ]; then
  g rev-parse -q --verify 'HEAD^{commit}' >/dev/null 2>&1 || die "repository has no commits yet"
fi

# gdiff <git diff options and pathspec>: run git diff over the selected range.
gdiff() {
  case "$MODE" in
    staged) g diff --cached "$@" ;;
    worktree) g diff HEAD "$@" ;;
    *)
      if [ "$HEAD_EXPLICIT" = 1 ]; then g diff "$MB" "$HEAD_SHA" "$@"; else g diff "$MB" "$@"; fi ;;
  esac
}

# ---------------------------------------------------------------- helpers ---

nlines() { if [ -z "$1" ]; then echo 0; else printf '%s' "$1" | grep -c ''; fi; }

# add <list-name> <path>: append to the newline-separated list variable L_<name>
add() {
  local var="L_$1" cur
  cur=${!var-}
  printf -v "$var" '%s%s\n' "$cur" "$2"
}

# sample <list> [n]: first n entries on one line, then a remainder count
sample() {
  local list=$1 max=${2:-5} n=0 total out='' line
  total=$(nlines "$list")
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    [ "$n" -le "$max" ] || break
    if [ -z "$out" ]; then out=$line; else out="$out, $line"; fi
  done <<EOF
$list
EOF
  if [ "$total" -gt "$max" ]; then out="$out (+$((total - max)) more)"; fi
  printf '%s' "$out"
}

# norm_path: turn numstat rename notation into the new path
norm_path() {
  local p=$1 pre mid post
  case "$p" in
    *"{"*" => "*"}"*)
      pre=${p%%\{*}; mid=${p#*\{}; post=${mid#*\}}; mid=${mid%%\}*}; mid=${mid#* => }
      p="$pre$mid$post"; p=${p//\/\//\/} ;;
    *" => "*) p=${p#* => } ;;
  esac
  printf '%s' "$p"
}

# ------------------------------------------------------- path classifiers ---

RE_LOCK='(^|/)(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|cargo\.lock|go\.sum|go\.work\.sum|poetry\.lock|pipfile\.lock|uv\.lock|pdm\.lock|gemfile\.lock|composer\.lock|packages\.lock\.json|gradle\.lockfile|flake\.lock|mix\.lock|pubspec\.lock|podfile\.lock|package\.resolved|\.terraform\.lock\.hcl)$'
RE_VENDOR='(^|/)(vendor|node_modules|third_party|third-party|bower_components)/'
RE_GEN='(^|/)(__generated__|generated|\.next|\.nuxt)/|\.min\.(js|css)$|\.bundle\.js$|\.map$|\.pb\.(go|cc|h)$|_pb2(_grpc)?\.pyi?$|\.g\.dart$|\.freezed\.dart$|\.generated\.[a-z]+$|\.designer\.cs$'
RE_SNAP='\.snap$|(^|/)__snapshots__/'
RE_MIG='(^|/)(migrations?|migrate|alembic|flyway|liquibase|changelogs?)/|(^|/)db/(migrate|schema|structure)|\.sql$|schema\.prisma$|(^|/)drizzle/|(^|/)schema\.(rb|graphql)$|(^|/)structure\.sql$'
RE_API='openapi|swagger|asyncapi|\.proto$|\.graphqls?$|\.gql$|\.avsc$|\.thrift$|\.wsdl$|\.xsd$|(^|/)(contracts?|schemas?|dto|dtos|api-spec|apispec)/'
RE_ROUTE='(^|/)(routes?|routers?|controllers?|handlers?|resolvers?|endpoints?|views|api|rpc|grpc|webhooks?)/'
RE_SEC='auth([^o]|$)|login|logout|signin|signup|passw|credential|secret|jwt|oidc|saml|permission|polic(y|ies)|crypt|hmac|csrf|cors|sanitiz|guard|keystore|certificate|tenant|payment|billing|checkout|invoice|payout|wallet|upload|webhook|(^|/)\.env|security|(^|[^a-z])(sso|mfa|totp|rbac|acl|iam|sessions?|tokens?)([^a-z]|$)'
RE_INFRA='\.tf$|\.tfvars$|\.hcl$|(^|/)(terraform|infra|infrastructure|deploy|deployment|deployments|k8s|kubernetes|helm|charts|ansible|pulumi|cdk|cloudformation|manifests)/|(^|/)dockerfile|\.dockerfile$|docker-compose|(^|/)compose\.ya?ml$|\.dockerignore$|(^|/)chart\.yaml$|(^|/)values[^/]*\.ya?ml$|kustomization\.ya?ml$|serverless\.ya?ml$|\.nomad$|(^|/)procfile$|nginx[^/]*\.conf$|(^|/)caddyfile$|(^|/)fly\.toml$|(^|/)render\.yaml$|(^|/)vercel\.json$|(^|/)netlify\.toml$|(^|/)wrangler\.(toml|jsonc?)$|(^|/)skaffold\.yaml$'
RE_CI='^\.github/(workflows|actions)/|^\.gitlab-ci\.yml$|^\.gitlab/ci/|^\.circleci/|(^|/)jenkinsfile|azure-pipelines|bitbucket-pipelines|^\.buildkite/|\.drone\.yml$|^\.travis\.yml$|^\.tekton/|^\.woodpecker|(^|/)cloudbuild\.ya?ml$|^\.github/dependabot\.yml$|(^|/)renovate\.json'
RE_DEPS='(^|/)(package\.json|requirements[^/]*\.(txt|in)|constraints[^/]*\.txt|pyproject\.toml|setup\.py|setup\.cfg|pipfile|go\.mod|go\.work|cargo\.toml|gemfile|[^/]+\.gemspec|composer\.json|pom\.xml|build\.gradle(\.kts)?|settings\.gradle(\.kts)?|libs\.versions\.toml|[^/]+\.csproj|[^/]+\.fsproj|directory\.packages\.props|packages\.config|nuget\.config|pubspec\.yaml|mix\.exs|package\.swift|podfile|cartfile|deps\.edn|build\.sbt|conanfile\.(txt|py)|vcpkg\.json|\.tool-versions|\.nvmrc|\.node-version|\.python-version|\.ruby-version|\.npmrc|\.yarnrc(\.yml)?|pip\.conf)$'
RE_TEST='(^|/)(tests?|__tests__|specs?|e2e|integration|integration-tests?|cypress|playwright|testdata|fixtures|__mocks__|__fixtures__|mocks?)/|(_test|\.test|\.spec|_spec|\.e2e|\.cy)\.[a-z0-9]+$|tests?\.(java|kt|cs|swift)$|(^|/)test_[^/]+\.py$|(^|/)conftest\.py$'
RE_DOCS='\.(md|mdx|rst|adoc|txt)$|(^|/)docs?/|(^|/)(readme|changelog|contributing|license|notice|authors)'
RE_FE='\.(tsx|jsx|vue|svelte|astro|css|scss|sass|less|styl|html?|hbs|ejs|erb|twig|njk|liquid)$|(^|/)(components|pages|hooks|styles|layouts|screens|widgets)/'
RE_JOBS='worker|(^|/)jobs?/|queue|consumer|producer|subscriber|publisher|schedul|(^|/)tasks?/|celery|sidekiq|resque|bullmq|kafka|pubsub|rabbitmq|temporal|airflow|(^|/)dags?/|(^|[^a-z])(cron|sqs|outbox|sagas?)([^a-z]|$)'
RE_OBS='(^|/)(logging|logger|metrics|telemetry|tracing|observability|monitoring|alerts?|dashboards?)(/|\.|$)|otel|opentelemetry|sentry|datadog|prometheus|grafana|newrelic|honeycomb'
RE_LLM='(^|/)prompts?/|\.prompt(\.[a-z]+)?$|(^|/)llm|openai|anthropic|langchain|langgraph|llamaindex|embedding|(^|/)rag/|(^|/)evals?/'
RE_RULES='(^|/)(agents\.md|agents\.override\.md|claude\.md|gemini\.md|review\.md|\.review-rules\.md|bugbot\.md|\.cursorrules|\.windsurfrules|\.clinerules|approval_policy\.md|codeowners|contributing\.md|\.coderabbit\.ya?ml|greptile\.json|\.pr_agent\.toml)$|(^|/)\.(cursor|claude|windsurf|github/instructions|github/skills|coderabbit|greptile|gemini|continue|macroscope|factory|kiro|amazonq)/|(^|/)\.github/copilot-instructions\.md$|(^|/)\.gitlab/duo/|(^|/)skills/[^/]+/skill\.md$|(^|/)\.(opencode|codex|agents|roo|junie)/'
RE_CONFIG='\.(ya?ml|toml|ini|json|jsonc|properties|conf|cfg|env|xml|plist)$|(^|/)\.env[^/]*$|(^|/)(config|settings|conf)/'
RE_SRC='\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte|py|pyi|go|rs|java|kt|kts|scala|cs|fs|rb|php|c|h|cc|cpp|cxx|hpp|hh|m|mm|swift|dart|ex|exs|erl|clj|lua|pl|r|sql|sh|bash|zsh|ps1|groovy|zig|nim|hs|ml)$'

# -------------------------------------------------------------- gather ---

shopt -s nocasematch

# parse_patch: read a unified diff on stdin. Prints one "#F<TAB>status<TAB>added
# <TAB>deleted<TAB>path[<TAB>newpath]" line per file, one "#H" line per hunk, and
# the added and removed lines of reviewable files unchanged.
parse_patch() {
  local line path='' old='' st=M a=0 d=0 ro=0 rn=0 noise=0 have=0 bin=0 plus=0 rfrom='' hdr op np
  pflush() {
    if [ "$have" = 1 ] && [ -n "$path" ]; then
      if [ "$bin" = 1 ]; then a=-; d=-; fi
      if [ "$st" = R ] && [ -n "$rfrom" ]; then
        printf '#F\t%s\t%s\t%s\t%s\t%s\n' "$st" "$a" "$d" "$rfrom" "$path"
      else
        if [ "$st" = R ]; then st=M; fi
        printf '#F\t%s\t%s\t%s\t%s\n' "$st" "$a" "$d" "$path"
      fi
    fi
    path=''; old=''; st=M; a=0; d=0; ro=0; rn=0; noise=0; have=0; bin=0; plus=0; rfrom=''
  }
  setnoise() {
    noise=0
    if [[ $path =~ $RE_LOCK ]] || [[ $path =~ $RE_VENDOR ]] || [[ $path =~ $RE_SNAP ]] || [[ $path =~ $RE_GEN ]]; then noise=1; fi
  }
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [ "$ro" -gt 0 ] || [ "$rn" -gt 0 ]; then
      case "$line" in
        '+'*) rn=$((rn - 1)); a=$((a + 1)); if [ "$noise" = 0 ]; then printf '%s\n' "$line"; fi ;;
        '-'*) ro=$((ro - 1)); d=$((d + 1)); if [ "$noise" = 0 ]; then printf '%s\n' "$line"; fi ;;
        \\*) ;;
        *) ro=$((ro - 1)); rn=$((rn - 1)) ;;
      esac
      continue
    fi
    case "$line" in
      'diff --git '*)
        pflush; have=1
        case "$line" in 'diff --git a/'*' b/'*) path=${line##* b/}; setnoise ;; esac ;;
      'new file mode'*) st=A ;;
      'deleted file mode'*) st=D ;;
      'rename from '*) rfrom=${line#rename from } ;;
      'rename to '*) st=R; path=${line#rename to }; setnoise ;;
      'Binary files '*|'GIT binary patch'*) bin=1 ;;
      '--- '*)
        if [ "$have" = 0 ] || [ "$plus" = 1 ]; then pflush; have=1; fi
        old=${line#--- }; old=${old%%$'\t'*}
        case "$old" in /dev/null) st=A; old='' ;; a/*) old=${old#a/} ;; esac ;;
      '+++ '*)
        np=${line#+++ }; np=${np%%$'\t'*}; plus=1
        case "$np" in
          /dev/null) st=D; if [ -z "$path" ]; then path=$old; fi ;;
          b/*) path=${np#b/} ;;
          *) if [ -z "$path" ]; then path=$np; fi ;;
        esac
        setnoise ;;
      '@@ '*)
        hdr=${line#@@ -}; op=${hdr%% *}; np=${hdr#* +}; np=${np%% *}
        case "$op" in *,*) ro=${op#*,} ;; *) ro=1 ;; esac
        case "$np" in *,*) rn=${np#*,} ;; *) rn=1 ;; esac
        case "$ro" in ''|*[!0-9]*) ro=0 ;; esac
        case "$rn" in ''|*[!0-9]*) rn=0 ;; esac
        if [ "$noise" = 0 ]; then printf '#H\n'; fi ;;
    esac
  done
  pflush
}

STATUS=
NUMSTAT=
UNTRACKED=
PARSED=
PATCH_TRUNCATED=0
PATHS_TRUNCATED=0
case "$MODE" in
  patch)
    if [ "$(printf '%s\n' "$RAW" | grep -c '')" -gt "$MAX_PATCH_LINES" ]; then PATCH_TRUNCATED=1; fi
    PARSED=$(printf '%s\n' "$RAW" | head -n "$MAX_PATCH_LINES" | parse_patch)
    RAW=
    while IFS=$'\t' read -r tag st a d p1 p2; do
      [ "$tag" = "#F" ] || continue
      if [ -n "${p2:-}" ]; then
        STATUS="$STATUS$st"$'\t'"$p1"$'\t'"$p2"$'\n'
        NUMSTAT="$NUMSTAT$a"$'\t'"$d"$'\t'"$p2"$'\n'
      else
        STATUS="$STATUS$st"$'\t'"$p1"$'\n'
        NUMSTAT="$NUMSTAT$a"$'\t'"$d"$'\t'"$p1"$'\n'
      fi
    done <<EOF
$(printf '%s\n' "$PARSED" | grep '^#F')
EOF
    ;;
  paths)
    if [ "$(nlines "$PATH_FILES")" -gt "$MAX_PATH_FILES" ]; then
      PATHS_TRUNCATED=1
      PATH_FILES=$(printf '%s\n' "$PATH_FILES" | head -n "$MAX_PATH_FILES")
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      STATUS="${STATUS}M"$'\t'"$f"$'\n'
      if [ ! -s "$f" ]; then
        NUMSTAT="${NUMSTAT}0"$'\t'"0"$'\t'"$f"$'\n'
      elif grep -Iq '' -- "$f" 2>/dev/null; then
        NUMSTAT="$NUMSTAT$(grep -c '' -- "$f" 2>/dev/null)"$'\t'"0"$'\t'"$f"$'\n'
      else
        NUMSTAT="${NUMSTAT}-"$'\t'"-"$'\t'"$f"$'\n'
      fi
    done <<EOF
$PATH_FILES
EOF
    ;;
  *)
    STATUS=$(gdiff --name-status -M) || die "git diff failed"
    NUMSTAT=$(gdiff --numstat -M)
    if [ "$MODE" = worktree ] || { [ "$MODE" = range ] && [ "$HEAD_EXPLICIT" = 0 ]; }; then
      UNTRACKED=$(g ls-files --others --exclude-standard 2>/dev/null)
    fi
    ;;
esac

MB_SHORT=
if [ -n "$MB" ]; then MB_SHORT=$(g rev-parse --short "$MB" 2>/dev/null) || MB_SHORT=${MB:0:8}; fi

if [ -z "$STATUS" ] && [ -z "$UNTRACKED" ]; then
  printf 'diff-triage v1\n'
  printf 'mode: %s\n' "$MODE"
  if [ -n "$MB" ]; then printf 'base: %s  merge-base: %s  head: %s\n' "$BASE" "$MB_SHORT" "$HEAD_REF"; fi
  printf 'size: files=0\ntier: none\nwhy: empty diff, nothing to review\n'
  exit 0
fi

ALLPATHS=
N_ADDED=0; N_MODIFIED=0; N_DELETED=0; N_RENAMED=0
DELETED_LIST=
ADDED_LIST=
while IFS=$'\t' read -r st p1 p2; do
  [ -n "$st" ] || continue
  case "$st" in
    A*) N_ADDED=$((N_ADDED + 1)); ALLPATHS="$ALLPATHS$p1"$'\n'; ADDED_LIST="$ADDED_LIST$p1"$'\n' ;;
    D*) N_DELETED=$((N_DELETED + 1)); ALLPATHS="$ALLPATHS$p1"$'\n'; DELETED_LIST="$DELETED_LIST$p1"$'\n' ;;
    R*|C*) N_RENAMED=$((N_RENAMED + 1)); ALLPATHS="$ALLPATHS$p2"$'\n' ;;
    *) N_MODIFIED=$((N_MODIFIED + 1)); ALLPATHS="$ALLPATHS$p1"$'\n' ;;
  esac
done <<EOF
$STATUS
EOF
N_UNTRACKED=0
if [ -n "$UNTRACKED" ]; then
  N_UNTRACKED=$(nlines "$UNTRACKED")
  ALLPATHS="$ALLPATHS$UNTRACKED"$'\n'
  ADDED_LIST="$ADDED_LIST$UNTRACKED"$'\n'
fi

GENATTR=
if [ "$IS_GIT" = 1 ]; then
  GENATTR=$(printf '%s' "$ALLPATHS" | g check-attr --stdin linguist-generated 2>/dev/null \
    | grep -E ': linguist-generated: (true|set)$' | sed -E 's/: linguist-generated: (true|set)$//')
fi
is_genattr() {
  [ -n "$GENATTR" ] || return 1
  case $'\n'"$GENATTR"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

L_sec=; L_mig=; L_api=; L_route=; L_infra=; L_ci=; L_deps=; L_test=; L_docs=; L_fe=
L_jobs=; L_obs=; L_llm=; L_rules=; L_config=; L_src=; L_noise=; L_testdel=
N_LOCK=0; N_GEN=0; N_VENDOR=0; N_SNAP=0
LANGS=
TOPDIRS=

note_lang() { LANGS="$LANGS$1"$'\n'; }

classify() {
  local p=$1 noise=0 top
  if [[ $p =~ $RE_LOCK ]]; then N_LOCK=$((N_LOCK + 1)); noise=1; add deps "$p"
  elif [[ $p =~ $RE_VENDOR ]]; then N_VENDOR=$((N_VENDOR + 1)); noise=1; add deps "$p"
  elif [[ $p =~ $RE_SNAP ]]; then N_SNAP=$((N_SNAP + 1)); noise=1; add test "$p"
  elif [[ $p =~ $RE_GEN ]] || is_genattr "$p"; then N_GEN=$((N_GEN + 1)); noise=1
  fi
  if [ "$noise" = 1 ]; then add noise "$p"; return 0; fi

  case "$p" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.vue|*.svelte|*.astro) note_lang ts-js ;;
    *.py|*.pyi) note_lang python ;;
    *.go) note_lang go ;;
    *.rs) note_lang rust ;;
    *.java|*.kt|*.kts) note_lang java-kotlin ;;
    *.cs|*.csx|*.cshtml|*.razor) note_lang csharp ;;
    *.rb|*.rake|*.erb|*.gemspec) note_lang ruby ;;
    *.php) note_lang php ;;
    *.c|*.h|*.cc|*.cpp|*.cxx|*.hpp|*.hh) note_lang c-cpp ;;
    *.sql) note_lang sql ;;
    *.sh|*.bash|*.zsh) note_lang shell ;;
  esac

  if [[ $p =~ $RE_RULES ]]; then add rules "$p"; return 0; fi
  if [[ $p =~ $RE_CI ]]; then add ci "$p"
  elif [[ $p =~ $RE_INFRA ]]; then add infra "$p"; fi
  if [[ $p =~ $RE_DEPS ]]; then add deps "$p"; fi
  if [[ $p =~ $RE_TEST ]]; then add test "$p"; return 0; fi
  if [[ $p =~ $RE_MIG ]]; then add mig "$p"; fi
  if [[ $p =~ $RE_API ]]; then add api "$p"; fi
  if [[ $p =~ $RE_DOCS ]] && ! [[ $p =~ $RE_SRC ]]; then add docs "$p"; return 0; fi
  if [[ $p =~ $RE_ROUTE ]]; then add route "$p"; fi
  if [[ $p =~ $RE_SEC ]]; then add sec "$p"; fi
  if [[ $p =~ $RE_FE ]]; then add fe "$p"; fi
  if [[ $p =~ $RE_JOBS ]]; then add jobs "$p"; fi
  if [[ $p =~ $RE_OBS ]]; then add obs "$p"; fi
  if [[ $p =~ $RE_LLM ]]; then add llm "$p"; fi
  if [[ $p =~ $RE_SRC ]]; then
    add src "$p"
    case "$p" in */*) top=${p%%/*} ;; *) top=. ;; esac
    TOPDIRS="$TOPDIRS$top"$'\n'
  elif [[ $p =~ $RE_CONFIG ]] && ! [[ $p =~ $RE_DEPS ]] && ! [[ $p =~ $RE_CI ]]; then add config "$p"
  fi
  return 0
}

while IFS= read -r p; do
  [ -n "$p" ] || continue
  classify "$p"
done <<EOF
$ALLPATHS
EOF

while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [[ $p =~ $RE_TEST ]]; then add testdel "$p"; fi
done <<EOF
$DELETED_LIST
EOF

# ---------------------------------------------------------------- sizes ---

TOT_ADD=0; TOT_DEL=0; REV_ADD=0; REV_DEL=0; N_BIN=0
HOT=
while IFS=$'\t' read -r a d rawp; do
  [ -n "$rawp" ] || continue
  p=$(norm_path "$rawp")
  if [ "$a" = "-" ]; then N_BIN=$((N_BIN + 1)); continue; fi
  TOT_ADD=$((TOT_ADD + a)); TOT_DEL=$((TOT_DEL + d))
  case $'\n'"$L_noise" in
    *$'\n'"$p"$'\n'*) ;;
    *) REV_ADD=$((REV_ADD + a)); REV_DEL=$((REV_DEL + d)); HOT="$HOT$((a + d))"$'\t'"$p"$'\n' ;;
  esac
done <<EOF
$NUMSTAT
EOF
N_FILES=$(nlines "$ALLPATHS")
N_NOISE=$(nlines "$L_noise")
REV_FILES=$((N_FILES - N_NOISE))
REV_LINES=$((REV_ADD + REV_DEL))
N_TOPDIRS=0
if [ -n "$TOPDIRS" ]; then N_TOPDIRS=$(printf '%s' "$TOPDIRS" | sort -u | grep -c ''); fi

# ------------------------------------------------------ content signals ---

EXCL=(':!*package-lock.json' ':!*yarn.lock' ':!*pnpm-lock.yaml' ':!*.lock' ':!*go.sum' \
  ':!*.min.js' ':!*.min.css' ':!*.map' ':!*.snap' ':!*node_modules/*' ':!*vendor/*' ':!*third_party/*')

# cat_reviewable: contents of the text files chosen with --paths, minus noise files
cat_reviewable() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case $'\n'"$L_noise" in *$'\n'"$f"$'\n'*) continue ;; esac
    if grep -Iq '' -- "$f" 2>/dev/null; then cat -- "$f" 2>/dev/null; fi
  done <<EOF
$PATH_FILES
EOF
}

SCANNED=1
PARTIAL_SCAN=0
ADDED_TXT=
REMOVED_TXT=
HUNKS=0
case "$MODE" in
  patch)
    ADDED_TXT=$(printf '%s\n' "$PARSED" | grep '^+')
    REMOVED_TXT=$(printf '%s\n' "$PARSED" | grep '^-')
    HUNKS=$(printf '%s\n' "$PARSED" | grep -c '^#H')
    PARSED=
    ;;
  paths)
    if [ "$REV_LINES" -gt "$MAX_SCAN_LINES" ]; then PARTIAL_SCAN=1; fi
    ADDED_TXT=$(cat_reviewable | head -n "$MAX_SCAN_LINES")
    ;;
  *)
    if [ "$((TOT_ADD + TOT_DEL))" -gt "$MAX_SCAN_LINES" ]; then
      SCANNED=0
    else
      PATCH=$(gdiff -U0 -M -- . "${EXCL[@]}" 2>/dev/null)
      ADDED_TXT=$(printf '%s\n' "$PATCH" | grep -E '^\+' | grep -vE '^\+\+\+ ')
      REMOVED_TXT=$(printf '%s\n' "$PATCH" | grep -E '^-' | grep -vE '^--- ')
      HUNKS=$(printf '%s\n' "$PATCH" | grep -cE '^@@ ')
      PATCH=
    fi
    ;;
esac

cadd() { if [ -z "$ADDED_TXT" ]; then echo 0; else printf '%s\n' "$ADDED_TXT" | grep -ciE -- "$1"; fi; }
crem() { if [ -z "$REMOVED_TXT" ]; then echo 0; else printf '%s\n' "$REMOVED_TXT" | grep -ciE -- "$1"; fi; }

S_SECRET=0; S_SINK=0; S_CONC=0; S_ERR=0; S_PERF=0; S_OBS=0; S_LLM=0
S_TESTREM=0; S_SKIP=0; S_SUPP=0; S_DEBUG=0; S_HIDDEN=0; S_GUARDREM=0
if [ "$SCANNED" = 1 ]; then
  S_SECRET=$(cadd '(passw(or)?d|secret|api[_-]?key|access[_-]?key|private[_-]?key|auth[_-]?token|client[_-]?secret)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'$<{ ]{8,}|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}')
  # shellcheck disable=SC2016
  S_SINK=$(cadd 'eval\(|exec\(|child_process|shell[[:space:]]*=[[:space:]]*true|os\.system|subprocess\.|innerHTML|dangerouslySetInnerHTML|v-html|pickle\.loads?|yaml\.load\(|ObjectInputStream|unserialize\(|md5\(|sha1\(|verify[[:space:]]*=[[:space:]]*false|rejectUnauthorized|InsecureSkipVerify|Access-Control-Allow-Origin|jwt\.|bcrypt|argon2|createHmac|createCipher|csrf|authoriz|authenticat|permission|sanitiz|\$where|raw\(|\.query\(.*(\+|\$\{)|execute\(.*(%|\+|format\()|trustProxy|chmod 777|0\.0\.0\.0')
  S_CONC=$(cadd 'mutex|rwlock|\.lock\(|synchronized|semaphore|atomic|volatile|go func|chan |sync\.|waitgroup|errgroup|Promise\.(all|race|allSettled|any)|setInterval|asyncio\.(gather|create_task|lock|wait)|threading\.|Thread\(|ExecutorService|CompletableFuture|GlobalScope|runBlocking|tokio::|spawn\(|Arc<|transaction|for update|skip locked|isolation|retry|retries|backoff|idempot|debounce|dedup|enqueue|publish\(|subscribe\(|setTimeout\(')
  S_ERR=$(cadd 'catch[[:space:]]*(\(|\{)|except[[:space:]:]|rescue|recover\(\)|\.catch\(|unwrap\(\)|panic!?\(|on_?error|finally|errors\.(is|as)\(|if err != nil')
  S_PERF=$(cadd 'select |insert into|update .* set|delete from| join |\.find(all|many|one|first|unique)?\(|\.where\(|\.aggregate\(|createQueryBuilder|prefetch_related|select_related|\.includes\(|joinedload|selectinload|\.objects\.|\.all\(\)|cache|memoiz| limit | offset |paginat|\.sort\(|order by|create index|readFileSync|\.read\(\)')
  S_OBS=$(cadd 'metrics?\.|counter|histogram|gauge|\.observe\(|span|tracer|otel|opentelemetry|sentry|statsd|prometheus|datadog|alert|slo|logger\.(error|warn|fatal|exception)|log\.(error|warn|fatal)')
  S_LLM=$(cadd 'openai|anthropic|langchain|langgraph|llamaindex|bedrock|vertexai|generateContent|chat\.completions|messages\.create|system[_ ]prompt|max_tokens|temperature|embedding|tool_use|function_call')
  S_TESTREM=$(crem 'assert|expect\(|should[. (]|^-[[:space:]]*(it|test|describe|context)\(|def test_|@Test|func Test|#\[test\]|\[Fact\]|\[Test\]')
  S_SKIP=$(cadd '\.skip\(|xit\(|xdescribe\(|xtest\(|@Ignore|@Disabled|pytest\.mark\.(skip|xfail)|t\.Skip\(|#\[ignore\]|\.only\(|skipTest|unittest\.skip|\.todo\(|pending\(')
  S_SUPP=$(cadd 'eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck|# noqa|# type: ignore|pylint: disable|//[[:space:]]*nolint|#\[allow\(|@SuppressWarnings|NOLINT|rubocop:disable|phpcs:ignore|@phpstan-ignore|# nosec|nosemgrep|as any|as unknown as|pragma: no cover|istanbul ignore|coverage: ignore')
  S_DEBUG=$(cadd 'console\.log\(|debugger;|binding\.pry|byebug|pdb\.set_trace|breakpoint\(\)|dbg!\(|fmt\.Println\(|System\.out\.println|var_dump\(|print_r\(|[^a-z]dd\(|TODO|FIXME|XXX|HACK')
  S_GUARDREM=$(crem 'authoriz|authenticat|permission|isAdmin|require(Auth|Role|Login)|csrf|validate|sanitiz|escape|verify|check[A-Z_]|assert|throw |raise |return .*(401|403|forbidden|unauthorized)|rate.?limit|timeout|retry|lock|transaction|if err != nil')
  if [ -n "$ADDED_TXT" ]; then
    # zero-width space, word joiner, bidi embeddings/overrides/isolates, Unicode tag characters
    S_HIDDEN=$(printf '%s\n' "$ADDED_TXT" | LC_ALL=C grep -c -e $'\xe2\x80\x8b' -e $'\xe2\x81\xa0' \
      -e $'\xe2\x80\xaa' -e $'\xe2\x80\xab' -e $'\xe2\x80\xac' -e $'\xe2\x80\xad' -e $'\xe2\x80\xae' \
      -e $'\xe2\x81\xa6' -e $'\xe2\x81\xa7' -e $'\xe2\x81\xa8' -e $'\xe2\x81\xa9' \
      -e $'\xf3\xa0\x80' -e $'\xf3\xa0\x81')
  fi
fi
ADDED_TXT=; REMOVED_TXT=

# ----------------------------------------------------------------- tier ---

C_sec=$(nlines "$L_sec"); C_mig=$(nlines "$L_mig"); C_api=$(nlines "$L_api"); C_route=$(nlines "$L_route")
C_infra=$(nlines "$L_infra"); C_ci=$(nlines "$L_ci"); C_deps=$(nlines "$L_deps"); C_test=$(nlines "$L_test")
C_docs=$(nlines "$L_docs"); C_fe=$(nlines "$L_fe"); C_jobs=$(nlines "$L_jobs"); C_obs=$(nlines "$L_obs")
C_llm=$(nlines "$L_llm"); C_rules=$(nlines "$L_rules"); C_config=$(nlines "$L_config"); C_src=$(nlines "$L_src")
C_testdel=$(nlines "$L_testdel")

# Whole-file review reads every line, so its size thresholds are about three times the diff ones.
LIGHT_LINES=50; DEEP_LINES=400; LINE_WORD='changed lines'
if [ "$MODE" = paths ]; then LIGHT_LINES=150; DEEP_LINES=1200; LINE_WORD='lines'; fi

WHY=
why() { if [ -z "$WHY" ]; then WHY=$1; else WHY="$WHY; $1"; fi; }

DEEP=0
[ "$C_sec" -gt 0 ] && { DEEP=1; why "security-sensitive paths ($C_sec)"; }
[ "$S_SECRET" -gt 0 ] && { DEEP=1; why "possible hard-coded credential ($S_SECRET lines)"; }
[ "$C_mig" -gt 0 ] && { DEEP=1; why "schema or migration files ($C_mig)"; }
[ "$C_api" -gt 0 ] && { DEEP=1; why "API or schema contract files ($C_api)"; }
[ "$C_infra" -gt 0 ] && { DEEP=1; why "infrastructure files ($C_infra)"; }
[ "$C_ci" -gt 0 ] && { DEEP=1; why "CI or automation files ($C_ci)"; }
[ "$C_testdel" -gt 0 ] && { DEEP=1; why "test files deleted ($C_testdel)"; }
[ "$S_HIDDEN" -gt 0 ] && { DEEP=1; why "invisible or bidirectional Unicode in added lines ($S_HIDDEN)"; }
[ "$REV_LINES" -gt "$DEEP_LINES" ] && { DEEP=1; why "more than $DEEP_LINES reviewable $LINE_WORD ($REV_LINES)"; }
[ "$REV_FILES" -gt 20 ] && { DEEP=1; why "more than 20 reviewable files ($REV_FILES)"; }

TIER=standard
if [ "$DEEP" = 1 ]; then
  TIER=deep
elif [ "$C_src" -eq 0 ] && [ "$C_deps" -eq 0 ] && [ "$C_config" -eq 0 ]; then
  TIER=light; why "no source, dependency or config files changed"
elif [ "$REV_LINES" -le "$LIGHT_LINES" ] && [ "$REV_FILES" -le 5 ] && [ "$C_route" -eq 0 ] && [ "$C_jobs" -eq 0 ] \
  && [ "$C_deps" -eq 0 ] && [ "$S_CONC" -eq 0 ] && [ "$S_SINK" -eq 0 ] && [ "$S_TESTREM" -eq 0 ]; then
  TIER=light; why "small change ($REV_LINES lines, $REV_FILES files) with no risk signal"
else
  why "no forcing risk area; default depth"
fi
if [ "$SCANNED" = 0 ]; then why "content not scanned (diff larger than $MAX_SCAN_LINES lines); treat as deep"; TIER=deep; fi

# --------------------------------------------------------------- output ---

printf 'diff-triage v1\n'
case "$MODE" in
  patch)
    if [ "$DIFF_FILE" = - ]; then printf 'mode: unified diff from stdin\n'; else printf 'mode: unified diff from %s\n' "$DIFF_FILE"; fi ;;
  paths) printf 'mode: whole files, no diff (%s file(s))\n' "$N_FILES" ;;
  staged) printf 'mode: staged changes\n' ;;
  worktree) printf 'mode: uncommitted changes vs HEAD (%s)\n' "$(g rev-parse --short HEAD)" ;;
  *)
    if [ -n "$COMMIT" ]; then
      printf 'mode: commit %s (%s) against its parent (%s)\n' "$COMMIT" "$(g rev-parse --short "$HEAD_SHA")" "$MB_SHORT"
    elif [ -n "$RANGE" ]; then
      printf 'mode: range %s  from: %s  to: %s\n' "$RANGE" "$MB_SHORT" "$(g rev-parse --short "$HEAD_SHA")"
    elif [ "$HEAD_EXPLICIT" = 1 ]; then
      printf 'mode: range  base: %s  merge-base: %s  head: %s (%s)\n' "$BASE" "$MB_SHORT" "$HEAD_REF" "$(g rev-parse --short "$HEAD_SHA")"
    else
      printf 'mode: range  base: %s  merge-base: %s  head: %s (%s) plus working tree\n' "$BASE" "$MB_SHORT" "$HEAD_REF" "$(g rev-parse --short "$HEAD_SHA")"
    fi ;;
esac
if [ "$MODE" = paths ]; then
  printf 'size: files=%s lines=%s\n' "$N_FILES" "$TOT_ADD"
else
  printf 'size: files=%s added=%s deleted=%s hunks=%s\n' "$N_FILES" "$TOT_ADD" "$TOT_DEL" "$HUNKS"
fi
printf 'reviewable: files=%s lines=%s (excluded: lockfiles=%s generated=%s vendored=%s snapshots=%s binary=%s)\n' \
  "$REV_FILES" "$REV_LINES" "$N_LOCK" "$N_GEN" "$N_VENDOR" "$N_SNAP" "$N_BIN"
if [ "$MODE" != paths ]; then
  printf 'status: added=%s modified=%s deleted=%s renamed=%s untracked=%s source-top-dirs=%s\n' \
    "$N_ADDED" "$N_MODIFIED" "$N_DELETED" "$N_RENAMED" "$N_UNTRACKED" "$N_TOPDIRS"
fi
printf 'tier: %s\n' "$TIER"
printf 'why: %s\n' "$WHY"

printf 'areas (by path):\n'
area() { # area <label> <count> <list>
  [ "$2" -gt 0 ] || return 0
  printf '  %s (%s): %s\n' "$1" "$2" "$(sample "$3" 4)"
}
area security "$C_sec" "$L_sec"
area migrations "$C_mig" "$L_mig"
area api-contracts "$C_api" "$L_api"
area request-handlers "$C_route" "$L_route"
area infra "$C_infra" "$L_infra"
area ci "$C_ci" "$L_ci"
area dependencies "$C_deps" "$L_deps"
area tests "$C_test" "$L_test"
area frontend "$C_fe" "$L_fe"
area background-jobs "$C_jobs" "$L_jobs"
area observability "$C_obs" "$L_obs"
area llm "$C_llm" "$L_llm"
area docs "$C_docs" "$L_docs"
area config "$C_config" "$L_config"
area rule-files "$C_rules" "$L_rules"
area tests-deleted "$C_testdel" "$L_testdel"

if [ "$MODE" = paths ]; then
  printf 'signals (by file content; counts are matching lines):\n'
else
  printf 'signals (by added or removed lines; counts are matching lines):\n'
fi
sig() { [ "$2" -gt 0 ] && printf '  %s: %s\n' "$1" "$2"; return 0; }
if [ "$SCANNED" = 1 ]; then
  sig possible-secret "$S_SECRET"
  sig security-sinks-or-auth "$S_SINK"
  sig concurrency-retries-transactions "$S_CONC"
  sig error-handling "$S_ERR"
  sig queries-caches-loops "$S_PERF"
  sig telemetry "$S_OBS"
  sig llm-calls "$S_LLM"
  sig removed-assertions-or-tests "$S_TESTREM"
  sig tests-skipped-or-focused "$S_SKIP"
  sig removed-guard-like-lines "$S_GUARDREM"
  sig suppressions "$S_SUPP"
  sig debug-or-todo-leftovers "$S_DEBUG"
  sig hidden-unicode "$S_HIDDEN"
  if [ "$((S_SECRET + S_SINK + S_CONC + S_ERR + S_PERF + S_OBS + S_LLM + S_TESTREM + S_SKIP + S_GUARDREM + S_SUPP + S_DEBUG + S_HIDDEN))" -eq 0 ]; then
    printf '  (none)\n'
  fi
else
  printf '  (skipped: diff too large to scan)\n'
fi

if [ -n "$LANGS" ]; then
  printf 'languages:'
  printf '%s' "$LANGS" | sort | uniq -c | sort -rn | while read -r n l; do printf ' %s(%s)' "$l" "$n"; done
  printf '\n'
fi

if [ -n "$HOT" ]; then
  printf 'largest reviewable files (%s):\n' "$LINE_WORD"
  printf '%s' "$HOT" | sort -rn | head -8 | while IFS=$'\t' read -r n p; do printf '  %5s  %s\n' "$n" "$p"; done
fi

# Path matches go under "load". Keyword counts go under "load" only when they are
# dense in a diff; in whole-file mode they scale with file size, so they only "consider".
KW=load
if [ "$MODE" = paths ]; then KW=consider; fi
LOAD=
CONSIDER=
CHOSEN=
pick() { # pick <load|consider> <file> <reason>
  case " $CHOSEN " in *" $2 "*) return 0 ;; esac
  CHOSEN="$CHOSEN $2"
  if [ "$1" = load ]; then
    LOAD="${LOAD}  references/$2.md  # $3"$'\n'
  else
    CONSIDER="${CONSIDER}  references/$2.md  # $3"$'\n'
  fi
}
if [ "$C_rules" -gt 0 ] || [ "$S_HIDDEN" -gt 0 ]; then pick load prompt-injection-defense "rule files changed or hidden Unicode added"; fi
if [ "$C_sec" -gt 0 ] || [ "$S_SECRET" -gt 0 ]; then pick load security "sensitive paths or a possible credential"; fi
if [ "$S_SINK" -ge 3 ]; then pick "$KW" security "security sinks or auth keywords"; fi
if [ "$C_mig" -gt 0 ]; then pick load data-migrations-compat "schema or migration files"; fi
if [ "$C_api" -gt 0 ]; then pick load api-contracts "contract or schema files"; fi
if [ "$C_jobs" -gt 0 ]; then pick load reliability-concurrency "background jobs, queues or schedulers"; fi
if [ "$S_CONC" -ge 3 ]; then pick "$KW" reliability-concurrency "concurrency, retries or transactions"; fi
if [ "$C_infra" -gt 0 ] || [ "$C_ci" -gt 0 ]; then pick load infra-iac-ci "infrastructure or CI files"; fi
if [ "$C_deps" -gt 0 ]; then pick load dependencies-supply-chain "manifests, lockfiles or vendored code"; fi
if [ "$C_llm" -gt 0 ]; then pick load llm-integration-code "prompt or model-integration files"; fi
if [ "$S_LLM" -ge 2 ]; then pick "$KW" llm-integration-code "model calls"; fi
if [ "$C_src" -gt 0 ] && [ "$TIER" != light ]; then pick load correctness-and-logic "source logic"; fi
if [ "$C_test" -gt 0 ] || [ "$S_TESTREM" -gt 0 ] || [ "$S_SKIP" -gt 0 ] || [ "$C_testdel" -gt 0 ]; then pick load tests "test files, or tests removed or skipped"; fi
if [ "$C_fe" -gt 0 ]; then pick load frontend-a11y "UI files"; fi
if [ "$C_docs" -gt 0 ] && [ "$((C_docs * 2))" -ge "$REV_FILES" ]; then pick load docs-and-comments "documentation is the main change"; fi
if [ "$REV_LINES" -gt "$DEEP_LINES" ] || [ "$REV_FILES" -gt 20 ]; then pick load large-pr-strategy "large change"; fi
if [ "$C_mig" -gt 0 ] || [ "$C_infra" -gt 0 ] || [ "$C_api" -gt 0 ]; then pick load qa-and-rollout-plan "migration, infrastructure or contract change: ordering and rollout"; fi
if [ "$S_SINK" -gt 0 ]; then pick consider security "a few security-relevant keywords"; fi
if [ "$C_route" -gt 0 ]; then pick consider api-contracts "request handlers changed"; fi
if [ "$S_CONC" -gt 0 ] || [ "$S_ERR" -ge 2 ]; then pick consider reliability-concurrency "error handling or async keywords"; fi
if [ "$S_PERF" -ge 3 ]; then pick consider performance "queries, caches or data loops"; fi
if [ "$C_obs" -gt 0 ] || [ "$S_OBS" -ge 3 ] || [ "$C_jobs" -gt 0 ]; then pick consider observability "telemetry or background work"; fi
if [ "$N_ADDED" -ge 5 ] || [ "$N_RENAMED" -ge 5 ] || [ "$N_TOPDIRS" -ge 3 ]; then pick consider design-maintainability "new modules, moves or cross-cutting change"; fi
if [ "$S_LLM" -gt 0 ]; then pick consider llm-integration-code "model-call keywords"; fi
if [ "$C_docs" -gt 0 ]; then pick consider docs-and-comments "docs changed"; fi
if [ "$C_config" -gt 0 ] || [ "$C_jobs" -gt 0 ] || [ "$C_deps" -gt 0 ] || [ "$C_ci" -gt 0 ] || [ "$C_fe" -gt 0 ]; then pick consider qa-and-rollout-plan "may need manual verification or a rollout note"; fi

LANG_REFS=
if [ -n "$LANGS" ]; then
  LANG_REFS=$(printf '%s' "$LANGS" | sort | uniq -c | sort -rn | head -2 | while read -r n l; do
    printf '  references/lang-%s.md  # %s file(s)\n' "$l" "$n"
  done)
fi
# At the light tier a language file is optional reading.
if [ "$TIER" = light ] && [ -n "$LANG_REFS" ]; then
  CONSIDER="$CONSIDER$LANG_REFS"$'\n'
  LANG_REFS=
fi
printf 'load:\n'
if [ -n "$LOAD" ]; then printf '%s' "$LOAD"; fi
if [ -n "$LANG_REFS" ]; then printf '%s\n' "$LANG_REFS"; fi
if [ -z "$LOAD" ] && [ -z "$LANG_REFS" ]; then printf '  (none: the always-on checks in SKILL.md are enough)\n'; fi
if [ -n "$CONSIDER" ]; then
  printf 'consider (weak match; open only if the change really involves it):\n%s' "$CONSIDER"
fi

NOTES=
if [ "$MODE" = range ] && [ "$HEAD_EXPLICIT" = 1 ] && [ "$HEAD_SHA" = "$(g rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" ]; then
  if [ -n "$(g status --porcelain 2>/dev/null | head -1)" ]; then
    NOTES="${NOTES}  - working tree has uncommitted changes that are not part of this range"$'\n'
  fi
fi
if [ "$MODE" = patch ]; then
  NOTES="${NOTES}  - raw diff: line numbers are those of the new file in each hunk; CI, threads and related changes are unknown"$'\n'
  if [ "$IS_GIT" = 0 ]; then NOTES="${NOTES}  - not inside a repository: surrounding code and repository rules are unavailable"$'\n'; fi
  if [ "$PATCH_TRUNCATED" = 1 ]; then NOTES="${NOTES}  - diff longer than $MAX_PATCH_LINES lines: only the first part was analyzed"$'\n'; fi
fi
if [ "$MODE" = paths ]; then
  NOTES="${NOTES}  - whole-file review: everything in these files is in scope, sizes are file lines, and there is no base to compare against"$'\n'
  if [ "$PATHS_TRUNCATED" = 1 ]; then NOTES="${NOTES}  - more than $MAX_PATH_FILES files: only the first $MAX_PATH_FILES were analyzed"$'\n'; fi
  if [ "$PARTIAL_SCAN" = 1 ]; then NOTES="${NOTES}  - keyword signals cover only the first $MAX_SCAN_LINES lines"$'\n'; fi
fi
if [ "$N_UNTRACKED" -gt 0 ]; then
  NOTES="${NOTES}  - $N_UNTRACKED untracked file(s) counted by path only; their content was not scanned: $(sample "$UNTRACKED" 3)"$'\n'
fi
if [ "$C_rules" -gt 0 ]; then
  NOTES="${NOTES}  - rule or agent instruction files changed: apply their base-branch version and review the edit as a change"$'\n'
fi
if [ "$N_BIN" -gt 0 ]; then NOTES="${NOTES}  - $N_BIN binary file(s) changed; inspect what they are"$'\n'; fi
if [ "$N_NOISE" -gt 0 ]; then
  NOTES="${NOTES}  - excluded from reviewable size: $(sample "$L_noise" 3)"$'\n'
fi
if [ -n "$NOTES" ]; then printf 'notes:\n%s' "$NOTES"; fi
exit 0
