#!/usr/bin/env bash
# Story 6.3 (SPEC §12.3 step 6, §12.4, A63, A86): the stable Sparkle feed, DIST/appcast.xml.
#   appcast.sh --tag vX.Y.Z --build N --zip DIST/Vigie-X.Y.Z.zip --signature SIG --repo OWNER/NAME --dist DIR
#              [--previous FILE|URL|none] [--dry-run]
# - A pre-release tag (vX.Y.Z-suffix) writes nothing: no beta feed before the public release (A63, Story 19.3).
# - One <item> per stable release, newest first: sparkle:version = build number (CFBundleVersion, Story 6.4),
#   sparkle:shortVersionString = X.Y.Z, sparkle:minimumSystemVersion = the deployment target of App/project.yml,
#   the enclosure on the release host (A86) with sparkle:edSignature and length from SIG (`sign-update.sh sign
#   --out`), and the notes of notes.sh as Markdown (<description sparkle:format="markdown">).
# - Earlier items are kept: --previous names the current feed (default: the releases/latest/download/appcast.xml of
#   REPO, the URL the app reads). A 404 means a first release; any other failure stops, so history is never
#   dropped silently. An item with the same build number or version as the new one is replaced (re-runs).
# - The finished feed is checked with xmllint and signed with sign-update.sh sign-feed (the app sets
#   SURequireSignedFeed). publish.sh uploads it with the other files of DIST.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
REL="$(dirname "${BASH_SOURCE[0]}")"

tag="" build="" zip="" sigfile="" repo="" dist="" previous=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) tag="${2-}"; shift 2 ;;
    --build) build="${2-}"; shift 2 ;;
    --zip) zip="${2-}"; shift 2 ;;
    --signature) sigfile="${2-}"; shift 2 ;;
    --repo) repo="${2-}"; shift 2 ;;
    --dist) dist="${2-}"; shift 2 ;;
    --previous) previous="${2-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "usage: appcast.sh --tag vX.Y.Z --build N --zip ZIP --signature SIG --repo OWNER/NAME --dist DIR [--previous FILE|URL|none] [--dry-run]" >&2; exit 2 ;;
  esac
done
[ -n "$tag" ] && [ -n "$dist" ] || die "--tag and --dist are required"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "invalid tag '$tag'"
version="${tag#v}"
if [[ "$version" == *-* ]]; then
  say "appcast: $tag is a pre-release; not listed in the stable appcast (A63)"
  exit 0
fi
[[ "$build" =~ ^[1-9][0-9]*$ ]] || die "--build must be a positive build number (CFBundleVersion)"
[[ "$repo" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || die "release repository '$repo' is not OWNER/NAME"
[ -n "$zip" ] && [ -n "$sigfile" ] || die "--zip and --signature are required"
[ -n "$previous" ] || previous="https://github.com/$repo/releases/latest/download/appcast.xml"
out="$dist/appcast.xml"
min_system="$(sed -nE 's/^[[:space:]]*MACOSX_DEPLOYMENT_TARGET:[[:space:]]*"?([0-9.]+)"?.*/\1/p' "$RELEASE_ROOT/App/project.yml" | head -1)"
[ -n "$min_system" ] || die "no MACOSX_DEPLOYMENT_TARGET in App/project.yml"

if [ "$DRY_RUN" = 1 ]; then
  say "+ previous items from $previous"
  say "+ write $out: item $version (build $build, minimum macOS $min_system), enclosure https://github.com/$repo/releases/download/$tag/$(basename "$zip")"
  say "notes:"; "$REL/notes.sh" --tag "$tag" | sed 's/^/  | /'
  say "+ xmllint --noout $out"
  "$REL/sign-update.sh" sign-feed --file "$out" --dry-run
  exit 0
fi

[ -f "$zip" ] || die "$zip not found"
[ -f "$sigfile" ] || die "$sigfile not found (sign-update.sh sign --out)"
command -v xmllint >/dev/null || die "xmllint not found"
signature="$(sed -n 's/^ed_signature=//p' "$sigfile")"
length="$(sed -n 's/^length=//p' "$sigfile")"
[[ "$signature" =~ ^[A-Za-z0-9+/]{86}==$ ]] || die "no EdDSA signature in $sigfile"
[ "$length" = "$(stat -f %z "$zip")" ] || die "$sigfile was made for another file (length $length, $zip is $(stat -f %z "$zip"))"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Previous items, verbatim.
: > "$tmp/items"
case "$previous" in
  none) ;;
  http://* | https://*)
    code="$(curl -sSL --retry 3 -o "$tmp/previous.xml" -w '%{http_code}' "$previous")" || die "cannot fetch $previous"
    case "$code" in
      200) ;;
      404) say "appcast: no feed at $previous yet (first stable release)"; rm -f "$tmp/previous.xml" ;;
      *) die "fetching $previous answered HTTP $code; refusing to drop earlier releases" ;;
    esac
    ;;
  *) [ -f "$previous" ] || die "$previous not found"; cp "$previous" "$tmp/previous.xml" ;;
esac
if [ -f "$tmp/previous.xml" ]; then
  xmllint --noout "$tmp/previous.xml" 2>/dev/null || die "the current appcast ($previous) is not well-formed XML"
  awk -v build="$build" -v version="$version" '
    /<item>/ { inside = 1; block = ""; skip = 0 }
    inside {
      block = block $0 "\n"
      if (index($0, "<sparkle:version>" build "</sparkle:version>")) skip = 1
      if (index($0, "<sparkle:shortVersionString>" version "</sparkle:shortVersionString>")) skip = 1
    }
    /<\/item>/ { if (inside && !skip) printf "%s", block; inside = 0 }
  ' "$tmp/previous.xml" > "$tmp/items"
fi

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
notes="$("$REL/notes.sh" --tag "$tag" | sed 's/]]>/]]]]><![CDATA[>/g')"
tag_time="$(git -C "$RELEASE_ROOT" for-each-ref --format='%(creatordate:unix)' "refs/tags/$tag" 2>/dev/null || true)"
[ -n "$tag_time" ] || tag_time="$(date +%s)"
pub_date="$(LC_ALL=C date -u -r "$tag_time" '+%a, %d %b %Y %H:%M:%S +0000')"
zip_name="$(basename "$zip")"
url="https://github.com/$repo/releases/download/$tag/$zip_name"

mkdir -p "$dist"
{
  cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Vigie</title>
    <link>https://github.com/$(printf '%s' "$repo" | xml_escape)</link>
    <description>Stable releases of Vigie.</description>
    <language>en</language>
    <item>
      <title>Version $version</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$min_system</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
$notes
]]></description>
      <enclosure url="$(printf '%s' "$url" | xml_escape)" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
XML
  cat "$tmp/items"
  cat <<XML
  </channel>
</rss>
XML
} > "$tmp/appcast.xml"
xmllint --noout "$tmp/appcast.xml" || die "generated appcast is not well-formed"
mv "$tmp/appcast.xml" "$out"
"$REL/sign-update.sh" sign-feed --file "$out"
say "appcast: $out ($(grep -c '<item>' "$out") item(s), newest $version build $build)"
