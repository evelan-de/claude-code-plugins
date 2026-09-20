# Narration voice (local TTS)

A self-hosted server with an OpenAI-compatible `/v1/audio/speech` endpoint.
This plugin ships one at `docker/openai-edge-tts/` (travisvn/openai-edge-tts;
no OpenAI account; synthesis calls Microsoft's Edge TTS backend over the
internet). One instance serves every project.

Check first: `docker ps --filter name=openai-edge-tts`. Not running and the
user did not say to skip narration: start it without asking. Read
`docker/openai-edge-tts/README.md` in the plugin checkout for the env it
expects (`API_KEY` is any string you choose), put it in a `.env` next to the
compose file, then:

```bash
docker compose -f <plugin-checkout>/docker/openai-edge-tts/docker-compose.yml up -d
```

Default port 5060. A project may carry its own copy under its `docker/`;
reuse that one.

## Voice and language

Match the narration language to the project's audience (README, CLAUDE.md;
ask when unclear). Write spoken language, not text read verbatim from a
description. `POST /v1/voices` with `{"language":"de-DE"}` lists voices for a
locale.

## Synthesize one clip per beat

Never one clip for the whole script; the overlap check in assemble.md works
per beat.

```bash
curl -s -X POST http://localhost:5060/v1/audio/speech -H "Authorization: Bearer <API_KEY>" -H "Content-Type: application/json" -d '{"input":"<beat text>","voice":"<voice>","response_format":"mp3"}' --output beat_1.mp3
```

Check each output is audio, not an error body: `file beat_1.mp3` says
`MPEG ADTS`, not `ASCII text`.
