# ImpossibleGauge

A Windower 4 addon for Final Fantasy XI that auto-`/check`s mobs near you and alerts when one returns **"impossible to gauge"** — the telltale sign of a Notorious Monster or a mob far above your level.

Great for NM hunting, zone sweeps, and confirming which pops are the real deal without manually clicking every mob.

---

## Features

- **Auto-scan** nearby mobs within a configurable radius (default **50 yalms**, 3D distance)
- **Staggered `/check` injection** (default **2 s between checks**) to avoid server spam
- **HUD** with live state: on/off, queue size, /checks sent, current target, and a running list of confirmed IG mobs
- **Red flash** on the HUD for 5 s whenever a new "impossible to gauge" hit comes in
- **Chat suppression** — hides the auto-`/check` response spam so only the clean `[IG]` alert remains
- **Sound alert** (optional — point it at any `.wav` on disk)
- Per-zone tracking; state resets automatically on zone change
- Draggable HUD; position persists in `settings.xml`

---

## Installation

1. Copy the `ImpossibleGauge` folder into your Windower addons directory:
   ```
   <Windower>/addons/ImpossibleGauge/
   ```
   File layout:
   ```
   ImpossibleGauge/
     ImpossibleGauge.lua
     README.md
     data/
     data/settings.xml   (auto-created on first run)
   ```

2. In-game:
   ```
   //lua load ImpossibleGauge
   //ig on
   ```

3. Optional — add to your auto-load list in `Windower/scripts/init.txt`:
   ```
   lua load ImpossibleGauge
   ```

---

## Quick Start

```
//ig on          enable scanning + /check injection
//ig test        fire a fake alert so you can see/position the HUD
//ig help        list every command
```

Drag the HUD with the mouse to where you want it; the position is saved automatically.

---

## How It Works

**Scan loop** (every `scan_interval` seconds, default 5 s):
- Walks the full mob array (`windower.ffxi.get_mob_array()`)
- Filters to `spawn_type == 16` (monsters), `valid_target == true`, `hpp > 0`, inside the configured range
- Skips mobs already queued, already auto-checked within `recheck_time` seconds, or already confirmed
- Adds survivors to a pending queue

**Check loop** (fires in `prerender`, throttled by `delay`):
- Dequeues one pending mob
- Verifies it's still alive and valid
- Injects an outgoing `0x0DD` packet (`/check`) targeting that mob
- Records the check time and adds the mob's name to a short-lived "recent checks" map used for chat suppression

**Detection** (on incoming packet `0x029`):
- Parses the action message
- If `Message == 249` ("`${target}'s strength is impossible to gauge!`"), the target is flagged as confirmed
- Triggers: `[IG] >>> IMPOSSIBLE TO GAUGE: <name> <<<` in chat, 5 s red flash on the HUD, optional sound

**Chat suppression** (on `incoming text`):
- Any line that contains the name of a mob we auto-checked within the last `suppress_window` seconds (default 3 s) is blocked by returning `true`
- Lines starting with `[IG]` are exempt so the addon's own output always shows

---

## Commands

All commands are prefixed with `//ig` (or `//impossiblegauge`).

| Command | Description |
|---|---|
| `//ig on` / `off` / `toggle` | Enable/disable scanning |
| `//ig range <yalms>` | Scan radius (default `50`) |
| `//ig delay <seconds>` | Seconds between injected `/check`s (default `2.0`, min `0.5`) |
| `//ig scan <seconds>` | How often to rescan for new mobs (default `5.0`) |
| `//ig sound` | Toggle the sound alert |
| `//ig soundfile <path>` | Full path to the `.wav` you want to play on an IG hit |
| `//ig suppress [on/off]` | Hide auto-`/check` chat responses (default on) |
| `//ig hud [on/off]` | Show/hide the HUD overlay |
| `//ig test [name]` | Fire a fake alert (useful for positioning the HUD + testing sound) |
| `//ig list` | Print all confirmed IG mobs for this zone |
| `//ig clear` | Reset all tracking (queues, confirmations, flash) |
| `//ig status` | Print all current settings |
| `//ig help` | Show the command list in-game |

---

## Settings

Stored in `ImpossibleGauge/data/settings.xml` (auto-generated). You can edit directly or via commands.

