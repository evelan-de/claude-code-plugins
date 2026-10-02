#!/usr/bin/env bash
# Autopilot gate-output filter (TEMPLATE).
# Copied into a project's .claude/hooks/ by `autopilot-hooks install` (from /autopilot init and the runner).
# autopilot-hook-version: 4   (raise it with every change to this file)
#
# Entry points:
#
#   hook  (default; PreToolUse hook for Bash)
#         Reads the hook JSON on stdin. When the project is autopilot-enabled
#         (.claude/autopilot.json exists) and the command is a gate command, it rewrites the
#         command to `<this script> run <cmdfile>`. The cmdfile is a `# CWD: <dir>` line (the
#         caller's cwd) followed by the original command, verbatim. Everything else passes
#         through ({}).
#         A gate command is: a test/lint/typecheck/build/gate script of a package manager, a
#         runner binary (vitest, jest, tsc, eslint, ...), or the project's own `gate` or
#         `gateFull` from .claude/autopilot.json (the whole one-line string, no further
#         arguments). Each may follow environment assignments
#         (`TZ=Europe/Berlin npm run gate`), `env [-i] [-u NAME] NAME=value ...`,
#         `cross-env NAME=value ...` and `timeout N`, in any order. It has to stand at a
#         command position: text inside quotes, inside a heredoc body or behind a `#` comment
#         is never a gate command.
#
#   run <cmdfile>
#         Executes the command in the cwd of the `# CWD:` line, in the user's login shell
#         ($SHELL when it is bash or zsh, otherwise bash) with pipefail, keeps its exit status,
#         prints a filtered view (RED: failure blocks + summary, GREEN: summary only) and
#         appends one evidence line to .claude/autopilot-gate.log:
#           <utc time> head=<sha> tree=<working-tree hash> exit=<code> cmd=<command>
#         `cmd=` is the whole command that ran, line breaks written as `\n`; a run outside the
#         project root is written as `cd <dir> && <command>`.
#
#   tree
#         Prints the working-tree hash used in the log (git write-tree over a temporary
#         index with every tracked and untracked, non-ignored file added, the log itself
#         excluded). A reviewer runs
#         this and compares it with the `tree=` of the log line to know the gate ran on
#         exactly the files it is reviewing, committed or not.
#
# Bypass: put `# raw` anywhere in the command to run it unfiltered.
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG="$PROJECT_DIR/.claude/autopilot.json"
LOG="$PROJECT_DIR/.claude/autopilot-gate.log"
SELF="$PROJECT_DIR/.claude/hooks/autopilot-gate-filter.sh"
MAX_LINES="${AUTOPILOT_GATE_MAX_LINES:-200}"

# What ends a script or runner name: a blank (arguments follow), an operator, a redirect, the end.
WORD_END='([[:space:];&|)<>]|$)'
# What ends the project's own gate: an operator, a redirect or the end. Further arguments make
# it another command.
GATE_END='[[:space:]]*([;&|)<>]|[0-9]+[<>]|$)'
# Package-manager scripts: <pm> [exec|workspace X|--filter X|-r|--recursive|-w X]* [run] <script>
PM_RE='(npx|pnpm|npm|yarn|bun)( (exec|workspace [^ ]+|--filter [^ ]+|-r|--recursive|-w [^ ]+))*( run)? (test|test:[a-z0-9:_-]+|lint|lint:[a-z0-9:_-]+|typecheck|type-check|check-types|format:check|build|build:[a-z0-9:_-]+|gate|gate:[a-z0-9:_-]+)'"$WORD_END"
# Direct runner binaries (with or without npx/exec prefix)
BIN_RE='((npx|pnpm exec|npm exec|yarn|bunx) )?(vitest|jest|mocha|playwright|tsc|eslint|biome|prettier)'"$WORD_END"
# What may stand in front of a gate command: the start of a command, then any of `env` (with
# -i, -u NAME), `cross-env`, environment assignments and `timeout N`. An assignment's value is
# a run of bare characters, quoted strings and `$(...)` substitutions.
SQ="'"
NAME='[A-Za-z_][A-Za-z0-9_]*'
VALUE='("[^"]*"|'"$SQ"'[^'"$SQ"']*'"$SQ"'|\$\([^()]*\)|`[^`]*`|[^[:space:];&|()"`'"$SQ"'])*'
ASSIGN="$NAME=$VALUE"
ENV='env([[:space:]]+(-i|--ignore-environment|-u[[:space:]]+'"$NAME"'|--unset='"$NAME"'))*'
PREFIX='(^|[;&|(]|then |do )[[:space:]]*(('"$ENV"'|(npx )?cross-env)[[:space:]]+|'"$ASSIGN"'[[:space:]]+|timeout [0-9]+[smh]?[[:space:]]+)*'
FAIL_RE='FAIL|✗|×|✘|✕|●|Error|error|ERR!|AssertionError|Expected|expected|Received|received|failed|Failed|TS[0-9]{4}|not ok|✖|Timed out|timed out'

