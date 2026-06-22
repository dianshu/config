---
name: xiaohongshu-note
description: 抓取并整理小红书图文笔记，输出一份整篇合并版正文。当用户分享小红书笔记时使用——触发信号包括：消息含 xhslink.com 短链、xiaohongshu.com 链接，或小红书 App「复制链接」出来的整段分享文本（形如「…标题…正文开头… http://xhslink.com/… 复制后打开【小红书】查看笔记！」）。流程：用 linkparser 公开 API 取全部高清原图 → 逐图 OCR 得正文 → 用 defuddle 取文案描述 → 双源合并 → 忠实压缩、连贯重组输出。Also triggers on: 小红书笔记 / 小红书图文 / 解析小红书 / RedNote note / xiaohongshu note.
---

# 小红书图文笔记抓取与整理

把用户分享的小红书图文笔记，变成**一份「整篇合并版」正文**交给用户。

## 何时触发
- 用户消息里出现 `xhslink.com` 短链或 `xiaohongshu.com` 链接；
- 或粘贴了小红书 App「复制链接」出来的**整段分享文本**（标题片段 + 正文开头 + 链接 + “复制后打开【小红书】查看笔记！”）。

## 核心约束（已与用户定稿）
- 用户**只需整段粘贴**，不必清理文本、不必截图。提取链接由代码完成。
- 从乱文本里取 URL **用正则**（确定性），不要用模型猜：匹配 `https?://\S+`，再 strip 尾部中英标点（`，。！,!` 等）。
- 最终**只输出一份「整篇合并版」**，不分块、不附过程说明。

## 步骤

### 1. 解析（取图 + 元数据）
把**整段分享文本**直接丢给 linkparser 公开 API —— 它会自己从文本里认出链接；**无需登录、无验证码、裸 curl 即可**：

```bash
curl -sS -m 30 -X POST "https://www.linkparser.cn/api/parse" \
  -H "Content-Type: application/json" \
  -d '{"content":"<整段分享文本或纯链接>"}'
```

返回 JSON 关键字段：
- `success` / `platform`(=xiaohongshu) / `type`(=image) / `title` / `author` / `cover`
- `resources[]`：每项 `url` 是一张**高清原图**（图文笔记通常 8 张，1080×1440）
- ⚠️ **响应里没有正文/文案字段** —— 文案要在第 3 步另取。

若 API 失败：用正则抠出纯 URL 再传一次；仍失败走「回退链」。

### 2. 下载并逐图 OCR（← 这是正文主体）
图文笔记的正文**印在图片上**，必须逐张读图。下载每个 `resources[].url`（带 referer 防盗链）到 `/tmp/`，再用 Read 逐张识别：

```bash
mkdir -p /tmp/xhs_note
curl -sL -m 30 -e "https://www.linkparser.cn/" \
  -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36" \
  "<原图URL>" -o /tmp/xhs_note/img_N.jpg
```
（也可用代理：`https://www.linkparser.cn/api/proxy?url=<urlencoded 原图URL>`。）
然后对每个 `img_N.jpg` 调 **Read**（图片走视觉识别），按 1→N 顺序记下逐图文字 = **逐图正文**。

### 3. 取文案描述（desc，第二来源）
linkparser 不给文案，用 defuddle 取小红书的 `desc`（作者发布时填的那段导语）：

```bash
curl -sL -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36" \
  "https://defuddle.md/<原始分享URL>"
```
取输出 frontmatter 里的 `description` 字段 = **文案描述**。（正文中夹的 base64 图片可忽略：`grep -v 'data:image'`。）

### 4. 双源合并 + 输出
- **逐图正文为主干**（那是笔记本体）；**desc 用于**：① 补充图片里没明说的背景信息；② 交叉校验、纠正 OCR 错字。
- 两源有出入时**以图文为准**。
- 去重：desc 常与首图内容高度重叠，**融合而非堆叠**。
- **输出风格（定稿）**：**忠实 + 压缩 + 连贯重组、不保留原文章节骨架**。即——保留全部关键事实/数据/金句和作者核心论点，砍掉情绪铺垫与重复，用自己的连贯叙述重写，**不照搬**原文 `01/02/03…` 小标题。
- 结尾用一行小字注明来源，例：`*基于 desc 文案 + N 图 OCR 双源合并，忠实压缩。*`

## 回退链（linkparser 不可用时）
1. **defuddle 直读**原始分享 URL：能拿 title/author/desc + 首图，但图文笔记后续图常因懒加载缺失。
2. **Chrome 打开**最终 `xiaohongshu.com/...` 链接：大概率撞登录墙 → 让用户在浏览器里**扫码登录**后再抓全部图。
3. 都不行就回到最初方案：请用户**直接截图**所有图发来。

## 边界与风险
- 仅验证过**图文笔记**；视频笔记未覆盖。
- 依赖第三方站 `linkparser.cn`，它若下线 / 加验证码 / 改接口，则走回退链。
- 图上极小字或复杂排版 OCR 偶有误差；以图片清晰度为准，必要时向用户说明不确定处。
