# BattleLine v1 product specification

## Confirmed product decisions

- Display name: `BattleLine`
- Bundle identifier: `com.ityut.battleline`
- Deployment target: iOS 26.0
- UI and QA baseline: iPhone 13 and iOS 26
- Device family: iPhone; no runtime block for particular iPhone models
- Match mode: nearby multiplayer only
- Transport: pure Bluetooth Low Energy only
- Cards: troop cards only
- Troop deck: six colors, each containing values 1 through 10 exactly once
  - red
  - orange
  - yellow
  - green
  - blue
  - purple
- Advanced claiming is a match-setup option and is not a persistent battle UI
  label.
- Battle layout: landscape layout D
  - three adjacent battle lines visible at once
  - one-row hand
  - fixed command area
  - controls to move the visible three-line window across all nine flags

## Player nickname

- After the launch animation, players without a saved nickname must enter one
  before accessing the home screen, including after upgrading an older install.
- The nickname is stored locally and reused on subsequent launches.
- Home has a Settings button at the top right. Settings > Personal information
  allows editing and explicitly saving the nickname; returning discards edits.
- Creating and joining matches displays the nickname without an editing field.
- Nickname changes apply only to new matches. Existing matches, including paused
  and restored matches, keep the nickname stored in their session.
- Nicknames allow internal spaces and emoji, trim leading/trailing whitespace,
  and normalize Unicode to NFC. The limit is 20 extended grapheme clusters and
  1,024 UTF-8 bytes. Blank names, line breaks, control characters and bidi
  formatting controls are rejected; emoji joiners and flag tags are retained.

## Rule source

The supplied five-page rulebook is the authoritative product rule source.
The first version excludes every tactics-card rule.

## Nearby match constraints

- One device is the authoritative host.
- The other device sends action intents with an expected state version.
- The host validates every action with the same rules engine used by the UI.
- Repeated command identifiers are idempotent.
- The joining device never stores the opponent's hand or deck order.
- Both players keep the app in the foreground for discovery and play.
- A disconnect pauses input. The host retains the authoritative match for
  foreground reconnection; automatic host migration is out of scope.

## Visual asset policy

Version 1 uses original, code-drawn placeholder cards, flags, and surfaces. It
does not copy the rulebook's card illustrations or page artwork.