# Prints stdin as the text the patterns look at: inside quotes ('...', "...", $'...') the
# characters that would start or end a command (blank, tab, line break, ; & | ( ) and the
# other quote) become control characters, a `#` comment and a heredoc body are dropped, a
# backslash-newline joins the lines. Everything else stays as it is, so a command at a command
# position still reads as typed. With `perline`, each input line is scanned on its own.
scan() {
  awk -v perline="${1:-0}" '
    function mapped(c) {
      if (c == " ") return "\001"; if (c == "\t") return "\002"
      if (c == ";") return "\004"; if (c == "&") return "\005"; if (c == "|") return "\006"
      if (c == "(") return "\016"; if (c == ")") return "\017"
      if (c == "\"") return "\020"; if (c == "\047") return "\021"
      return c
    }
    {
      if (perline) { q = ""; nh = 0; hd = 0 }
      line = $0
      if (hd) {                                  # inside a heredoc body: dropped
        t = line; if (strip[cur]) sub(/^\t+/, "", t)
        if (t == word[cur]) { cur++; if (cur > nh) { hd = 0; nh = 0 } }
        next
      }
      out = ""; cont = 0; n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1); nx = substr(line, i + 1, 1)
        if (q == "\047") { if (c == "\047") q = ""; out = out (q == "" ? c : mapped(c)); continue }
        if (q == "$\047") {
          if (c == "\\") { out = out c mapped(nx); i++; continue }
          if (c == "\047") q = ""; out = out (q == "" ? c : mapped(c)); continue
        }
        if (q == "\"") {
          if (c == "\\" && nx != "") { out = out c mapped(nx); i++; continue }
          if (c == "\"") q = ""; out = out (q == "" ? c : mapped(c)); continue
        }
        if (c == "\\") { if (nx == "") cont = 1; else { out = out c mapped(nx); i++ }; continue }
        if (c == "\047" || c == "\"") { q = c; out = out c; continue }
        if (c == "$" && nx == "\047") { q = "$\047"; out = out c nx; i++; continue }
        if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;&|(]/)) break
        if (c == "<" && nx == "<" && substr(line, i + 2, 1) == "<") { out = out "<<<"; i += 2; continue }
        if (c == "<" && nx == "<") {                 # heredoc when a word follows (not a shift)
          j = i + 2; s = 0
          if (substr(line, j, 1) == "-") { s = 1; j++ }
          while (substr(line, j, 1) ~ /[ \t]/) j++
          if (substr(line, j, 1) !~ /[A-Za-z_"\047\\]/) { out = out "<<"; i++; continue }
          w = ""
          while (j <= n) {
            ch = substr(line, j, 1)
            if (ch ~ /[ \t;&|()<>]/) break
            if (ch == "\\") { j++; w = w substr(line, j, 1) }
            else if (ch == "\047" || ch == "\"") {
              k = index(substr(line, j + 1), ch)
              if (k == 0) { w = w substr(line, j + 1); j = n } else { w = w substr(line, j + 1, k - 1); j += k }
            } else w = w ch
            j++
          }
          if (w != "") { nh++; word[nh] = w; strip[nh] = s }
          out = out substr(line, i, j - i); i = j - 1; continue
        }
        out = out c
      }
      if (q != "") printf "%s\003", out
      else if (cont) printf "%s", out
      else { print out; if (nh > 0) { hd = 1; cur = 1 } }
    }
    END { printf "\n" }'
}

