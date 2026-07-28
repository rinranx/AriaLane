# Third-party notices

This inventory is based on AriaLane 1.0.0's pinned dependencies, imported
modules, resources, and release packaging scripts.

## Components distributed inside AriaLane.app

### Sparkle 2.9.2

- Project: <https://github.com/sparkle-project/Sparkle>
- Copyright: the Sparkle Project contributors listed in its license
- Primary license: MIT
- Distribution: `Sparkle.framework`, including its updater and XPC services

Sparkle includes code derived from bsdiff, sais-lite, ed25519, and
`SUSignatureVerifier.m`, under BSD-2-Clause, MIT, zlib, and BSD-2-Clause-style
terms respectively. The pinned upstream license text, including all of these
notices, is preserved verbatim in
[`Resources/Licenses/Sparkle-LICENSE.txt`](Resources/Licenses/Sparkle-LICENSE.txt)
and is copied into the released app.

### Public Sans

- Project: <https://github.com/uswds/public-sans>
- Copyright: Copyright 2015 The Public Sans Project Authors
- License: SIL Open Font License 1.1
- Distribution: the Regular, Medium, SemiBold, and Bold TTF files

The complete license text is stored at
[`Resources/Fonts/OFL.txt`](Resources/Fonts/OFL.txt) and is copied into the
released app with the font files.

## External runtime not distributed by AriaLane

AriaLane can discover, start, and communicate with a separately installed
[aria2](https://aria2.github.io/) executable over JSON-RPC. aria2 is licensed
under `GPL-2.0-or-later`. AriaLane does not copy, embed, statically link, or
redistribute aria2 or aria2's own runtime dependencies.

## Platform frameworks and marks

Swift, SwiftUI, AppKit, Charts, PhotosUI, Security, ServiceManagement,
UniformTypeIdentifiers, UserNotifications, Vision, and the other Apple
platform frameworks are supplied by macOS or Apple's developer tools; they are
not third-party binaries distributed inside AriaLane.

The X name and logo are trademarks of X Corp. The small X mark in AriaLane is
used only to identify a link to the author's X profile and does not imply
affiliation or endorsement.
