# Local Writing Assistant

A planned local-first macOS writing assistant for English, initially targeting Slack and later Google Docs.

## Intended experience

- Run as a native menu-bar app.
- Underline spelling and grammar issues in supported editors.
- Offer corrections on hover and apply them on click.
- Offer sentence rewrites on demand using a local language model.
- Keep text processing on-device, with no text logging and a pause control.

## Initial technical direction

- Swift and AppKit for the macOS app and suggestion overlays.
- macOS Accessibility APIs for supported desktop editors.
- macOS spellchecking for immediate spelling feedback.
- Benchmark a quantized 4B model via llama.cpp for grammar and rewrites.
- Target development hardware: Apple M3 with 32 GB memory.
- Investigate a companion browser extension for Google Docs.

## First milestone

Validate Slack accessibility support, then complete the read-text → detect-typo → position-underline → accept-correction workflow without disrupting typing.

## Status

Project setup only. No application implementation yet.
