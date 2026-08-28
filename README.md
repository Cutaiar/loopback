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

### Two modes: passthrough vs. processed

By default, `audio-route on` picks a **Multi-Output Device** that includes
BlackHole (create one in **Audio MIDI Setup → + → Create Multi-Output Device**,
tick BlackHole and your speakers). Your speakers keep playing while BlackHole
receives the same stream — right for visualizers, recorders, meters.

If another program is going to *process* the BlackHole feed and play the result
back to your speakers (a reverb, an EQ, a pitch shifter), the multi-output is
wrong: you hear the untouched dry signal on top of the processed one. Use
`--bare` to route output to BlackHole 2ch only:

```bash
audio-route on --bare               # speakers go silent; processor is your only path
```

### Overrides

`LOOPBACK_OUTPUT` / `LOOPBACK_INPUT` force a specific device instead of the
auto-picked one. Value can be a UID, an exact name, or any substring of a name.

```bash
LOOPBACK_OUTPUT="Multi with Sonos" audio-route on
LOOPBACK_INPUT="BlackHole 16ch" audio-route on
```

### Under the hood

The snapshot stores device UIDs, not names, so a renamed device still restores.
A second `on` keeps the first snapshot — the state you actually want back.

`audiodev.swift` is the small CoreAudio helper the script shells out to; it
compiles once into `~/.cache/loopback/audiodev` and is reused.

## Why standalone

Extracted from [Hyperspace](https://github.com/Cutaiar/hyperspace) so other
loopback tools (e.g. real-time reverb, per-app recorders) can depend on the
same routing helper instead of copy-pasting it.
