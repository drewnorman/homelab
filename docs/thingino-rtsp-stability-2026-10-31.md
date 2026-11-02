# Thingino RTSP stability trial — 2026-10-31

Times are America/Denver (MDT). Measurements are from `lab-core` unless
stated otherwise. The router at `192.168.1.1` is a Netgear R7450; both
cameras reported its BSSID (`BC:A5:11:10:E2:C8`). The router lost no packets
in the checks run from `lab-core`.

| Stage | Camera 1 (`.23`) | Camera 2 (`.24`) | Frigate observations |
| --- | --- | --- | --- |
| Baseline, channel Auto (2), 08:32 | 7% loss / 100 packets; 5.48 ms average RTT | 6% loss / 100; 598 ms average RTT | 5.0 / 3.6 processed fps; 12 / 77 reconnects and 202 / 220 stalls in the preceding hour |
| Channel 11, about 08:43–08:48 | 7.7–8.3% loss / 300; 960–1211 ms average RTT across both cameras | Same combined range | 08:39–08:56: 13 / 11 ffmpeg restarts and 51 / 60 RTSP timeouts |
| Channel 1, about 08:59–09:04 | 11% loss / 300; 978 ms average RTT | 11% loss / 300; 16.6 ms average RTT | 08:56–09:05: 8 / 1 ffmpeg restarts and 35 / 2 RTSP timeouts |
| Channel 1, camera 2 at 2500/500 kb/s, about 09:05–09:10 | 6.3% loss / 300; 910 ms average RTT | 7.3% loss / 300; 6.25 ms average RTT | 5.1 processed fps each, 0 skipped fps in the immediate sample; no new camera 2 restarts from 09:06–09:10, while camera 1 had 2 |
| Channel 1, camera 2 at 2500/500 kb/s, about 09:24–09:29 | 8% loss / 300; 594 ms average RTT | 8% loss / 300; 21.6 ms average RTT | No camera 2 ffmpeg restart through the sample; camera 1 continued restarting |
| Channel 1, camera 2 at 2500/500 kb/s, about 09:55–10:00 | 12% loss / 300; 744 ms average RTT | 11.3% loss / 300; 1067 ms average RTT | Camera 2 accumulated at least 7 fresh restarts by 09:52; 0% router loss |
| Camera 2's full hour, ending 10:04 | Camera 1 stayed at 4000/1000 kb/s | Camera 2 stayed at 2500/500 kb/s | Fresh Frigate log since 09:06: 20 / 17 ffmpeg restarts and 47 / 69 RTSP timeouts; both marked `unusable` |
| Channel 1, both cameras at 2500/500 kb/s, about 10:05–10:10 | 1.33% loss / 300; 25.3 ms average RTT, 4.6 s max | 0.33% loss / 300; 174 ms average RTT, 10 s max | Router 0% loss; camera 2 had one RTSP timeout in the new log window |
| Channel 1, both cameras at 2500/500 kb/s, about 10:20–10:25 | 0% loss / 300; 2.39 ms average RTT | 0% loss / 300; 2.18 ms average RTT | Router 0% loss; no new ffmpeg restart since 10:06 at the start of this sample |
| Channel 1, both cameras at 2500/500 kb/s, about 10:39–10:44 | 0% loss / 300; 2.33 ms average RTT | 0% loss / 300; 2.59 ms average RTT | Router 0% loss; both about 5 processed fps, 0 skipped fps, and no ffmpeg restart since 10:06 |
| Channel 1, both cameras at 2500/500 kb/s, about 10:54–10:59 | 0% loss / 300; 7.28 ms average RTT, 1.02 s max | 0% loss / 300; 3.31 ms average RTT, 142 ms max | Router 0% loss |
| Both-camera hour end, 11:04 | 1% loss to router and `lab-core` in 100-packet camera-origin checks | 0% loss to router, 1% to `lab-core` in 100-packet camera-origin checks | About 5 processed fps and 0 skipped fps each; `fair` connection quality, 1 reconnect and 9 stalls per camera in the rolling hour |

## Outcome

