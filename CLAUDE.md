# Notes for Claude Code

CI builds every push for the simulator on Xcode 26 (see .github/workflows/build.yml). The iPhone Duo hinge code in Platform/Fold.swift only compiles with the iOS 27 SDK (gated by the HINGE_API flag set per SDK in project.yml), so build it once on the Mac with Xcode 27 and fix it there if the API names differ.

Work on the `ethan` branch and open pull requests into `main`.

Rules:
- Keep the layering: Features use Stores and the `Backend` protocol, never ConvexMobile directly.
- No hard coded colors or fonts in Features; add a token to `Theme` instead.
- Backend function names live only in `ConvexBackend.swift` and `SpacetimeBackend.swift`, and must match `backend/convex/*.ts` (and the `spacetime/` module routes) in the parent repo.
- Convex numbers decode via `@ConvexFloat` / `@OptionalConvexFloat`.
- iOS 27 only APIs (hinge) stay behind `#available` in `Platform/`.
- Fonts: run scripts/fetch-fonts.sh; never commit the font files (license).
- Avatar math lives in DesignSystem/Avatar; keep drawing in AvatarRenderer and timing in AvatarEngine.
