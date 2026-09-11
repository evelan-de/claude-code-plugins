# Self-hosted TTS (openai-edge-tts)

Backs the [`e2e-demo`](../../skills/e2e-demo/SKILL.md) skill's voice narration. Shared across every
project using this plugin, the same way `bin/codex-cli` is a shared tool rather than something each
project reinvents - stand this up once per machine (or once per project, your call) and any project
running `e2e-demo` can use it.

Wraps [travisvn/openai-edge-tts](https://github.com/travisvn/openai-edge-tts): a self-hosted server
that exposes an **OpenAI-compatible** `/v1/audio/speech` endpoint but synthesizes speech using
Microsoft Edge's free neural TTS voices under the hood. **No OpenAI account, API key, or billing is
involved anywhere** — `API_KEY` below is a secret this container invents and checks itself, never a
real OpenAI credential. Note synthesis itself does call out to Microsoft's Edge TTS backend over the
internet to actually generate the audio - this is self-hosted and free, but not fully air-gapped.

## Bringing it up

```bash
cd docker/openai-edge-tts   # wherever this plugin is checked out, e.g. ~/work/github/claude-code-plugins
cp .env.example .env
# edit .env: set API_KEY to any string you like
docker compose up -d
```

Published on `http://localhost:5060` by default. Check for a port collision first if a specific
project already uses 5060 for something else (`lsof -iTCP:5060 -sTCP:LISTEN`) and set `TTS_PORT` in
`.env` to something else if so.

## Verifying it works

```bash
curl -X POST http://localhost:5060/v1/audio/speech \
  -H "Authorization: Bearer $(grep API_KEY= .env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d '{"input":"This confirms the local text to speech service is working.","voice":"en-US-AvaNeural","response_format":"mp3"}' \
  --output test.mp3
```

Should produce a real playable mp3. `POST /v1/voices` with `{"language":"<locale>"}` (e.g. `de-DE`,
`en-US`, `fr-FR`) lists available voices for that language - useful when a project's narration needs
a different language than the default.

## Gotchas

- **`REQUIRE_API_KEY=True` by default.** Every request needs `Authorization: Bearer <API_KEY>`
  matching what's in `.env`, or it's rejected. There is no "correct" value to guess — whatever you
  put in `.env` is correct, because the server both sets and checks it.
- **One instance can serve every project.** There's no per-project state here beyond the API key -
  if you're regularly using `e2e-demo` across multiple repos, it's fine (and simpler) to run this
  once per machine rather than once per project, as long as they all know the port and key.
