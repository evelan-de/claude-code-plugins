# Manual testing - Codex delegation skills

Everything auto-testable in this environment was verified in REPORT.md. The one check below is
genuinely interactive (it needs a live Claude Code session with the plugin loaded) and could not
run in the non-interactive autopilot session.

## Live trigger behaviour

Launch a fresh session with the local plugin:

```bash
claude --plugin-dir /Users/astraub/dev/tools/claude-code-plugins
```

Then confirm:

1. `/codex-review` appears in the command list / `/help`.
2. Prompt "zweite Meinung von Codex zu meinen Änderungen" -> the `codex-review` skill is picked up.
3. Prompt "review my changes" (no Codex mention) -> `codex-review` is NOT invoked; the normal
   review flow runs. (This is the key negative check - explicit-only triggering.)
4. Prompt "frag Codex, was es von diesem Repo hält" -> `codex-ask` triggers, and its preflight
   `codex-cli --version` resolves the Codex.app binary.

Static coverage: the skill descriptions already encode the explicit-only triggers and the
"generic review does NOT trigger" clause, and the reviewer verified them - this step just
eyeballs the live matcher once.
