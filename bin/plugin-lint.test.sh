#!/usr/bin/env bash
# Tests for bin/plugin-lint. Run: bash bin/plugin-lint.test.sh
set -uo pipefail

TOOL="$(cd "$(dirname "$0")" && pwd)/plugin-lint"
PASS=0; FAIL=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check() { # $1 desc  $2 want_exit  $3 want_substring  $4 got_exit  $5 got_output
  if [ "$4" -eq "$2" ] && printf '%s' "$5" | grep -qF "$3"; then
    echo "ok   - $1 (exit $4)"; PASS=$((PASS+1))
  else
    echo "FAIL - $1 (want exit $2 + '$3'; got exit $4, output: $5)"; FAIL=$((FAIL+1))
  fi
}

# A clean fake plugin root: two skills (alpha with two references files, beta
# with a folded description that borrows alpha's shared.md), one agent, a
# plugin.json listing that agent, and a README naming both skills.
P="$tmp/p"
fresh() {
  rm -rf "$P"
  mkdir -p "$P/skills/alpha/references" "$P/skills/beta" "$P/agents" "$P/.claude-plugin"
  cat > "$P/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: The alpha skill. Triggers on "alpha".
---

Read `references/notes.md` first, then call evelan:beta.
EOF
  echo "notes" > "$P/skills/alpha/references/notes.md"
  echo "shared" > "$P/skills/alpha/references/shared.md"
  cat > "$P/skills/beta/SKILL.md" <<'EOF'
---
name: beta
description: >-
  The beta skill, folded over
  two lines.
---

Shared rules: `${CLAUDE_PLUGIN_ROOT}/skills/alpha/references/shared.md`.
Reviewer: evelan:helper.
EOF
  cat > "$P/agents/helper.md" <<'EOF'
---
name: helper
description: A helper agent used by evelan:alpha.
---
EOF
  cat > "$P/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "evelan",
  "version": "1.0.0",
  "skills": "./skills/",
  "agents": [
    "./agents/helper.md"
  ]
}
EOF
  cat > "$P/README.md" <<'EOF'
# Fake plugin

Skills: alpha, beta. Agents: evelan:helper.
EOF
}

run() { out="$(sh "$TOOL" "$P" 2>&1)"; got=$?; }

# 1. clean root -> exit 0 with the OK line
fresh; run
check "clean root -> OK line" 0 "plugin-lint: OK (2 skills, 1 agents)" "$got" "$out"

# 2. default root = git top level of the cwd
fresh
git init -q "$P"
out="$(cd "$P/skills" && sh "$TOOL" 2>&1)"; got=$?
check "default root from git top level" 0 "plugin-lint: OK (2 skills, 1 agents)" "$got" "$out"

# 3. name mismatch
fresh; sed -i.bak 's/^name: alpha$/name: alfa/' "$P/skills/alpha/SKILL.md"; rm "$P/skills/alpha/SKILL.md.bak"; run
check "name mismatch" 1 "skills/alpha/SKILL.md: name: is 'alfa' but the folder is 'alpha'" "$got" "$out"

# 4. missing description
fresh; sed -i.bak '/^description:/d' "$P/skills/alpha/SKILL.md"; rm "$P/skills/alpha/SKILL.md.bak"; run
check "missing description" 1 "skills/alpha/SKILL.md: frontmatter has no description:" "$got" "$out"

# 5. empty description
fresh; sed -i.bak 's/^description:.*/description:/' "$P/skills/alpha/SKILL.md"; rm "$P/skills/alpha/SKILL.md.bak"; run
check "empty description" 1 "skills/alpha/SKILL.md: description: is empty" "$got" "$out"

# 6. missing frontmatter
fresh; printf 'no frontmatter\n' > "$P/skills/alpha/SKILL.md"; run
check "missing frontmatter" 1 "skills/alpha/SKILL.md: frontmatter missing" "$got" "$out"

# 7. referenced references file missing
fresh; rm "$P/skills/alpha/references/notes.md"; run
check "missing referenced references file" 1 "skills/alpha/SKILL.md: references/notes.md does not exist under skills/alpha/" "$got" "$out"

# 8. cross-skill referenced file missing
fresh; rm "$P/skills/alpha/references/shared.md"; run
check "missing cross-skill references file" 1 "skills/beta/SKILL.md: skills/alpha/references/shared.md does not exist" "$got" "$out"

# 9. unreferenced references file
fresh; echo "orphan" > "$P/skills/alpha/references/orphan.md"; run
check "unreferenced references file" 1 "skills/alpha/references/orphan.md: not mentioned in skills/alpha/SKILL.md" "$got" "$out"

# 10. unresolved evelan: reference
fresh; echo "See evelan:gamma." >> "$P/skills/beta/SKILL.md"; run
check "unresolved evelan: reference" 1 "skills/beta/SKILL.md: line 10: evelan:gamma resolves to neither skills/gamma/ nor agents/gamma.md" "$got" "$out"

# 11. plugin.json lists an agent that does not exist
fresh; sed -i.bak 's|"./agents/helper.md"|"./agents/helper.md", "./agents/ghost.md"|' "$P/.claude-plugin/plugin.json"; rm "$P/.claude-plugin/plugin.json.bak"; run
check "plugin.json lists a missing agent" 1 ".claude-plugin/plugin.json: agents lists ghost.md but agents/ghost.md does not exist" "$got" "$out"

# 12. plugin.json does not list an existing agent
fresh; printf -- '---\nname: extra\n---\n' > "$P/agents/extra.md"; run
check "plugin.json misses an agent" 1 ".claude-plugin/plugin.json: agents does not list agents/extra.md" "$got" "$out"

# 13. em dash (written via printf so this test file itself stays clean)
fresh; printf 'A line with a %b dash.\n' '\342\200\224' >> "$P/agents/helper.md"; run
check "em dash reported with file and line" 1 "agents/helper.md: line 5: em dash (U+2014)" "$got" "$out"

# 14. skill missing from README
fresh; printf '# Fake plugin\n\nSkills: alpha.\n' > "$P/README.md"; run
check "skill missing from README" 1 "README.md: does not mention skill 'beta'" "$got" "$out"

# 15. removed-concept mention
fresh; echo "Old flow: mission-control decides." >> "$P/README.md"; run
check "removed concept" 1 "README.md: line 4: removed concept \"mission-control\"" "$got" "$out"

# 16. excluded files are not scanned for evelan:/removed concepts
fresh
echo "evelan:nothing and DIGEST.md" > "$P/skills/THIRD-PARTY-NOTICES.md"
echo "evelan:nothing and wayfinder" > "$P/skills/alpha/x.test.sh"
run
check "THIRD-PARTY-NOTICES.md and *.test.sh are skipped" 0 "plugin-lint: OK" "$got" "$out"

# 17. no root at all -> exit 2
out="$(cd "$tmp" && sh "$TOOL" 2>&1)"; got=$?
check "no root -> exit 2" 2 "no plugin root" "$got" "$out"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
