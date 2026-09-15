<div align="center">

# Vigia

**An NVR for macOS.** Records your IP cameras to a server you own, keeps as much
history as the disk allows, and plays it back natively — the Intelbras Play job,
built for the Mac.

</div>

---

Vigia is two halves. A recorder that runs on your own machine — a homelab box, a
NAS, anything that runs Docker — pulling RTSP and writing it to disk in
segments, deleting the oldest as space runs out, like a conventional DVR. And a
native macOS client that watches the live feed and searches the recordings on a
timeline.

## The client

```sh
brew install --cask mesquitadev/tap/vigia
xattr -dr com.apple.quarantine /Applications/Vigia.app
```

Or build from source: `Scripts/bundle.sh` then `open dist/Vigia.app`.

The recorder announces itself over Bonjour, so the app finds it on its own — no
IP address to type in.

## The recorder

Copy `deploy/` to the machine that will record, fill in `.env` from
`.env.example`, and bring it up:

```sh
cp .env.example .env    # camera address, user, password
docker compose up -d
```

Seven small containers: the recorder, a retention loop, an HLS transcoder for
live view, an indexer, an event listener that receives the camera's motion
alerts, nginx, and the Bonjour announcer.

## Recordings

Video is copied, never re-encoded, so recording costs almost no CPU and the
quality is exactly what the camera sent. Retention is a circular buffer with
three limits at once — maximum age, maximum size, and a floor of free space that
is never eaten — and the most restrictive wins.

HEVC is tagged `hvc1` rather than `hev1`. Apple silently refuses to play `hev1`
in MP4: the file reports as not playable, with no error explaining why.

## The timeline

The day is one continuous track: motion episodes in amber above, recorded
footage in blue below, with a playhead that moves with the video. Clicking a
time seeks to that second inside the right file, and playback crosses from one
five-minute segment to the next without a pause, so the file boundaries are
invisible.

Motion events from the camera say *when* something moved, not *where*. Vigia
works out the where by comparing neighbouring frames as you watch, and draws a
box around what changed.

## Requirements

macOS 14 or later for the client. Docker on the recorder. An ONVIF/RTSP camera —
developed against an Intelbras VIP 3230 B, which speaks the Dahua CGI API.

## License

MIT © Paulo Victor Mesquita
