# Human Human Interaction Lab: iOS

SwiftUI app for the Cal Hacks 13.0 project. Your phone, worn on a lanyard, becomes a live name badge. This repo is a submodule of [human-human-interaction-lab](https://github.com/EthanPany/human-human-interaction-lab).

Design: [Figma file](https://www.figma.com/design/fT0XfUlJq0W47Z33XfjnYY/Cal-Hack-13)

## Run it

1. `brew install xcodegen`
2. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and fill in `CONVEX_URL` (from `backend/.env.local` after `npx convex dev`), `AGENT_PHONE` (the Photon iMessage number) and `DEVELOPMENT_TEAM`.
3. `xcodegen` creates `HHIL.xcodeproj` (not committed; rerun after adding files).
4. Open it, pick your iPhone, Run. Do it on two phones to test proximity (Nearby Interaction needs real U1/U2 iPhones, not the simulator).

With no `CONVEX_URL` the app runs on `MockBackend` so the UI can still be clicked through.

## Layout

```
HHIL/
  App/            entry point, environment, root + tab view, config
  Core/
    Models/       Decodable types matching Convex query results
    Services/     Backend protocol, ConvexBackend, MockBackend
    Stores/       @Observable state: session, badge, router
    Nearby/       Nearby Interaction (UWB), one NISession per peer
    Recording/    on device speech transcription of conversations
  DesignSystem/   Theme tokens, BadgeStyle protocol, shared components
  Platform/       iPhone Duo hinge support (Fold.swift)
  Features/       one folder per screen: Badge, People, Profile, Settings, Onboarding
```

## Swapping in the final design

Views read every color, font and radius from `Theme`, and the badge is drawn by a `BadgeStyle`. To apply the designers' look, add a new `Theme` value and a new `BadgeStyle` (copy `WireframeBadgeStyle`) and set it in `HHILApp.swift`. No feature code needs to change.

## iPhone Duo

Closed (outer screen) wears the badge; opened shows the person you are talking to in People. Same tab bar layout, no sidebars. The hinge API lives only in `Platform/Fold.swift`; if the SDK names differ, fix them there.
