# Camera RTSP stability trial — 2026-10-31

Two Wi-Fi cameras had intermittent packet loss and RTSP restarts. The detailed camera addresses, radio identifiers, per-device measurements, and event timeline are kept in private operational notes.

## Lessons retained

- Compare camera-to-router and server-to-camera packet loss before attributing stream stalls to Frigate.
- Change one radio or encoder setting at a time, then observe a full period of Frigate logs and recording quality.
- Lowering both cameras' bitrates improved the immediate sample, but later restarts showed that a short clean interval was not proof of a lasting fix.
- Confirm recorded clips decode cleanly as well as checking processed frames and reconnect counts.

The retained trial settings still need longer observation. A future access point change should be evaluated against the same measures.
