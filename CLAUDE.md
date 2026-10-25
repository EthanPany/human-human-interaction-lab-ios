# Notes for Claude Code

CI builds every push for the simulator on Xcode 26 (see .github/workflows/build.yml). The iPhone Duo hinge code in Platform/Fold.swift is behind the HINGE_API flag, which is off: the iOS 27.0 beta SDK has no hinge symbols yet. Turn it on in project.yml once an SDK ships the API, and fix the names in Fold.swift then. The app builds and installs with Xcode 27 via scripts/install-on-phone.sh.

Work on the `ethan` branch and open pull requests into `main`.

Rules:
- Keep the layering: Features use Stores and the `Backend` protocol, never ConvexMobile directly.
- No hard coded colors or fonts in Features; add a token to `Theme` instead.
- Convex function names live only in `ConvexBackend.swift` and must match `backend/convex/*.ts` in the parent repo.
- Convex numbers decode via `@ConvexFloat` / `@OptionalConvexFloat`.
- iOS 27 only APIs (hinge) stay behind `#available` in `Platform/`.
- Fonts: run scripts/fetch-fonts.sh; never commit the font files (license).
- Avatar math lives in DesignSystem/Avatar; keep drawing in AvatarRenderer and timing in AvatarEngine.
