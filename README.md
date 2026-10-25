# Human Human Interaction Lab: iOS

SwiftUI app for the Cal Hacks 13.0 project. Your phone, worn on a lanyard, becomes a live name badge. This repo is a submodule of [human-human-interaction-lab](https://github.com/EthanPany/human-human-interaction-lab).

Design: [Figma file](https://www.figma.com/design/fT0XfUlJq0W47Z33XfjnYY/Cal-Hack-13)

## Run it

1. `brew install xcodegen`, then `./scripts/fetch-fonts.sh` (General Sans; the license doesn't allow committing the font files)
2. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and fill in `CONVEX_URL` (from `backend/.env.local` after `npx convex dev`), `AGENT_PHONE` (the Photon iMessage number) and `DEVELOPMENT_TEAM`.
3. `xcodegen` creates `HHIL.xcodeproj` (not committed; rerun after adding files).
4. Open it, pick your iPhone, Run. Do it on two phones to test proximity (Nearby Interaction needs real U1/U2 iPhones, not the simulator).

With no `CONVEX_URL` the app runs on `MockBackend`, which cycles the badge through idle, approaching, talking and saved so every state can be seen on one phone.

CI (`.github/workflows/build.yml`) builds every push on the newest Xcode GitHub has.

## Layout

```
HHIL/
  App/            entry point, environment, root + tab view, config
  Core/
    Models/       Decodable types matching Convex query results
    Services/     Backend protocol, ConvexBackend, SpacetimeBackend (HTTP, same function names as spacetime/src/http.ts), MockBackend
    Stores/       @Observable state: session, badge, router
    Nearby/       Nearby Interaction (UWB), one NISession per peer
    Recording/    on device speech transcription of conversations
  DesignSystem/   Theme tokens, BadgeStyle protocol, shared components
  Platform/       iPhone Duo hinge support (Fold.swift)
  Features/       one folder per screen: Badge, People, Profile, Settings, Onboarding
```

## Design

The look follows the designer's Figma page: cream surfaces, General Sans, the red/yellow/purple/green/blue palette, cream icon buttons with a soft shadow.

- `DesignSystem/Theme.swift`: every color, font and radius. Views never hard code them.
- `DesignSystem/Background/FlowingBackground.swift`: the designer's blurred colors as a `MeshGradient` that drifts slowly, bleeds colors together and leans with the phone's tilt.
- `DesignSystem/Avatar/`: the living avatar. Each shape (blob, puzzle, circle, triangle, square, pill, flower) is a polar radius function, so shapes morph into each other and wobble like jelly. Two eyes blink, glance around and follow the match (UWB direction) or the phone's tilt. Expressions (idle, sleepy, curious, excited, happy, love) are parameter sets the engine eases between, the same idea as procedural robot eyes (RoboEyes, Cozmo) and Rive state machines.
- `AvatarTint`: nobody near, your own color. A match approaching tints you toward the shared color, pale when far, saturated and deeper when close.
- `DesignSystem/Badge/`: the badge. Huge name, company, a title line that flips to whatever the nearby person cares about, location pill, and the yellow interests block (badge tags and hobbies merged, plus photo moments). Layouts: avatar, photo and text, full photo, each with its own type scale. When two people start talking, their avatar jumps into your frame along an arc and lands beside yours.

To restyle, make a new `Theme` and `BadgeStyle` and set them in `HHILApp.swift`. No feature code changes.

## iPhone Duo

Closed (outer screen) wears the badge; opened shows the person you are talking to in People. Same tab bar layout, no sidebars. The hinge API lives only in `Platform/Fold.swift`; if the SDK names differ, fix them there.
