# Todo Capsule 更新发布流程

这份文档给未来维护者和其他 Agent 使用。目标是：换账号、换机器、换 Agent 后，仍然知道 Todo Capsule 应该如何发布新版，并且不会误提交密钥或覆盖本机已安装版本。

## Agent 执行约定

当用户说“发布”“发布到 GitHub”“更新上去”“再发布一次”时，默认含义是**完整发布一个可被 Sparkle 自动更新发现的新版本**，不是只执行 `git push`。

必须完成这条链路：

1. 确认当前代码已提交或先提交功能改动。
2. 将 `code/Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion` 递增。
3. 构建新的 DMG。
4. 用 Sparkle EdDSA 私钥签名 DMG。
5. 更新根目录 `appcast.xml`，包含新版本、build、DMG URL、length 和 `sparkle:edSignature`。
6. 更新 `README.md` 最新 DMG 链接。
7. 提交并推送 release 元数据。
8. 创建 GitHub Release，并上传 `.dmg` 和 `.sha256`。
9. 校验公开 raw appcast 和 GitHub Release asset URL。

如果只把源码提交推到 GitHub，已安装旧版本的 app 不会发现更新。

## 当前发布方式

- GitHub 仓库：`Seth360/todo-capsule`
- GitHub Releases 用来托管 DMG 安装包
- Sparkle 更新源：`https://raw.githubusercontent.com/Seth360/todo-capsule/main/appcast.xml`
- Sparkle 公钥写在 `code/Resources/Info.plist` 的 `SUPublicEDKey`
- 自动检查策略：`SUScheduledCheckInterval` 当前为 `3600` 秒；应用启动后还会调用一次 `checkForUpdatesInBackground()`，让用户不必手动点“检查更新…”才发现新版。
- Sparkle 私钥不能提交。当前本机有两处可用来源：
  - Keychain account: `todo-capsule`
  - 本地忽略文件：`code/.sparkle-private/todo-capsule-ed25519.key`
- 当前机器没有 `gh`，Git 也可能没有配置 credential helper。GitHub HTTPS 凭据可从 macOS Keychain 读取：
  - account: `129053598`
  - server: `github.com`

## 重要原则

- 不要提交 `code/.sparkle-private/`、`code/sparkle-updates/`、`.build/`、`*.app`、`*.dmg`。
- 不要把 Sparkle 私钥、公证凭证、GitHub token 写进仓库。
- 如果用户要验证自动更新，不要覆盖 `/Applications/TodoCapsule.app`。保持已安装旧版本，让 Sparkle 从 appcast 更新到新版本。
- 只有用户明确要求“更新本机应用程序”时，才把新 app 拷贝到 `/Applications`。
- 当前安装包未做 Apple Developer ID 签名和 notarization。GitHub 下载后可能触发 Gatekeeper 提示，这是签名公证问题，不是 Sparkle 问题。

## 发布新版步骤

下面以发布 `0.1.10`、build `11` 为例。实际发布时从当前 `Info.plist` 和 `appcast.xml` 的最新版本继续递增。为避免漏改，终端命令统一先设置变量：

```bash
VERSION="0.1.10"
BUILD="11"
TAG="v${VERSION}"
DMG_NAME="todo-capsule-v${VERSION}.dmg"
```

### 1. 修改版本号

编辑 `code/Resources/Info.plist`：

```xml
<key>CFBundleShortVersionString</key>
<string>0.1.10</string>
<key>CFBundleVersion</key>
<string>11</string>
```

同步更新根目录 `README.md` 的最新版 DMG 下载链接。

### 2. 构建 DMG

```bash
cd "/Users/seth/Documents/AI Python/todo-capsule/code"
./package-dmg.sh
```

生成文件：`code/todo-capsule.dmg`。

### 3. 准备 Sparkle 更新文件

```bash
rm -rf sparkle-updates
mkdir -p sparkle-updates
cp todo-capsule.dmg "sparkle-updates/${DMG_NAME}"
wc -c < "sparkle-updates/${DMG_NAME}"
shasum -a 256 "sparkle-updates/${DMG_NAME}"
```

记录输出的文件大小和 SHA256。

也要把 SHA256 写成同名 sidecar，供 GitHub Release 上传：

```bash
shasum -a 256 "sparkle-updates/${DMG_NAME}" \
  > "sparkle-updates/${DMG_NAME}.sha256"
```

### 4. 签名 DMG

优先使用本地忽略文件里的 Sparkle 私钥：

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --ed-key-file .sparkle-private/todo-capsule-ed25519.key \
  "sparkle-updates/${DMG_NAME}"
```

记录输出的 `sparkle:edSignature` 和 `length`。

如果 `.sparkle-private` 不存在，需要从 Keychain 或备份恢复私钥。不要重新生成公私钥，除非同时迁移所有已发布 app 的 `SUPublicEDKey` 策略。

### 5. 更新 appcast

编辑根目录 `appcast.xml`，把最新 item 改成新版本：

```xml
<title>0.1.10</title>
<sparkle:version>11</sparkle:version>
<sparkle:shortVersionString>0.1.10</sparkle:shortVersionString>
<enclosure
  url="https://github.com/Seth360/todo-capsule/releases/download/v0.1.10/todo-capsule-v0.1.10.dmg"
  length="填入第 3/4 步得到的 length"
  type="application/octet-stream"
  sparkle:edSignature="填入第 4 步得到的签名"/>
```

`pubDate` 用当前时间，格式示例：

```bash
date '+%a, %d %b %Y %H:%M:%S %z'
```

### 6. 本地校验

```bash
xmllint --noout ../appcast.xml

