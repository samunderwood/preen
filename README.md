# Preen

A free, open-source menu bar app for macOS that takes tracking parameters and redirect wrappers out of links as you copy them, and leaves the rest of what you copied as it was. The menu shows what it removed from each link, with a way to restore the original.

Preen removes the parameters named in AdGuard's [URL Tracking filter](https://github.com/AdguardTeam/AdguardFilters) (its `$removeparam` rules) and the per-site parameters in the [ClearURLs rules](https://github.com/ClearURLs/Rules), and unwraps the redirect links ClearURLs knows, plus a few it doesn't, such as Outlook Safe Links. Both rule sets are bundled and refreshed once a day. Cleaning happens on the Mac.

## Download

[Preen for macOS 26 Tahoe or later](https://www.samunderwood.co.uk/preen). It's free, and it updates itself.

## How it reads the clipboard

macOS doesn't announce clipboard changes, so Preen checks the change count twice a second. When it changes, Preen asks the system's data detection whether the copy holds a link (`NSPasteboard.detectedPatterns(for:)`), which doesn't read the contents. It reads only copies with a link in them, so other copies are never read. Where macOS asks before apps read the clipboard (Apple's pasteboard privacy feature, opt-in through `EnablePasteboardPrivacyDeveloperPreview` so far), the question comes up only for links. Copies marked concealed or transient by password managers, and copies made in excluded apps, are left alone.

The Services menu's Clean Links and the Shortcuts action Clean Links work on text passed to them, not the clipboard.

## Building

The app depends on SamKit, a private package of interface and update code shared by my Mac apps, so it can't be built from this repository alone. The cleaning engine, PreenCore, is a separate Swift package with no dependencies, and builds and tests on its own:

```sh
cd Packages/PreenCore && swift test
```

`scripts/update-rules.sh` refreshes the bundled rules and the test fixtures; run the tests afterwards.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE). The AdGuard filter is GPL-3.0 and the ClearURLs rules are LGPL-3.0; see `Acknowledgements`.