| Key | Default | Notes |
|---|---|---|
| `enabled` | `false` | Start disabled; toggle via `//ig on` |
| `range` | `50` | Scan radius in yalms |
| `delay` | `2.0` | Seconds between /check injections |
| `scan_interval` | `5.0` | Seconds between full mob rescans |
| `recheck_time` | `120` | Seconds before a non-confirmed mob can be re-checked |
| `sound` | `true` | Play `sound_file` on IG hit |
| `sound_file` | `''` | Path to a `.wav` |
| `suppress` | `true` | Hide auto-`/check` chat responses |
| `suppress_window` | `3.0` | Seconds after sending /check to suppress related chat lines |
| `chat_color` | `200` | Chat color code for `[IG]` lines |
| `hud.visible` | `true` | Show the HUD |
| `hud.max_confirmed_shown` | `8` | Most recent N confirmed mobs to display |
| `hud.pos.x`, `hud.pos.y` | `10, 300` | HUD position (also updated by dragging) |

---

## HUD Anatomy

```
ImpossibleGauge [ON]  range=50y  delay=2.0s
Queue: 3    Sent: 12    Confirmed: 2
Checking: Frogamander
--- Impossible to Gauge ---
  - Unut
 >> Zurko-Bazurko                   <- ">>" + red bg = fresh hit
```

- Line 1 — on/off state + current scan settings
- Line 2 — live counters (queued, total /checks sent this zone, confirmations)
- Line 3 — last mob targeted by an auto-check (clears between ticks)
- Confirmed block — rolling list of IG hits, capped to `max_confirmed_shown`
- The newest hit is prefixed with `>>` and the whole panel flashes red for 5 s

---

## Tradeoffs / Gotchas

- The addon injects real `/check` packets against the live server. Keep `delay` sane (≥ 1 s) to avoid looking like a bot.
- `/check` in FFXI returns a valid response out to ~50 yalms; beyond that you just get no response, which means no false positives but also no detection.
- **Chat suppression is name-based with a 3 s window.** If you manually `/check` a mob the addon just auto-checked, your manual response is suppressed too. Also: a party chat line that happens to contain the same mob name within 3 s will be hidden. Toggle off with `//ig suppress off` if this bites.
- State is **per-zone**: confirmations clear when you zone. Same mob ID in the same zone won't re-alert until you `//ig clear` or zone out and back.
- Some NM-adjacent mobs (same family, similar level) may also return "impossible to gauge" — this addon surfaces *all* of them, not just the pops you're after. Eyeball the name.
- Trusts, pets, chocobos, and players are skipped (spawn_type filter).

---

## Troubleshooting

**HUD doesn't appear**
Run `//ig hud on`. If still hidden, `//ig test` to force an alert and drag the panel on-screen.

**Addon says enabled but no /checks happening**
- Run `//ig status` — make sure `enabled=true`
- Check there are mobs in range (`range` and `spawn_type == 16` filter)
- If `Queue` stays at 0, nothing matched the filter; increase `range` or move closer
- If `Queue > 0` but `Sent` isn't incrementing, `delay` may be too high for your observation window

**No sound**
- `//ig status` should show `sound=true` and a valid `sound_file`
- Use a full absolute path: `//ig soundfile C:\Windower4\addons\ImpossibleGauge\data\alert.wav`

**Chat suppression is hiding too much**
`//ig suppress off`. Drop `suppress_window` in `settings.xml` for a shorter blackout window.

**HUD stayed red after `//ig clear`** — fixed in v1.1+; update if you're on an older copy.

---

## Technical Notes

- Outgoing packet `0x0DD` — `/check` (fields: Target, Target Index, Check Type=0)
- Incoming packet `0x029` — action message (fields: Actor, Target, Param1/2, Actor Index, Target Index, Message)
- Action message ID `249` = `"${target}'s strength is impossible to gauge!"` (see `res/action_messages.lua`)
- `/check` range is ~50 yalms; this is larger than the melee/targeting range commonly assumed
- `spawn_type == 16` filters to actual monsters (excludes NPCs, pets, trusts, players)

---

## Changelog

- **1.2** — Chat suppression of auto-`/check` responses (on by default); `//ig suppress` toggle
- **1.1** — HUD with live state and red-flash alert; `//ig hud`, `//ig test`; `clear` now resets the flash
- **1.0** — Initial release: auto-scan, staggered /check, 0x029 detection, chat + sound alerts

---

## License

MIT — do whatever, credit appreciated.