tree_hash() {
  local dir="${1:-$PROJECT_DIR}" idx
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { echo nogit; return; }
  idx="$(mktemp)"
  rm -f "$idx"
  # Seed from HEAD first: an empty index plus "add -A" skips tracked-but-gitignored files
  # (hooks and settings force-added under an ignored .claude/), so two different trees
  # would hash the same. A repo without a commit has no HEAD; then the seed is skipped.
  ( cd "$dir" \
    && { GIT_INDEX_FILE="$idx" git read-tree HEAD >/dev/null 2>&1 || true; } \
    && GIT_INDEX_FILE="$idx" git -c core.safecrlf=false add -A . >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$idx" git rm -q --cached --ignore-unmatch .claude/autopilot-gate.log >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null ) | cut -c1-12
  rm -f "$idx"
}

mode="${1:-hook}"

if [ "$mode" = "tree" ]; then
  tree_hash "$PROJECT_DIR"
  exit 0
fi

if [ "$mode" = "run" ]; then
  cmdfile="${2:-}"
  if [ -z "$cmdfile" ] || [ ! -f "$cmdfile" ]; then
    echo "autopilot-gate-filter: missing command file" >&2
    exit 1
  fi
  cwd="$(sed -n '1s/^# CWD: //p' "$cmdfile")"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    echo "autopilot-gate-filter: the command file must start with a '# CWD: <existing dir>' line" >&2
    exit 1
  fi
  tmp="$(mktemp -d)"
  raw="$tmp/raw.txt"
  script="$tmp/gate.sh"
  { printf 'cd %q || exit 1\n' "$cwd"; tail -n +2 "$cmdfile"; } >"$script"
  # The evidence names what ran: the whole command, line breaks as \n, and the cwd when it is
  # not the project root.
  orig="$(tail -n +2 "$cmdfile")"
  nl='\n'; orig="${orig//$'\n'/$nl}"; orig="${orig//$'\t'/ }"
  root="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"
  here="$(cd "$cwd" && pwd -P)"
  if [ "$here" != "$root" ]; then
    case "$here" in "$root"/*) here="${here#"$root"/}";; esac
    orig="cd $here && $orig"
  fi
  # The user's login shell when it is bash or zsh, otherwise bash (see autopilot-gate.sh).
  gate_shell=bash
  user_shell="${SHELL:-}"
  case "${user_shell##*/}" in
    bash|zsh) command -v "$user_shell" >/dev/null 2>&1 && gate_shell="$user_shell" ;;
  esac
  "$gate_shell" -l -o pipefail "$script" >"$raw" 2>&1
  rc=$?
  total="$(wc -l <"$raw" | tr -d ' ')"
  head_sha="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  tree="$(tree_hash "$PROJECT_DIR")"
  mkdir -p "$(dirname "$LOG")"
  printf '%s\thead=%s\ttree=%s\texit=%s\tcmd=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$head_sha" "$tree" "$rc" "$orig" >>"$LOG"

  if [ "$rc" -eq 0 ]; then
    echo "GATE GREEN (exit 0) · $total lines, showing summary only · full output: $raw"
    tail -n 12 "$raw"
  else
    echo "GATE RED (exit $rc) · $total lines, showing failures + summary · full output: $raw"
    echo "--- failures ---"
    grep -n -E -B2 -A8 "$FAIL_RE" "$raw" | head -n "$MAX_LINES"
    echo "--- summary (tail) ---"
    tail -n 15 "$raw"
  fi
  exit "$rc"
fi

# ---- hook mode -------------------------------------------------------------------------
input="$(cat 2>/dev/null || true)"

[ -f "$CONFIG" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || { echo '{}'; exit 0; }

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || { echo '{}'; exit 0; }

case "$cmd" in
  *"# raw"*|*autopilot-gate-filter*|*autopilot-gate.sh*) echo '{}'; exit 0;;
esac

# The project's own gate commands (`gate`, `gateFull` in autopilot.json), scanned like the
# command, as one ERE alternation of literal strings, each trimmed; nothing when neither is a
# one-line string.
project_gates_re() {
  jq -r '[.gate, .gateFull][] | select(type == "string") | gsub("^\\s+|\\s+$"; "")
         | select(length > 0 and (test("\n") | not))' "$CONFIG" 2>/dev/null \
    | scan 1 | sed -e '/^$/d' -e 's/[][(){}.*+?^$|\\]/\\&/g' | paste -s -d '|' -
}

scanned="$(printf '%s\n' "$cmd" | scan)"
# $1 an ERE for what follows the prefix: true when the scanned command holds a match
cmd_has() { printf '%s' "$scanned" | grep -q -E "${PREFIX}$1"; }

is_gate=no
if cmd_has "(${PM_RE}|${BIN_RE})"; then
  is_gate=yes
else
  project_gates="$(project_gates_re)"
  if [ -n "$project_gates" ] && cmd_has "(${project_gates})${GATE_END}"; then
    is_gate=yes
  fi
fi
[ "$is_gate" = yes ] || { echo '{}'; exit 0; }

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PROJECT_DIR"
scratch="$(printf '%s' "$input" | jq -r '.scratchpad_dir // empty' 2>/dev/null)"
[ -n "$scratch" ] && [ -d "$scratch" ] || scratch="$(mktemp -d)"
id="$(printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null)"
cmdfile="$scratch/autopilot-gate-${id:-$$}-$(date +%s%N 2>/dev/null || date +%s).sh"
{
  printf '# CWD: %s\n' "$cwd"
  printf '%s\n' "$cmd"
} >"$cmdfile"

jq -n --arg c "bash \"$SELF\" run \"$cmdfile\"" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: {command: $c}}}'
exit 0
