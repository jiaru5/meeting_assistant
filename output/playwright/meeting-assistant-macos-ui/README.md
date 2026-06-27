# Meeting Assistant macOS UI Mockups

This folder contains static product mockups for the Meeting Assistant macOS client.

## Files

- `mockups.html`: source file for all screens, with clickable anchors and route labels between screens.
- `render-screenshots.mjs`: Playwright renderer.
- `all-mockups.png`: full-page overview export.
- `00-journey-overview.png`: product journey and boundary map.
- `01-home-preflight.png`: app home and preflight checks.
- `02-record-setup.png`: recording setup.
- `03-recording-live.png`: live recording state.
- `04-saved-artifacts.png`: recorded session and artifact registry.
- `05-import-media.png`: import media fallback path.
- `06-processing.png`: audio normalization and transcript processing.
- `07-transcript-review.png`: transcript review and export.
- `08-dependency-error.png`: dependency missing error state.
- `09-delete-confirm.png`: delete confirmation.
- `10-product-surfaces.png`: complete MVP surface inventory.

## Navigation Relationships

Open `mockups.html` in a browser to view the full clickable atlas. Each artboard has a route strip with:

- `From`: where this screen is entered from.
- `Current`: current screen.
- `Primary next`: the normal next step in the user journey.
- `Branch`, `Failure`, `Invalid input`, or `Cancel`: alternate jumps and exception paths.

The main flow is:

`00 Journey overview` -> `01 Home / preflight` -> `02 Recording setup` -> `03 Recording live` -> `04 Saved artifacts` -> `06 Processing` -> `07 Transcript review`.

Important branches:

- `01 Home / preflight` -> `05 Import media` -> `06 Processing`.
- `01 Home / preflight`, `02 Recording setup`, `03 Recording live`, `05 Import media`, or `06 Processing` -> `08 Dependency / error state` -> `01 Home / preflight`.
- `04 Saved artifacts` or `07 Transcript review` -> `09 Delete confirmation`.
- `00 Journey overview` -> `10 Product surfaces` for the complete screen inventory.

## Design Direction

The visual direction adapts the public Vercel Geist design tokens and product-design tone: light surfaces, strict black-and-white hierarchy, compact type, thin borders, small radii, sparse accent colors, and dense operational information.

The screens are product-design targets, not current implementation screenshots. They separate target UX from current implementation state where relevant.

## Regenerate

From the repository root:

```bash
npx --yes --package playwright node output/playwright/meeting-assistant-macos-ui/render-screenshots.mjs
```
