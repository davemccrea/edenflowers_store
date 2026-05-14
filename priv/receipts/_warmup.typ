// Compiled at image-build / CI-setup time to populate the Typst package
// cache so the first real receipt render doesn't fetch packages
// (and write download progress to stderr) at request time.
//
// Keep this in sync with the @preview imports in receipt.typ.

#import "@preview/tiaoma:0.3.0": qrcode

// A trivial body — we only need typst to resolve the imports above.
// Compiled output is discarded.
#set page(width: 1cm, height: 1cm, margin: 0pt)
