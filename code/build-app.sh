#!/usr/bin/env bash
# 打成正式 TodoCapsule.app（显示 Dock 图标）。开机自启需要这个 bundle。
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release

APP="TodoCapsule.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/TodoCapsule "$APP/Contents/MacOS/TodoCapsule"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

PROXY_APP_TOKEN="${TC_PROXY_APP_TOKEN:-}"
if [[ -z "$PROXY_APP_TOKEN" ]]; then
  PROXY_APP_TOKEN="$(security find-generic-password -s "todo-capsule-proxy-app-token" -a "${USER}" -w 2>/dev/null || true)"
fi
if [[ -n "$PROXY_APP_TOKEN" ]]; then
  /usr/libexec/PlistBuddy -c "Delete :TCProxyAppToken" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :TCProxyAppToken string ${PROXY_APP_TOKEN}" "$APP/Contents/Info.plist"
  echo "==> 已注入预设模型 App Token"
else
  echo "==> 未设置 TC_PROXY_APP_TOKEN，发布包将无法调用受保护的预设模型代理"
fi

SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/TodoCapsule" 2>/dev/null || true
else
  echo "ERROR: Sparkle.framework 未找到。请先运行 swift build -c release。" >&2
  exit 1
fi

# 真实跑出来的问题：ad-hoc 签名（-sign -）的签名值是基于二进制内容算的哈希，每次改代码重新打包
# 签名就会变——macOS TCC 的授权记录是按"bundle ID + 签名身份"认的，签名一变就被当成"新app"，
# 之前点过的"允许访问桌面"全部失效，每次重新打包运行都要重新弹一遍系统权限框。改用本机已有的稳定
# 自签名证书（同一个身份，不随二进制内容变化），只要证书不变，TCC 授权就能跨重新打包持续有效——
# 只需要用户在换证书后的第一次运行时再点一次"允许"，之后不用每次重新点。
CODESIGN_IDENTITY="Mandarin Dictation Local"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${CODESIGN_IDENTITY}"; then
  codesign --force --deep --sign "${CODESIGN_IDENTITY}" "$APP" 2>/dev/null && echo "==> 稳定身份签名 OK (${CODESIGN_IDENTITY})" || echo "==> codesign 跳过（不影响自用运行）"
else
  codesign --force --deep --sign - "$APP" 2>/dev/null && echo "==> ad-hoc 签名 OK（未找到稳定证书 ${CODESIGN_IDENTITY}，回退 ad-hoc——每次重新打包会再弹一次系统权限框）" || echo "==> codesign 跳过（不影响自用运行）"
fi

echo "✅ 打包完成：$(pwd)/$APP"
echo "   运行：open ./$APP        （或拖进 /Applications）"
echo "   开机自启：跑起来后菜单栏 ✓ → 开机自启（首次可能要去 系统设置→通用→登录项 批准）"
