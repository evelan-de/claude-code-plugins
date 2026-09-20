# Assemble the narrated MP4

Inputs: the video file(s) from the track(s), one `beat_N.mp3` per narration
beat (tts.md), the narration script with rough timestamps.

## 1. Measure each clip

Per file (one call each):

```bash
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 beat_1.mp3
```

## 2. Compute non-overlapping starts

For each beat in order:
`start = max(intended_timestamp, previous_start + previous_duration + 0.15s)`.
Rough timestamps alone are not enough; a beat placed at the next video moment
can start before the previous one finished speaking. Overlap is a bug.

When a start had to move noticeably later than the video moment, disclose the
pacing mismatch in the report. Do not trim the long beat.

## 3. Mix the narration track

`adelay` takes the computed start in ms per clip:

```bash
ffmpeg -i beat_1.mp3 -i beat_2.mp3 -filter_complex "[0:a]adelay=0|0[a0];[1:a]adelay=13000|13000[a1];[a0][a1]amix=inputs=2:duration=longest:dropout_transition=0[aout]" -map "[aout]" -y narration.mp3
```

## 4. Mux

Single video source:

```bash
ffmpeg -i video.webm -i narration.mp3 -c:v libx264 -c:a aac -shortest -y demo.mp4
```

Both tracks (sequential cuts in narration order, e.g. terminal deploy, then
the browser showing the result):

```bash
ffmpeg -i terminal.mp4 -i browser.mp4 -filter_complex "[0:v]scale=1280:720,setsar=1[v0];[1:v]scale=1280:720,setsar=1[v1];[v0][v1]concat=n=2:v=1:a=0[v]" -map "[v]" -y combined.mp4
```

```bash
ffmpeg -i combined.mp4 -i narration.mp3 -c:v libx264 -c:a aac -shortest -y demo.mp4
```

## 5. Verify

```bash
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 demo.mp4
```

Narration noticeably longer or shorter than the video: say so in the report.

## Embedding in the report

1. Publish the report with `capabilities: {"assets": {}}` (load the
   `artifact-capabilities` skill first).
2. Upload each MP4: `Artifact` publish with `asset: true`, the report's `url`
   and the MP4's `file_path`. The result gives the asset `url`.
3. Put that URL into `<video controls src="...">` (poster: one of the real
   screenshots) and republish the same file to the same `url`.

Before/After: both videos in the same report under "Before" and "After"
headings, side by side (stacked on narrow viewports). Never a link-out,
never a base64 data URI for video.
