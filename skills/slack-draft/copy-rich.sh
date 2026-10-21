#!/bin/sh
# Puts an HTML file on the macOS clipboard as HTML, RTF and plain text, then reads
# each back. Slack's message box keeps link text, bold, lists and code only from a
# rich paste, and a target that reads plain text alone still gets the words.
#
#   copy-rich.sh <file.html>
#
# Exits non-zero when a type is missing after the write.
set -eu

html=${1:-}
if [ -z "$html" ] || [ ! -f "$html" ]; then
  echo "usage: copy-rich.sh <file.html>" >&2
  exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

textutil -convert rtf -inputencoding UTF-8 -output "$tmp/draft.rtf" "$html"
textutil -convert txt -inputencoding UTF-8 -output "$tmp/draft.txt" "$html"

osascript -l JavaScript - "$html" "$tmp/draft.rtf" "$tmp/draft.txt" <<'EOF'
ObjC.import("AppKit");
function run(argv) {
  const pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  pb.setStringForType($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null), "public.html");
  pb.setDataForType($.NSData.dataWithContentsOfFile(argv[1]), "public.rtf");
  pb.setStringForType($.NSString.stringWithContentsOfFileEncodingError(argv[2], $.NSUTF8StringEncoding, null), "public.utf8-plain-text");
  const html = ObjC.unwrap(pb.stringForType("public.html")) || "";
  const rtf = pb.dataForType("public.rtf");
  const text = ObjC.unwrap(pb.stringForType("public.utf8-plain-text")) || "";
  const links = (html.match(/<a\s/g) || []).length;
  if (!html || rtf.isNil() || !text) {
    throw new Error("clipboard is missing a type: html " + html.length + ", rtf " + (rtf.isNil() ? 0 : rtf.length) + ", text " + text.length);
  }
  return "clipboard: html " + html.length + " chars with " + links + " links, rtf " + rtf.length + " bytes, text " + text.length + " chars\n" + text.slice(0, 120);
}
EOF
