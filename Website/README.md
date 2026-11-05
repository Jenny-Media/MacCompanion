# Mac Companion website

A static product site with dedicated `/privacy/`, `/support/` and unlisted `/beta/` routes,
responsive layouts, accessible navigation, light/dark/system appearance and
source-backed product copy. The hero uses the same official Apple download badge
as FrameWink, with App Store links in navigation, the closing section, footer and
support. The unlisted beta route remains separate. No forms or analytics scripts.

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

The homepage uses prepared native app captures in matching device frames for
iPhone, iPad, and iPhone Duo. Desktop, Compose Text, Terminal, Trackpad & Keyboard,
and Files have screenshot-led showcases. Duo has dedicated Book and Tabletop
examples, and is represented in navigation, pricing, and FAQ.

The hero and pricing lead with **One Mac. Free forever.** The free limit refers to
one saved remote Mac, not one client device. The iOS 1.1 release was verified on
Apple's public App Store on November 4, 2026. The official download URL is
<https://apps.apple.com/app/id6819496840>. Lifetime Pro is a $9.99 U.S. one-time
upgrade; the optional 14-day trial does not renew or charge. Local prices may vary.
Download wording follows the other released Jenny Media app websites; the beta
invitation stays out of public navigation and search indexing.

Only the explicitly requested, sanitized website marketing exports are tracked
under `source/assets/screens/`. Raw captures, capture adapters, input fixtures,
and review evidence stay outside application Git. No private device screenshots
are published. See [the asset notes](source/assets/screens/README.md) for source,
sample-content disclosure, and proportional export details. The app's native
catalogs and signing configuration are independent.

App artwork originates in `../Branding/app-icon.png`; the website retains its
approved exported icon. Appearance follows the system until the visitor chooses
a theme. Each click on the header button visibly switches between light and
dark and saves that choice across routes and reloads. Existing saved System
preferences still follow the OS. Public navigation does not expose the unlisted
beta invitation.

Fonts use the system stack; artwork, styles and scripts are served from the site.
The only browser storage is appearance preference. Product privacy disclosures
cover local credentials, iOS 1.1 local backups and optional iCloud Keychain sync,
SSH encryption for desktop/input and Terminal transport, Live Activities, Apple
purchases and support.

The public site is hosted on Vercel at <https://mac.jenny.media/>, in the
`mac-companion` project under `xcv58s-projects`. `vercel.json` serves the generated
`dist/` directory, adds security headers and keeps the dedicated routes intact.
Run the build and checks above before deploying; upload only `vercel.json` and
`dist/`, never the native app sources, local settings or hosting credentials.

The earlier owner-private Sites preview uses `.openai/hosting.json` and remains
separate. Website deployment does not release the iOS app or open a public beta.
