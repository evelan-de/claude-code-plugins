# Reference images and compositing

`codex exec` takes reference images via one `--image <FILE>` flag per file.
gpt-image-2 uses them as visual input: put a real screenshot on a device
screen, restyle a photo, blend elements.

```bash
codex-cli exec --sandbox workspace-write -c approval_policy=on-request -c approvals_reviewer=auto_review --skip-git-repo-check --image public/marketing/device-photo.png --image /tmp/app-ui.png - < /tmp/codex-<brief> > /tmp/codex-<log> 2>&1
```

Rules:

- `--image` is variadic. A positional prompt after it is read as another
  image and Codex reports "No prompt provided via stdin". The brief always
  goes in on stdin (trailing `-`).
- Label each input in the brief ("IMAGE 1 is the device photo, IMAGE 2 is the
  UI screenshot") and say what to do with each.
- UI on a screen: "map IMAGE 2 onto the screen with correct perspective, fill
  edge-to-edge inside the bezel, keep the UI crisp and legible, do not redraw
  or garble its text, add a subtle screen-glow spill onto the scene". Check
  small labels for legibility afterwards.
- Keep a photo mostly unchanged: "keep IMAGE 1's composition, lighting and
  background essentially unchanged".

A baked-in composite beats a CSS perspective overlay in the page: one flat
asset, no drift across breakpoints.
