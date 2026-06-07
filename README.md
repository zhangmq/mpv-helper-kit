# mpv-helper-kit

## 功能

- 浏览器联动
    - 浏览器扩展到 mpv 的 URL 投送（依赖 ff2mpv 扩展、ff2mpv-rust）
    - 播放列表支持（依赖 yt-dlp）
    - 支持 YouTube、Bilibili、Niconico 等网站
- 着色器动态切换（依赖 mpv-shim-default-shaders）
    - FSRCNNX（超分辨率）：开关
    - Anime4K（去模糊）：L / M / S 循环
    - CAS（锐化）：0.0 / 0.5 / 1.0 循环

---

## 安装

### 通过 install.sh

```bash
cd mpv-helper-kit
./install.sh
```

脚本会安装全部依赖包并部署所有文件。已安装的包跳过，已存在的配置文件提示手动合并。

### 浏览器扩展

`install.sh` 无法安装浏览器扩展，需手动操作：

- **Chrome**：[ff2mpv](https://chromewebstore.google.com/detail/ff2mpv/ephjcajbkgplkjmelpglennepbpmdpjg)（作者 woodruffw）—— 已测试
- **Firefox**：[ff2mpv](https://addons.mozilla.org/firefox/addon/ff2mpv/)（作者 yossarian/woodruffw）—— 未测试

### 手动安装

以下按功能归属分组，可只选需要的部分。

```bash
# mpv: 播放器
sudo pacman -S mpv

mkdir -p ~/.config/mpv/scripts ~/.local/bin ~/.cache/yt-dlp
```

| 文件 | 目标 |
|---|---|
| `files/.config/mpv/mpv.conf` | `~/.config/mpv/mpv.conf` |
| `files/.config/mpv/input.conf` | `~/.config/mpv/input.conf` |

**Celluloid（可选）：**

```bash
# 本地文件播放的 GUI 前端
# install.sh 会自动建立脚本符号链接，使其可读取 mpv 配置
sudo pacman -S celluloid
```

首选项 → 配置文件 → 勾选「加载 mpv 配置文件」和「加载 mpv 输入配置文件」。

**着色器动态切换：**

```bash
sudo pacman -S mpv-shim-default-shaders
cp files/.config/mpv/scripts/shader-keys.lua ~/.config/mpv/scripts/shader-keys.lua
```

Celluloid 需要额外链接（Celluloid 不读 mpv 的脚本目录）：

```bash
mkdir -p ~/.config/celluloid/scripts ~/.config/celluloid/script-opts
ln -sf ~/.config/mpv/scripts/shader-keys.lua ~/.config/celluloid/scripts/shader-keys.lua
```

**浏览器联动：**

```bash
# yt-dlp: 流媒体 URL 解析，wrapper 依赖
# ff2mpv-rust: 接收浏览器扩展发来的 URL
sudo pacman -S yt-dlp
paru -S ff2mpv-rust
cp files/.local/bin/mpv-wrapper.sh ~/.local/bin/mpv-wrapper.sh
chmod +x ~/.local/bin/mpv-wrapper.sh
```

创建 `~/.config/ff2mpv-rust.json`，`player_command` 需使用绝对路径：

```json
{
    "player_command": "/home/<用户名>/.local/bin/mpv-wrapper.sh",
    "player_args": ["--"]
}
```

`install.sh` 会自动生成此文件。

---

## 实现原理

### 浏览器联动

#### 数据流

浏览器扩展将当前页面 URL 通过 Chrome Native Messaging 或 Firefox native messaging 发送给 `ff2mpv-rust`，后者根据 `~/.config/ff2mpv-rust.json` 中的 `player_command` 调用 `mpv-wrapper.sh`，wrapper 处理 URL 后启动 mpv。

mpv 收到 URL 后通过内建 yt-dlp hook（`ytdl=yes`）解析实际流地址并播放。

#### mpv-wrapper.sh

wrapper 从传入参数中取最后一个值作为 URL，按以下分类处理：

**已知单视频格式**：以下格式的 URL 直接 `exec mpv`，不调用 yt-dlp：

- `youtube.com/watch`、`youtu.be/`
- `bilibili.com/video/`
- `nicovideo.jp/watch/`
- `vimeo.com/`
- `twitch.tv/videos/`

**已知播放列表格式**：以下格式的 URL 通过 `yt-dlp --flat-playlist --print url` 提取所有条目，管道传入 `mpv --playlist=-`：

- YouTube `?list=`
- Bilibili `/list/`、`/space/`
- Niconico `/mylist/`、`/series/`、`/user/`

**其他 URL**：由 yt-dlp `--flat-playlist` 检测。若返回多于 1 条 URL，按播放列表处理；否则按单视频处理。

**Cookie**：wrapper 首次运行时从 Chrome 导出 cookie 到 `~/.cache/yt-dlp/cookies.txt`（明文），之后每 6 小时自动刷新。B站高画质和部分网站的登录态依赖此文件。

**mpv.conf 配合**：`ytdl-raw-options` 中的 `cookies=` 指向同一 cookie 文件，使 mpv 内建 yt-dlp hook 使用相同登录态。`no-playlist=` 阻止 mpv 内建 hook 再次展开已被 wrapper 处理的播放列表。

#### 已知限制

- Celluloid / Haruna 等 GUI 前端无法通过 ff2mpv 播放流媒体 URL
- 部分网站可能因地域限制导致 yt-dlp 提取失败

### 着色器动态切换

#### 组件

| 组件 | 说明 |
|---|---|
| `shader-keys.lua` | 注册快捷键，通过 `mp.set_property_native("glsl-shaders", ...)` 在播放中动态修改着色器列表。mpv 原生的 `glsl-shaders` 是启动时静态加载的全局选项 |
| `mpv.conf` 中的 `profile-cond` | 基于视频分辨率在文件加载时自动设置着色器，作为初始默认值 |

着色器文件由 `mpv-shim-default-shaders` 包安装至 `/usr/share/mpv-shim-default-shaders/shaders/`。

#### mpv 渲染管线中的着色器位置

mpv 的渲染管线分为多个阶段。本配置涉及的三个阶段：

1. 色度缩放（`cscale=ewa_lanczossharp`）
2. 亮度平面处理（`HOOK LUMA`）—— FSRCNNX、Anime4K 在此阶段，处理原始分辨率的亮度数据
3. 亮度缩放（`scale=ewa_lanczossharp`）—— 将亮度平面拉伸到显示分辨率
4. 缩放后处理（`HOOK SCALED`）—— CAS 在此阶段

FSRCNNX 和 Anime4K 在步骤 2 完成 2x 放大后，步骤 3 的 `scale` 负责补充剩余缩放。两者处于不同阶段，不存在重复处理。

#### 着色器

**FSRCNNX**（`Ctrl+Alt+f`，开关）：2x CNN 超分辨率，`HOOK LUMA` 阶段。

**Anime4K**（`Ctrl+Alt+a`，循环）：`HOOK LUMA` 阶段，通过切换不同强度的预训练模型文件实现档位调节：

| 档位 | 文件 |
|---|---|
| L (Light) | `Anime4K_Restore_CNN_L.glsl` |
| M (Medium) | `Anime4K_Restore_CNN_M.glsl` |
| S (Strong) | `Anime4K_Restore_CNN_S.glsl` |

UL 和 VL 变体存在渲染问题，已排除。

**CAS**（`Ctrl+Alt+c`，循环）：`HOOK SCALED` 阶段。mpv 的 `glsl-shader-opts` 选项可在着色器编译前设置 `#define`，此处用于注入 `SHARPENING` 值，无需修改着色器文件：

| 档位 | SHARPENING |
|---|---|
| 0.0 | 0.0 |
| 0.5 | 0.5 |
| 1.0 | 1.0 |

切换 CAS 档位时，脚本先设置 `glsl-shader-opts` 为新值，再从 `glsl-shaders` 列表中移除并重新加入 CAS 路径，触发 mpv 以新的 `SHARPENING` 值重新编译着色器。

#### 状态查询

`Ctrl+Alt+i` 读取 mpv 当前的 `glsl-shaders` 和 `glsl-shader-opts` 属性值并显示。

#### 行为

- `Ctrl+Alt+f` 按下时：FSRCNNX 未启用则启用，已启用则关闭
- `Ctrl+Alt+a` 按下时：Anime4K 关闭 → L → M → S → 关闭（循环）
- `Ctrl+Alt+c` 按下时：CAS 关闭 → 0.0 → 0.5 → 1.0 → 关闭（循环）
- FSRCNNX、Anime4K、CAS 可同时启用
- 切换视频后，脚本通过 `file-loaded` 事件将 `glsl-shaders` 和 `glsl-shader-opts` 恢复为上一个视频结束时的值

#### 自动配置（可选）

`mpv.conf` 中基于视频高度的 `profile-cond` 在首次启动时设置着色器默认值。用户通过快捷键手动调整后，手动设置在后续视频切换时自动恢复，覆盖 profile-cond 的默认值。profile-cond 仅在无手动设置的首次加载时生效。

| 视频高度 | 默认加载 |
|---|---|
| ≤720 | FSRCNNX + Anime4K M + CAS |
| 721–1080 | FSRCNNX |
| ≥2160 | 无 |

---

## 文件结构

```
mpv-helper-kit/
├── README.md
├── install.sh
└── files/
    ├── .config/
    │   ├── mpv/
    │   │   ├── mpv.conf              # 视频输出 + 超分辨率自动配置
    │   │   ├── input.conf
    │   │   └── scripts/
    │   │       └── shader-keys.lua
    └── .local/
        └── bin/
            └── mpv-wrapper.sh         # URL 预处理 + cookie 导出
```

---

## 卸载

**包：**

```bash
paru -Rns ff2mpv-rust                       # 浏览器联动（AUR）
sudo pacman -Rns mpv-shim-default-shaders   # 着色器文件
sudo pacman -Rns celluloid                  # GUI 前端（可选）
```

`mpv` 和 `yt-dlp` 可能被其他程序依赖，不建议直接移除。

以下为安装过程中部署或生成的文件，卸载时可删除文件或移除文件中相关配置段落：

| 路径 | 说明 |
|---|---|
| `~/.config/mpv/mpv.conf` | 视频输出、yt-dlp、profile-cond |
| `~/.config/mpv/input.conf` | 快捷键注释 |
| `~/.config/mpv/scripts/shader-keys.lua` | 着色器快捷键脚本 |
| `~/.config/ff2mpv-rust.json` | ff2mpv 配置（install.sh 生成） |
| `~/.local/bin/mpv-wrapper.sh` | URL 预处理脚本 |
| `~/.cache/yt-dlp/cookies.txt` | Chrome cookie 导出 |
| `~/.config/celluloid/scripts/shader-keys.lua` | Celluloid 符号链接 |
