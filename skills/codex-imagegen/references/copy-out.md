# Where the file lands, and copying it out

Codex's image tool writes first to `~/.codex/generated_images/<session-id>/`
(Windows: `%USERPROFILE%\.codex\generated_images\<session-id>\`), then copies
to the destination named in the brief. On Windows the native sandbox can block
that copy (log shows `windows sandbox: ... apply deny-read ACLs`) although the
image was generated.

When the destination file is missing after the run:

```bash
codex-image-copy <ABS_PATH>
```

The helper picks the newest session directory and its newest `ig_*.png`
(fallback: any png in that session), creates the destination folder and
copies the file. It never picks bundled sample images or older sessions.
Then look at the copied file and confirm it is the image just described.

Re-run the generation only when no image was generated at all.
