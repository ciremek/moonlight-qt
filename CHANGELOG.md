# Changelog

Moonvibe versions, newest first. Each one builds on [Moonlight PC](https://github.com/moonlight-stream/moonlight-qt) 6.2.

## 0.4.0 · Make it yours · October 21, 2026

### New
- **In English**: the interface follows the Mac's language, French or English.
- **PC settings** (right-click a PC): rename it, see its detected addresses, and add several of your own, like Tailscale and WireGuard side by side, each with a test that checks the right PC answers. The wake options moved here.
- **App settings** (right-click an app): a tile icon and color, a quality of its own, and Mac apps to open when its stream starts and quit when it ends.
- Apps that restart themselves with admin rights, like VirtualHere, are quit too.

### Improved
- A quieter interface: settings explanations moved into tooltips, repeated subtitles are gone.
- Dark mode: red and indigo text and outlines, and the "running" badge, now reach at least 5:1 contrast.
- VoiceOver: app tiles launch from VoiceOver, unnamed controls got names, nothing reads twice.

## 0.3.0 · Wake & Go · October 18, 2026

### New
- **Wake & Go**: launching an app on a PC that's off or asleep wakes it up, then launches the app as soon as it answers. The Wake-on-LAN packet goes out again every 10 seconds for 2 minutes, with a timer and a Cancel button on Home.
- **Per-PC wake options**: an editable MAC address and an external target (IP or DDNS name + port) to wake the PC from outside your home network.
- **LAN at home, Tailscale on the go**: Moonvibe uses the PC's local address as soon as the Mac is on its network, and a VPN address no longer replaces the local one.

### Fixed
- Home comes back right away after a stream, instead of waiting up to 30 seconds when the PC stopped answering.
- A PC that falls asleep during a stream shows as offline as soon as you quit, instead of staying online.
- Quitting the app on the PC is skipped when the PC no longer answers.
- Launching a stream while the previous one is still closing shows a message, instead of getting stuck on "Connexion…".

## 0.2.0 · Liquid Glass interface · October 18, 2026

### New
- **SwiftUI interface** on top of the Moonlight engine: Home with your PCs, their apps and recent sessions, search and keyboard shortcuts.
- **Guided pairing** with the PIN to type into Sunshine.
- **Liquid Glass in-stream panels**: a bar with the PC and the app, a live stats card, and a shortcut reminder while the mouse is captured.
- **Settings** in their own window, with a **Perso** (custom) preset saved as soon as you leave the built-in presets.
- **Moonvibe icon** in light and dark.

### Fixed and hardened
- The AWDL rule install is protected against swapped temporary files, and logs are private in `~/Library/Logs/Moonvibe`.
- No more PC polling during streams, or after 5 minutes in the background.
- Presets follow the refresh rate of the display the stream opens on.
- Confirmation before quitting the app running on the PC to launch another one.
- Discord status off by default. macOS 14.4 minimum.
- Upstream fix: the mouse polling rate is no longer reduced.

## 0.1.0 · First steps · October 17, 2026

- **Moonvibe** becomes its own app: separate name, identifier and settings, so it runs alongside the official Moonlight.
- **Auto resolution**: the stream uses the native resolution of the display it opens on.
- **AWDL off while streaming**, optional, to avoid Wi-Fi latency spikes.
