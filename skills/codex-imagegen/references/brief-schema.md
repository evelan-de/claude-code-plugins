# Image brief schema and sizing

Codex's imagegen skill reads a labeled spec. Fill only the lines that matter.
Keep the user's intent; do not invent brands, slogans, extra subjects or
palettes. For project assets, read the page or DESIGN.md first so the image
matches the palette.

```text
Use your imagegen skill to generate an image.

Use case: <photorealistic-natural | product-mockup | ui-mockup |
  infographic-diagram | ads-marketing | logo-brand | illustration-story |
  stylized-concept | background-texture | social-og-card>
Asset type: <where it is used, e.g. "landing page hero", "1200x630 OG card">
Primary request: <the user's actual ask>
Subject: <the main thing in frame>
Scene/backdrop: <environment>
Style/medium: <photo | 3D render | flat illustration | ...>
Composition/framing: <wide | close | top-down; subject position; negative
  space where page copy overlays it>
Lighting/mood: <e.g. soft studio light, golden hour>
Color palette: <the product's palette for project assets>
Text (verbatim): "<exact text>" or "none"
Size: <WIDTHxHEIGHT and aspect>
Quality: <low for drafts | high for final assets and legible text>
Constraints: <must-keep items>
Avoid: <no logos, no watermark, no text unless requested, no extra UI chrome>

Save the final PNG to the absolute path: <ABS_PATH>
Create the folder if needed. After saving, print the absolute path you wrote.
Do not ask me anything; proceed end to end.
```

## Sizing

gpt-image-2 accepts `auto` or `WIDTHxHEIGHT` (edges multiples of 16, max edge
3840, ratio at most 3:1). Size is stated inside the brief, not as a CLI flag.

- Hero / wide banner: `1536x1024` (4K showcase: `3840x2160`)
- Square / avatar / icon: `1024x1024`
- Portrait / mobile: `1024x1536`
- Social / OpenGraph card: describe as 1200x630; Codex maps to the nearest
  valid size

The model returns the nearest valid size, not always the exact one. For a hard
size contract (OG cards, favicons, ad slots) generate at the right aspect and
resample afterwards:

```bash
python3 -c "from PIL import Image; Image.open('<ABS_PATH>').resize((1200, 630), Image.LANCZOS).save('<ABS_PATH>')"
```

## Transparency

No native transparent backgrounds. For a cutout, ask for the subject "on a
perfectly flat solid #00ff00 background, crisp edges, generous padding, no
shadows or reflections, #00ff00 used nowhere on the subject" and tell Codex
to run its bundled `remove_chroma_key.py` helper and save an alpha PNG. Hair,
glass or smoke: tell the user true transparency needs Codex's `gpt-image-1.5`
fallback and let them decide.
