#!/usr/bin/env bash
# 打成 DMG（自用/分发）。
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh

DMG="todo-capsule.dmg"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R TodoCapsule.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "todo-capsule" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "✅ $(pwd)/$DMG"
echo
echo "⚠️ 未做 Developer ID 签名 + 公证(notarize)。"
echo "   · 自用：右键 .app → 打开（绕过 Gatekeeper）即可。"
echo "   · 分发给别人：需要你的 Apple Developer 证书，"
echo "     codesign --sign \"Developer ID Application: <你的名字>\" TodoCapsule.app"
echo "     再 xcrun notarytool submit ... 公证。透明胶囊与 Mac App Store 基本无缘，走直装/DMG。"