.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --ed-key-file .sparkle-private/todo-capsule-ed25519.key \
  --verify "sparkle-updates/${DMG_NAME}" "填入签名"
```

确认 app 内版本：

```bash
plutil -p TodoCapsule.app/Contents/Info.plist | rg "CFBundleShortVersionString|CFBundleVersion"
```

### 7. 提交并推送

只提交源码、`README.md`、`appcast.xml` 和 `Info.plist` 等需要进入仓库的文件：

```bash
cd "/Users/seth/Documents/AI Python/todo-capsule"
git status --short
git diff --check
git add README.md appcast.xml code/Resources/Info.plist code/Sources
git commit -m "release: prepare ${VERSION}"
git push origin main
```

如果 `git push` 报 `could not read Username for 'https://github.com': Device not configured`，说明命令行 Git 没接上 Keychain。可用临时 `GIT_ASKPASS` 从 Keychain 读取凭据推送，注意不要打印 token：

```bash
tmp_askpass=$(mktemp)
chmod 700 "$tmp_askpass"
printf '%s\n' '#!/bin/sh' \
  'case "$1" in' \
  '  *Username*) echo "129053598" ;;' \
  '  *Password*) security find-internet-password -s github.com -a 129053598 -w ;;' \
  '  *) echo "" ;;' \
  'esac' > "$tmp_askpass"
GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$tmp_askpass" git push origin main
push_code=$?
rm -f "$tmp_askpass"
exit $push_code
```

### 8. 创建 GitHub Release 并上传 DMG

如果安装了 `gh`：

```bash
gh release create "${TAG}" \
  "code/sparkle-updates/${DMG_NAME}" \
  "code/sparkle-updates/${DMG_NAME}.sha256" \
  --title "Todo Capsule ${VERSION}" \
  --notes "写入本次更新说明"
```

如果没有 `gh`，可以用 GitHub API。当前机器通常可通过 Keychain 取 token：

```bash
TOKEN=$(security find-internet-password -s github.com -a 129053598 -w)
```

创建 release：

```bash
TOKEN=$(security find-internet-password -s github.com -a 129053598 -w)
VERSION="${VERSION}" python3 - <<'PY' > /tmp/todo-capsule-release.json
import json
import os
version = os.environ["VERSION"]
body = """- 写入本次更新说明。"""
print(json.dumps({
    "tag_name": f"v{version}",
    "target_commitish": "main",
    "name": f"Todo Capsule {version}",
    "body": body,
    "draft": False,
    "prerelease": False
}, ensure_ascii=False))
PY
curl -fsSL \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/Seth360/todo-capsule/releases \
  -d @/tmp/todo-capsule-release.json \
  -o /tmp/todo-capsule-release-response.json
rm -f /tmp/todo-capsule-release.json
```

上传 DMG 和 SHA256：

```bash
TOKEN=$(security find-internet-password -s github.com -a 129053598 -w)
UPLOAD_URL=$(python3 - <<'PY'
import json
with open('/tmp/todo-capsule-release-response.json') as f:
    data = json.load(f)
print(data['upload_url'].split('{', 1)[0])
PY
)
for asset in "code/sparkle-updates/${DMG_NAME}" "code/sparkle-updates/${DMG_NAME}.sha256"; do
  name=$(basename "$asset")
  ctype="application/octet-stream"
  case "$name" in *.sha256) ctype="text/plain" ;; esac
  curl -fsSL \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: $ctype" \
    --data-binary @"$asset" \
    "$UPLOAD_URL?name=$name" \
    -o "/tmp/todo-capsule-upload-$name.json"
done
```

不要把 token 写进仓库、日志、release notes 或任何临时可提交文件。

### 9. 公开地址校验

```bash
curl -fsSL https://raw.githubusercontent.com/Seth360/todo-capsule/main/appcast.xml | rg "${VERSION}|sparkle:version|${DMG_NAME}|edSignature"

curl -I -L "https://github.com/Seth360/todo-capsule/releases/download/${TAG}/${DMG_NAME}"
```

确认 `content-length` 和 appcast 的 `length` 一致。

## 自动更新测试方式

测试 Sparkle 自动更新时：

1. 保持 `/Applications/TodoCapsule.app` 是旧版本。
2. 发布新版本到 GitHub Release。
3. 确认 `appcast.xml` 已经指向新版本。
4. 打开旧版本 app，菜单栏里点“检查更新…”，或等待自动检查。
5. 更新完成后再确认 `/Applications/TodoCapsule.app/Contents/Info.plist` 已变成新版本。

不要为了“看新界面”直接覆盖 `/Applications`，否则自动更新链路就没法验证。

## 常见问题

### GitHub 下载后提示 Apple 无法验证

这是因为当前 app 不是 Developer ID 签名并公证的正式分发包。自用可以右键打开或清除 quarantine；面向公开用户要申请 Apple Developer Program，并走 Developer ID signing、hardened runtime、notarization、staple。

### Sparkle 没有发现更新

检查：

- 已安装 app 的 `CFBundleVersion` 是否低于 appcast 的 `sparkle:version`
- `SUFeedURL` 是否仍指向 GitHub raw appcast
- appcast XML 是否可公开访问
- DMG `length` 和 `sparkle:edSignature` 是否匹配当前上传文件
- GitHub Release asset URL 是否能 `curl -I -L` 访问

### Sparkle 签名验证失败

通常是 DMG 在签名后又被重新打包或替换了。重新执行打包、复制到 `sparkle-updates`、`sign_update`、更新 appcast、上传 Release asset。
