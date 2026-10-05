# Mac Companion local website

A static product preview using the approved shared app artwork. No registration,
remote forms, analytics, public download artifacts, or deployment is configured.
The page describes the current development beta and does not promise an App Store
or TestFlight release.

Start a local preview from this directory:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open <http://127.0.0.1:4173/>. Stop the server with Control-C.

App artwork originates in `../Branding/app-icon.png`. Regenerate resized assets
with `python3 ../scripts/export_brand_assets.py`. The native app catalogs are
consumed by `project.yml`; XcodeGen regenerates the checked-in Xcode project.

All fonts, artwork, styles, and scripts are served locally. A local preview does
not prepare public release packages or establish production acceptance.