Channel 11 was stopped before the planned hour because loss and latency were
already worse and Frigate kept restarting both feeds. Channel 1 was retained
because its fresh log window had fewer reconnects, especially for camera 2.
Camera 2 was changed from 4000/1000 to 2500/500 kb/s at about 09:04 and
observed for one hour. Camera 1 was then changed to 2500/500 kb/s at about
10:04 and observed for another hour. Each change restarted only that camera's
`/etc/init.d/S31prudynt` service, and 25/5 fps was verified unchanged. These
are the settings retained.

With both cameras reduced, 100-packet checks **from** each camera to the
router and `lab-core` had 0% loss at about 10:14. The three later 300-packet
checks from `lab-core` had 0% loss to both cameras. At 11:04, three of four
camera-origin 100-packet checks had exactly 1% loss, missing the strict
less-than-1% target. Frigate was processing about 5 fps per camera with 0
skipped fps, but it reported one reconnect and nine stalls per camera in the
rolling hour. The fresh logs place the reconnects at 11:00:09 for camera 2
and 11:00:39 for camera 1. Both had RTSP timeouts. The performance is much
better than baseline, but the no-reconnect target has not been met. Repeat
100-packet checks shortly afterward had 0% loss from both cameras to both
destinations, and Frigate logged no further timeout or restart since 11:01.

Neither Thingino kernel log showed a Wi-Fi disassociation at the 11:00
failure. Their syslogs contained routine RTSP messages without a matching
new error. At 09:33, a 100-packet check from camera 1 to the router and
`lab-core` had 1% loss and 589–863 ms average RTT; camera 2 had 2% loss to
both destinations and 4–5.5 ms average RTT. A one-minute `wlan0` interface
counter sample showed 2/7 receive drops and zero transmit drops on cameras
1/2. The drivers reported a 72.2 Mb/s link but did not provide usable
retransmission counts through `iwconfig`.

## Recording check and follow-up

A camera 2 Frigate event clip from 10:07 decoded without errors (201 frames
over 8.06 seconds). Camera 1's 10:06:51 clip had H.264 decode errors and
contained 975 frames but reported only 0.29 seconds of duration. Another
camera 1 clip from 10:06:32 was only 1.3 KB despite being served as MP4.
These clips were created shortly after its streamer restart; no later
natural camera 1 event was retained during the hour. A manual `test` event
request was rejected with HTTP 403, so no synthetic event was created.
A clean, later camera 1 recording is still unverified.

Direct RTSP probes after the one-hour trial found 199 frames over about eight
seconds on each camera's main stream, with 40 ms median timestamp steps and
no non-monotonic frames. A separate eight-second direct camera 1 MP4 recorded
200 frames over 8.04 seconds and decoded without errors. This narrows the
remaining check to a later **Frigate** camera 1 event clip.

Both cameras use the same Thingino build (`ciao+2c3eca5`, 2026-08-14), the
same Prudynt binary, and matching non-credential `/etc/prudynt.json` settings.

## Access-point diagnostics

After router access was restored, its Advanced Home page confirmed 2.4 GHz
channel 1 and firmware `V1.2.1.92_1.0.1`. **Show Statistics** displayed
aggregate 2.4 GHz packet and byte counters and zero reported collisions, but
no per-client signal or retry counters. **Attached Devices** remained on
"Please wait a moment" for over two minutes in both Basic and Advanced views.
Router logs for 16:59–17:02 UTC (10:59–11:02 MDT) contained access-control
entries and an unrelated DHCP assignment, with no camera MAC event. That
absence does not establish good radio quality; this interface did not provide
the per-camera RF measurements needed to isolate the remaining outage.
The cameras' own `iwconfig` indicators at the follow-up were link quality
66/100 and signal 50/100 for camera 1, and 58/100 and 44/100 for camera 2;
these driver units are not calibrated dBm readings, and no useful retry
counter was exposed through `iwconfig`, `/proc/net`, or kernel debug files.

Repeat Frigate health and recording checks after 24 hours; retain channel 1
and 2500/500 kb/s on both cameras meanwhile.
