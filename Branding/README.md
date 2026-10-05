# Mac Companion artwork

`app-icon.png` is the user-approved **Linked screens** artwork: a wide Mac frame
and an upright phone frame sharing an edge, in white on blue. The user selected
this exact concept on 2026-10-03 for both applications and the website.

The master is an opaque, unmasked 1254 × 1254 PNG. Native asset catalogs and web
exports use the same artwork. `python3 scripts/export_brand_assets.py` resamples
it with macOS `sips`; no creative changes are applied during export. App icon
compilation uses Xcode's asset catalog compiler. No extra splash delay is added.

## Generation

Created with the built-in imagegen tool. Final prompt:

```text
Use case: logo-brand
Asset type: Preview-only app icon concept for Mac Companion, a Mac host application and an iPhone remote-control client.
Style/medium: Original, carefully designed Apple-platform app icon artwork. Simple bold geometry and balanced negative space, with subtle restrained depth. Readable at small sizes.
Scene/backdrop: A full square opaque blue background, consistent with the application's existing blue UI accents. White primary symbol.
Composition/framing: One centered symbol, ample safe margins, filled square canvas. No pre-rounded outer icon mask.
Text: None.
Constraints: An original symbol that conveys the relationship between a computer and its phone companion. No Apple logos, no copied SF Symbols, no tiny interface details, no gradients that obscure the silhouette, no lettering, no watermark, no surrounding devices or presentation sheet. This is a concept preview, not a screenshot or a shipping asset.
Primary request: A wide desktop screen frame and a tall phone frame interlock into one coherent symbol, sharing a clear structural edge. Use a thick clean white outline, simple interior negative space, and no desktop stand. The relationship of the wide and tall shapes should immediately read as two devices working together.
```
