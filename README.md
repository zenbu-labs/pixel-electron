# pixel-electron

Patched Electron for the pixel terminal browser. This repo is the source of
truth for the patches and build configuration; prebuilt binaries are published
as GitHub Releases on
[zenbu-labs/electron-releases](https://github.com/zenbu-labs/electron-releases),
which also hosts the automation that keeps everything in sync with upstream
Electron — see its README for how the pipeline works.

## The patch

`patches/osr-vsync-display.patch` — offscreen-rendering windows get a
compositor with no display id, so viz drives their begin frames from a 60Hz
fallback timer whose "supported frame intervals" menu tops out at 60fps. The
moment the page receives any input, Chromium's frame interval decider clamps
begin frames (and therefore requestAnimationFrame) to 60fps, and the throttled
interval is reported back as the display interval, permanently overwriting the
rate requested via `webContents.setFrameRate`. The patch binds the offscreen
compositor to the primary display, so begin frames ride a real display link:
supported intervals derive from the actual monitor refresh rate, input boosts
to the fastest rate instead of clamping to 60, and the display-link path has
the guard against the interval feedback loop that latches the throttle.

## Layout

- `patches/` — applied on top of `src/electron` after `gclient sync`
- `config.json` — `platforms` to build, how many electron `supported_majors`
  to track, and the `minimum_version` worth building
- `scripts/check-patches.sh <version>` — verifies patches apply to an electron
  tag (used by the sync workflow; cheap, no chromium checkout)
- `scripts/build.sh <version> <out dir>` — full source build producing
  officially-named release assets (used by the build workflow; also works
  locally on any Mac with ~120GB free disk)

## Consuming the binaries

The npm `electron` package downloads its binary from a mirror when configured.
Point it at the release repo in `.npmrc`:

```ini
electron_mirror=https://github.com/zenbu-labs/electron-releases/releases/download/
electron_custom_dir=v{{ version }}
```

Everything else — package.json version, `@electron/get` checksums — works
unchanged, as long as a release exists for the version you pin.
