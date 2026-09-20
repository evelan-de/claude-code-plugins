# Track B: CLI / infra task

Tools: `asciinema` and `agg` (`brew install asciinema agg` on macOS; see
asciinema.org and github.com/asciinema/agg for other platforms).

## B1: script the real commands

Write the exact command sequence the task's own instructions specify (README,
CLAUDE.md section, runbook) into a shell script. No shortcuts, no skipped
steps.

Human-gated steps (browser login, magic link, approving a dashboard prompt):
list them separately, the script runs everything else, narration and report
name them. When a one-time step already completed in a prior real run and its
state persists (a login token, a created project), build on it and say so in
the narration.

## B2: record

```bash
asciinema rec -c "bash the-script.sh" session.cast
```

Real commands, real output, real timing. Trim only dead time with asciinema's
idle-time options; never change what happened.

## B3: render

```bash
agg --idle-time-limit 1.5 session.cast session.gif
```

```bash
ffmpeg -i session.gif -movflags faststart -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -y terminal.mp4
```

`--idle-time-limit` compresses waits without altering real command durations;
prefer it over speeding up the whole recording.

When Track A also applies (a web UI shows the result), record that part with
the framework library the Track A way (navigate, screenshot, record; a full
test is not needed) and keep `terminal.mp4` and the browser segment separate;
they are concatenated in assemble.md.
