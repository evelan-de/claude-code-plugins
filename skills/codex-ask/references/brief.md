# Brief template for codex-ask

Write the brief to a temp file (`mktemp /tmp/codex-XXXXXX`) and pass it on
stdin. Fill only the lines that matter. Keep the user's intent verbatim; do
not add requirements, constraints or scope they did not state.

```text
GOAL
<the user's actual ask, restated faithfully>

CONTEXT
- Relevant files: <paths Codex should read first>
- Stack/conventions that matter here: <only the ones that apply>

CONSTRAINTS
- <what must not change>
- <project rules that bind this task>

EXPECTED RESULT
<what a good answer or change looks like>

DEFINITION OF DONE
<how Codex should verify its own work before finishing>
```

Structured output: when the user wants a machine-readable answer, write a
JSON schema to a file and add `--output-schema <FILE>`. Free text is the
default.
