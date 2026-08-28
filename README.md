# loopback

Small macOS utilities for routing system audio through
[BlackHole](https://existential.audio/blackhole/) — the piece every loopback
project ends up rewriting.

## audio-route

Snapshots your current input/output devices, switches them to BlackHole so
another program (a visualizer, a reverb, a recorder) can see the system audio,
and restores them on `off`.

```bash
brew install blackhole-2ch          # if you don't already have it
./audio-route on                    # snapshot, then route through BlackHole
./audio-route off                   # restore, discard the snapshot
./audio-route status                # what's selected, and is a snapshot held
```

### Put it on your PATH

Symlink the script into any directory already on `$PATH` — on macOS
`~/.local/bin` is a common choice:

```bash
mkdir -p ~/.local/bin
ln -s "$PWD/audio-route" ~/.local/bin/audio-route
audio-route status                  # now callable from anywhere
```

The script resolves symlinks before locating `audiodev.swift`, so the shim
still finds the CoreAudio helper next to the real script.

Routing "output" to bare BlackHole would silence your speakers, so `audio-route`
picks a **Multi-Output Device** that includes BlackHole (create one in
**Audio MIDI Setup → + → Create Multi-Output Device**, tick BlackHole and your
speakers). Override the auto-detected targets with `HYPERSPACE_OUTPUT` /
`HYPERSPACE_INPUT` (a UID, exact name, or substring).

The snapshot stores device UIDs, not names, so a renamed device still restores.
A second `on` keeps the first snapshot — the state you actually want back.

`audiodev.swift` is the small CoreAudio helper the script shells out to; it
compiles once into `~/.cache/hyperspace/audiodev` and is reused.

## Why standalone

Extracted from [Hyperspace](https://github.com/Cutaiar/hyperspace) so other
loopback tools (e.g. real-time reverb, per-app recorders) can depend on the
same routing helper instead of copy-pasting it.
