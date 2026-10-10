# Mac Companion website

A static product site with dedicated `/privacy/` and `/support/` routes,
responsive layouts, accessible navigation, light/dark/system appearance and
source-backed product copy. Availability explicitly describes private TestFlight;
there is no public beta or App Store download link. No forms or analytics scripts.

`source/` is authoritative. Shared header/footer fragments are composed by
`build.py`; generated `dist/` is not edited by hand. Build before preview:

```sh
python3 build.py
python3 check.py
node --check source/site.js
```

Start a local preview from this directory:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory dist
```

Open <http://127.0.0.1:4173/>. Stop the server with Control-C.

App artwork originates in `../Branding/app-icon.png`; the website retains its
approved exported icon. The original hero illustration was generated for this
site and is labeled as artwork, not an app screen. No private device screenshots
are published. The app's native catalogs and signing configuration are independent.

Fonts use the system stack; artwork, styles and scripts are served from the site.
The only browser storage is appearance preference. Product privacy disclosures
cover local credentials, optional iCloud Keychain sync, SSH encryption for desktop/input and Terminal
transport, Live Activities, Apple purchases and support.

The public site is hosted on Vercel at <https://mac.jenny.media/>, in the
`mac-companion` project under `xcv58s-projects`. `vercel.json` serves the generated
`dist/` directory, adds security headers and keeps the dedicated routes intact.
Run the build and checks above before deploying; upload only `vercel.json` and
`dist/`, never the native app sources, local settings or hosting credentials.

The earlier owner-private Sites preview uses `.openai/hosting.json` and remains
separate. Website deployment does not release the iOS app or open a public beta.
