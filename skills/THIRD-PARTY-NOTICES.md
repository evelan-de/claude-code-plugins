# Third-party notices

## Workflow skills vendored from mattpocock/skills

The following skills were copied from https://github.com/mattpocock/skills (MIT License,
Copyright (c) 2026 Matt Pocock) at commit `c55ee46073ed923f86ce59a5eb3b6d895095d1b7`
(2026-09-18) and adapted for the Evelan plugin: renamed, cross-references rewritten to the
`evelan:` namespace, Codex `agents/openai.yaml` sidecars dropped, persona references removed.
They are maintained here as Evelan skills from now on and may diverge from upstream.

| Upstream | Evelan skill |
| --- | --- |
| grill-me, grilling, grill-with-docs | question-me (merged into one skill) |
| to-spec | to-spec |
| to-tickets | to-tasks |
| implement | implement |
| tdd | tdd |
| code-review | code-review |
| diagnosing-bugs | diagnose-bug |
| domain-modeling | domain-model |
| codebase-design | codebase-design |
| improve-codebase-architecture | improve-architecture |
| setup-matt-pocock-skills | setup-workflow-skills |
| handoff | handoff |

Not vendored: the `in-progress`, `misc` and `deprecated` folders. Vendored at first and
removed on 2026-09-20 (plugin 2.0.0): prototype, research, resolving-merge-conflicts, triage,
teach, to-questionnaire, wizard, writing-for-agents, wayfinder, ask-matt (which-skill), wait-what.

### MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Write-less rules vendored from DietrichGebert/ponytail

The "Write less" section of `skills/autopilot/SKILL.md` condenses the ladder and rules of
the `ponytail` skill from https://github.com/DietrichGebert/ponytail (MIT License,
Copyright (c) 2026 DietrichGebert) at commit `e3ba2aa6f1e6f0bc4d69eb09c9f0d0a93af56156`
(2026-09-14). Rewritten for an unattended run; intensity levels, statusline, the
`ponytail:` comment convention and the review/audit/debt/gain skills were not taken over.
Maintained here as part of the Evelan autopilot skill and may diverge from upstream.

### MIT License

Copyright (c) 2026 DietrichGebert

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
