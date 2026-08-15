# tools

## og-source.html

Source for `public/og.png`, the Open Graph card. It is a standalone 1200×630
page styled to match the hero (clay assets are inlined as data URIs, so it
renders offline).

To regenerate after changing the copy:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars --window-size=1200,630 \
  --screenshot="$PWD/public/og.png" \
  "file://$PWD/tools/og-source.html"
```

Replace it with a real app screenshot when one is available.
