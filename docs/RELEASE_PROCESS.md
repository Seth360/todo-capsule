# Todo Capsule 更新发布流程

这份文档给未来维护者和其他 Agent 使用。目标是：换账号、换机器、换 Agent 后，仍然知道 Todo Capsule 应该如何发布新版，并且不会误提交密钥或覆盖本机已安装版本。

## 当前发布方式

- GitHub 仓库：`Seth360/todo-capsule`
- GitHub Releases 用来托管 DMG 安装包
- Sparkle 更新源：`https://raw.githubusercontent.com/Seth360/todo-capsule/main/appcast.xml`
- Sparkle 公钥写在 `code/Resources/Info.plist` 的 `SUPublicEDKey`
- Sparkle 私钥不能提交。当前本机有两处可用来源：
  - Keychain account: `todo-capsule`
  - 本地忽略文件：`code/.sparkle-private/todo-capsule-ed25519.key`

## 重要原则

- 不要提交 `code/.sparkle-private/`、`code/sparkle-updates/`、`.build/`、`*.app`、`*.dmg`。
- 不要把 Sparkle 私钥、公证凭证、GitHub token 写进仓库。
- 如果用户要验证自动更新，不要覆盖 `/Applications/TodoCapsule.app`。保持已安装旧版本，让 Sparkle 从 appcast 更新到新版本。
- 只有用户明确要求“更新本机应用程序”时，才把新 app 拷贝到 `/Applications`。
- 当前安装包未做 Apple Developer ID 签名和 notarization。GitHub 下载后可能触发 Gatekeeper 提示，这是签名公证问题，不是 Sparkle 问题。

## 发布新版步骤

下面以发布 `0.1.5`、build `6` 为例。

### 1. 修改版本号

编辑 `code/Resources/Info.plist`：

```xml
<key>CFBundleShortVersionString</key>
<string>0.1.5</string>
<key>CFBundleVersion</key>
<string>6</string>
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
cp todo-capsule.dmg sparkle-updates/todo-capsule-v0.1.5.dmg
wc -c < sparkle-updates/todo-capsule-v0.1.5.dmg
shasum -a 256 sparkle-updates/todo-capsule-v0.1.5.dmg
```

记录输出的文件大小和 SHA256。

### 4. 签名 DMG

优先使用本地忽略文件里的 Sparkle 私钥：

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update \
  --ed-key-file .sparkle-private/todo-capsule-ed25519.key \
  sparkle-updates/todo-capsule-v0.1.5.dmg
```

记录输出的 `sparkle:edSignature` 和 `length`。

如果 `.sparkle-private` 不存在，需要从 Keychain 或备份恢复私钥。不要重新生成公私钥，除非同时迁移所有已发布 app 的 `SUPublicEDKey` 策略。

### 5. 更新 appcast

编辑根目录 `appcast.xml`，把最新 item 改成新版本：

```xml
<title>0.1.5</title>
<sparkle:version>6</sparkle:version>
<sparkle:shortVersionString>0.1.5</sparkle:shortVersionString>
<enclosure
  url="https://github.com/Seth360/todo-capsule/releases/download/v0.1.5/todo-capsule-v0.1.5.dmg"
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
  --verify sparkle-updates/todo-capsule-v0.1.5.dmg "填入签名"
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
git commit -m "release: prepare 0.1.5"
git push origin main
```

### 8. 创建 GitHub Release 并上传 DMG

如果安装了 `gh`：

```bash
gh release create v0.1.5 \
  code/sparkle-updates/todo-capsule-v0.1.5.dmg \
  code/sparkle-updates/todo-capsule-v0.1.5.dmg.sha256 \
  --title "Todo Capsule 0.1.5" \
  --notes "写入本次更新说明"
```

如果没有 `gh`，可以用 GitHub API。当前机器通常可通过 Git credential 取 token：

```bash
TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential fill | awk -F= '/^password=/{print $2}')
```

然后用 `curl` 创建 release 和上传 assets。参考之前发布命令即可，但不要把 token 写进文件。

### 9. 公开地址校验

```bash
curl -fsSL https://raw.githubusercontent.com/Seth360/todo-capsule/main/appcast.xml | rg "0.1.5|sparkle:version|todo-capsule-v0.1.5|edSignature"

curl -I -L https://github.com/Seth360/todo-capsule/releases/download/v0.1.5/todo-capsule-v0.1.5.dmg
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
