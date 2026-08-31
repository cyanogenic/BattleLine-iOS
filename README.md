# BattleLine

BattleLine is an iPhone-first, nearby multiplayer implementation of the
troop-card game described in `battle-line-rulebook-v2.pdf`.

## Version 1 scope

- Two nearby iPhones connected directly with Bluetooth Low Energy.
- Sixty troop cards: red, orange, yellow, green, blue, and purple, numbered
  1 through 10 in each color.
- Nine flags, standard formations, manual flag claims, and immediate victory
  on three adjacent flags or any five flags.
- Standard claiming or the advanced "claim only at the beginning of a turn"
  rule, selected before the match starts.
- Host-authoritative state validation. A joining device receives only its
  player view and never the opponent's hand or the deck order.
- Landscape battle screen with nine continuously scrolling lines, at least
  three fully visible lines, softened scroll edges, a one-row hand, and a fixed
  command area. Scrolling preserves the selected play target.

Version 1 does not include tactics cards, AI, internet play, accounts, cloud
services, or background Bluetooth discovery.

## Requirements

- Xcode 26 or newer
- iOS deployment target 26.0
- Two physical iPhones for BLE validation

Core rule tests run independently with:

```sh
swift test --package-path Packages/BattleLineCore
```

The app can be built without signing for the simulator with:

```sh
xcodebuild \
  -project BattleLine.xcodeproj \
  -scheme BattleLine \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

BLE discovery and transfer are unavailable in the iOS Simulator and require
two signed physical-device builds.

