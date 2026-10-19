# Lockloop

Make animated lock screen wallpapers for iPhone and Android, right in the phone's browser.

- **8 scenes**: Liquid gradient, Aurora, Warp, Bokeh, Waves, Code Rain, Orbits, and My Photo (your picture with slow zoom, pan, sway or breathe motion)
- **Overlays**: snow, rain, sparkles and fireflies, layered on any scene
- **Palettes**: 8 presets plus 3 custom colors, with speed and detail sliders and a Shuffle button
- **Live preview** in a phone frame with an iOS- or Android-style clock, so you can check that the clock stays readable
- **Exact device sizes**: iPhone 16 Pro Max through SE, Galaxy S25/S25 Ultra, Pixel 9/9 Pro, and generic 1080×2400
- **Seamless loops**: all motion completes whole cycles per loop, so the last frame flows into the first
- **Export**: H.264 MP4 rendered frame by frame (WebCodecs + [mp4-muxer](https://github.com/Vanilagy/mp4-muxer), MIT, vendored in `vendor/`). Browsers without WebCodecs fall back to real-time `MediaRecorder` capture. There's also a PNG still. On phones, **Save / Share** opens the system share sheet so you can save straight to Photos or Gallery.

## Run it

No build step is needed. Serve the folder over HTTP:

```sh
cd lockloop
python3 -m http.server 8000
# open http://localhost:8000
```

To use it on a phone, host the folder on any static host (GitHub Pages, Netlify, Vercel) and open it in Safari or Chrome. You can then use *Add to Home Screen* to install it like an app.

## Setting the wallpaper

| Phone | How |
| --- | --- |
| iPhone | Export the **3 s (Live Photo)** loop and save it to Photos. Convert it to a Live Photo with a video-to-Live-Photo app, then go to Settings → Wallpaper → Add New → Photos. iOS can only animate the lock screen from a Live Photo. |
| Samsung Galaxy | Settings → Wallpaper and style → Change wallpapers → Gallery → pick the video (up to 15 s) for the Lock screen. |
| Pixel / other Android | Use a video live-wallpaper app from Google Play and pick the exported video. |

## Files

- `index.html`: layout and controls
- `scenes.js`: deterministic scene and overlay renderers (pure functions of loop phase)
- `app.js`: UI state, preview loop and video/PNG export
- `styles.css`: styles (responsive, mobile first)
