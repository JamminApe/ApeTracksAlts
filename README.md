# ApeTracksAlts

A lightweight World of Warcraft addon for **Project Ascension** (3.3.5) that tracks item counts, gold, and character data across all your alts — displayed directly in item tooltips.

Built by **JamminApe**.

---

## Features

### Phase 1 — Core Tracking ✅
- **Item tooltips** — hover any item and instantly see how many you have across all characters on the realm, broken down by Bags, Bank, and Mailbox
- **Gold tracking** — records each character's gold on login and whenever money changes; summarized with `/ata gold`
- **Stale data indicator** — characters not logged into in 7+ days are flagged with a red `[stale]` tag
- **Auto-pruning** — zero-count item entries are silently cleaned from the DB on every login to keep saves lean
- **Multi-character DB** — data persists across sessions per realm, building up as you log into each alt

### Coming Soon
- **Phase 2** — Character panel UI (`/ata show`), level & spec tracking, minimap button
- **Phase 3** — Item search (`/ata find`), ignore list, toggle per location
- **Phase 4** — Crafting deficit view, equipped gear tracking, profession skill tracking

---

## Installation

1. Download or clone this repository
2. Copy the `ApeTracksAlts` folder into your addons directory:
   ```
   World of Warcraft\Interface\AddOns\ApeTracksAlts\
   ```
3. Make sure the folder contains:
   ```
   ApeTracksAlts.toc
   Core.lua
   Gold.lua
   Tooltip.lua
   ```
4. Launch the game and enable **ApeTracksAlts** in the addon list

---

## Slash Commands

| Command | Description |
|---|---|
| `/ata` | Show help and all available commands |
| `/ata list` | List all tracked characters with level, class, gold, and stale flag |
| `/ata gold` | Show gold breakdown across all alts with account total |
| `/ata debug` | Show DB stats — character count and unique items tracked |
| `/ata reset` | Wipe the database (current character is re-seeded immediately) |

---

## Tooltip Example

When you hover over an item, ApeTracksAlts adds a section at the bottom of the tooltip:

```
ApeTracksAlts
Shadowyforce    Bags: 20  Bank: 181  Total: 201
Altcharacter    Bags: 40             Total: 40

Account Total   241
```

- Character names are colored by class
- Only locations with items are shown — no empty labels
- Your currently logged-in character always appears first
- Stale characters sort to the bottom with a [stale] tag
- Account Total reflects everything across all alts

---

## File Structure

```
ApeTracksAlts/
├── ApeTracksAlts.toc   # Addon metadata and load order
├── Core.lua            # DB, scanning (bags/bank/mail), events, slash commands
├── Gold.lua            # Gold tracking and coin item tooltip hook
└── Tooltip.lua         # Item tooltip hook and display logic
```

---

## Development

### Branching strategy
- `main` — stable, tested releases only
- `phase-X` — active development branch for each phase
- Tags mark each completed phase: `v1.0-phase1`, `v1.0-phase2`, etc.

### Rolling back
If a phase introduces a breaking issue, roll back to the last tagged baseline:
```
git checkout v1.0-phase1
```

### Saved variable
All data is stored in `ApeTracksAltsDB` inside your WTF folder:
```
WTF\Account\ACCOUNTNAME\SavedVariables\ApeTracksAlts.lua
```
Structure per character:
```lua
ApeTracksAltsDB = {
    ["RealmName"] = {
        ["CharacterName"] = {
            class    = "ROGUE",
            level    = 60,
            gold     = 150000,   -- in copper
            lastSeen = 1746000000,
            items    = {
                [2592] = { inv = 0, bnk = 20, mb = 0 },
            }
        }
    }
}
```

---

## Compatibility

- **Server:** Project Ascension (Warcraft Reborn)
- **Patch:** 3.3.5 (Interface version 30300)
- **Tested on:** Bronzebeard realm

---

## Changelog

### v1.0 — Phase 1
- Core item tracking across bags, bank, and mailbox
- Gold and level tracking per character
- Stale data detection (7-day threshold)
- Auto-pruning of zero-count DB entries
- Debounced bank and mail rescans on live item changes
- Class-colored character names in tooltips
- `/ata list`, `/ata gold`, `/ata debug`, `/ata reset` commands
