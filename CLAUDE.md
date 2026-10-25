# Notes for Claude Code

This code was written without Xcode, so it has not been compiled yet. First job on the Mac: `xcodegen && xcodebuild -scheme HHIL -destination 'generic/platform=iOS' build`, then fix compile errors.

Rules:
- Keep the layering: Features use Stores and the `Backend` protocol, never ConvexMobile directly.
- No hard coded colors or fonts in Features; add a token to `Theme` instead.
- Convex function names live only in `ConvexBackend.swift` and must match `backend/convex/*.ts` in the parent repo.
- Convex numbers decode via `@ConvexFloat` / `@OptionalConvexFloat`.
- iOS 27 only APIs (hinge) stay behind `#available` in `Platform/`.
