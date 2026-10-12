# 7-Zip console component

- Upstream: https://www.7-zip.org/ and https://github.com/ip7z/7zip
- Version: 26.03, published 2026-09-03.
- Source: https://github.com/ip7z/7zip/releases/download/26.03/7z2603-src.tar.xz
- Original macOS distribution (license / manual): https://github.com/ip7z/7zip/releases/download/26.03/7z2603-mac.tar.xz
- The bundled executable is compiled from the unmodified upstream source for Intel x86_64 and Apple Silicon arm64 (universal), with macOS deployment target 12.0. Rebuild via scripts/build-7zip.sh.
- The complete corresponding source is included in 7z2603-src.tar.xz. Upstream's LGPL and additional unRAR / BSD notices apply to this separately executed component, not iTools's own MIT source.
- See License.txt and COPYING.LGPL.txt. No proprietary FastZip or iRightMouse files are redistributed.
- iTools invokes this executable through Process, without a shell. Passwords are sent through stdin, never command arguments. AES ZIP requires a compatible extractor.
