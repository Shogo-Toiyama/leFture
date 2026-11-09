# System audio capture test

Checks whether the webapp could record the sound the computer is playing (e.g. a Zoom class
heard through earphones) with `navigator.mediaDevices.getDisplayMedia({ audio: true, systemAudio: 'include' })`,
instead of asking users to record it on a second device.

No external API is called, so this test costs $0.

## Run

```bash
python3 contents_generation/test_codes/system_audio_capture/serve.py
# open http://localhost:8765/ in Chrome (http://localhost is a secure context; file:// is not)
```

Each run writes into `results/` (git-ignored, recordings may contain class audio):

- `<YYYYMMDD_HHMMSS>_<scenario>.<webm|m4a|ogg>` — the recording
- `<YYYYMMDD_HHMMSS>_<scenario>.json` — environment, requested constraints, what was shared
  (`displaySurface`), audio track settings, level meter stats, decode check, event log

`outcome` in the JSON is `audio_captured` (peak > -50 dBFS), `silent`, `decode_failed`, or `no_audio_track`.

## Scenarios worth running

| scenario label | share in the picker | sound source | output |
|---|---|---|---|
| `tone_screen_earphones` | entire screen + system audio | the page's test tone | earphones |
| `zoom-app_screen_earphones` | entire screen + system audio | Zoom desktop app | earphones |
| `zoom-app_window_earphones` | Zoom window + system audio | Zoom desktop app | earphones |
| `zoom-web_tab_earphones` | the Zoom web-client tab + tab audio | Zoom in Chrome | earphones |
| `*_videostop` | any, with "stop video track" checked | any | any |

Also open the page in Safari / Firefox once to record which browsers return no audio track.
