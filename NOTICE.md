# Notices

## Origin

Kechil PRO was written against public JPEG/JFIF, PNG, WebP, C2PA and IPTC standards.
No source, styling, copy or assets were taken from another metadata tool or website.

## Third-party components

### libwebp 1.6.0

The app statically links the WebP encoder from the official libwebp source distribution,
vendored at `vendor/libwebp`. The exact source tree is pinned by
`vendor/libwebp.sha256` and verified by `tools/check.sh`.

Copyright (c) 2010, Google Inc. All rights reserved.

libwebp is distributed under the BSD 3-Clause license. Its complete license text is
included at `vendor/libwebp/COPYING`.

### Pillow

`Tests/verify_algorithm.py` uses Pillow only during development-time verification to
create fixtures and compare decoded pixels. Pillow is not distributed in the app and is
released under the MIT-CMU license.

## Trademarks

Apple, macOS, Finder and Xcode are trademarks of Apple Inc. SynthID is a Google product
name. C2PA and Content Credentials are marks of their respective organisations. GitHub,
Ko-fi and PayPal are marks of their respective owners. Names are used only for accurate
technical description and imply no endorsement.

## License

Kechil PRO is released under GNU GPL v3.0. See [LICENSE](LICENSE).
