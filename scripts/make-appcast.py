"""Write the Sparkle appcast of one Moonvibe release to stdout.

The release notes are the version's section of CHANGELOG.md, as markdown. The enclosure
attributes (sparkle:edSignature and length) come from Sparkle's sign_update run on the DMG.
Moonvibe requires a signed appcast (SURequireSignedFeed): run sign_update on the result too.

Usage: make-appcast.py VERSION DMG_URL ENCLOSURE_ATTRIBUTES MINIMUM_MACOS CHANGELOG
"""

import re
import sys
from email.utils import formatdate
from xml.sax.saxutils import escape, quoteattr

version, dmg_url, enclosure, minimum_macos, changelog = sys.argv[1:6]

if not re.fullmatch(r'sparkle:edSignature="[A-Za-z0-9+/=]+" length="\d+"', enclosure):
    sys.exit(f"Unexpected enclosure attributes from sign_update: {enclosure}")

# Each version's section starts with "## <version> · <name> · <date>"
lines = open(changelog, encoding="utf-8").read().splitlines()
start = next((i for i, line in enumerate(lines) if re.match(rf"## {re.escape(version)}(\s|$)", line)), None)
if start is None:
    sys.exit(f"{changelog} has no section for {version}")
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
notes = "\n".join(lines[start + 1:end]).strip()
if not notes or "]]>" in notes:
    sys.exit(f"The {version} section of {changelog} is empty or can't go in CDATA")

print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Moonvibe</title>
    <item>
      <title>Moonvibe {escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(version)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(minimum_macos)}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
{notes}
]]></description>
      <enclosure url={quoteattr(dmg_url)} type="application/x-apple-diskimage" {enclosure}/>
    </item>
  </channel>
</rss>""")
