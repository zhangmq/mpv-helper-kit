#!/bin/bash
# mpv-helper-kit 安装脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"
HOME_DIR="$HOME"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
ok()   { echo -e "${GREEN}[√]${NC} $1"; }
skip() { echo -e "${YELLOW}[跳]${NC} $1"; }

echo "========================================"
echo "  mpv-helper-kit 安装"
echo "========================================"
echo

# ------------------- 依赖包 -------------------
echo "--- 依赖包 ---"
SKIPPED_PKGS=()

for pkg in mpv yt-dlp celluloid mpv-shim-default-shaders; do
    if pacman -Qi "$pkg" &>/dev/null; then
        skip "$pkg"
        SKIPPED_PKGS+=("  $pkg (已安装)")
    else
        echo -n "安装 $pkg ... "
        sudo pacman -S --noconfirm "$pkg" &>/dev/null && ok "$pkg" || warn "$pkg"
    fi
done

for pkg in ff2mpv-rust; do
    if pacman -Qi "$pkg" &>/dev/null; then
        skip "$pkg"
        SKIPPED_PKGS+=("  $pkg (已安装)")
    elif command -v paru &>/dev/null; then
        echo -n "安装 $pkg (AUR) ... "
        paru -S --noconfirm "$pkg" &>/dev/null && ok "$pkg" || warn "$pkg"
    elif command -v yay &>/dev/null; then
        echo -n "安装 $pkg (AUR) ... "
        yay -S --noconfirm "$pkg" &>/dev/null && ok "$pkg" || warn "$pkg"
    fi
done
echo

# ------------------- 目录 -------------------
mkdir -p "$HOME_DIR/.config/mpv/scripts"
mkdir -p "$HOME_DIR/.config/celluloid/scripts"
mkdir -p "$HOME_DIR/.config/celluloid/script-opts"
mkdir -p "$HOME_DIR/.local/bin"
mkdir -p "${XDG_CACHE_HOME:-$HOME_DIR/.cache}/yt-dlp"
echo

# ------------------- 部署文件 -------------------
echo "--- 配置文件 ---"

SKIPPED=()

deploy() {
    local rel="$1"
    local mode="$2"
    local src="$FILES_DIR/$rel"
    local dst="$HOME_DIR/$rel"

    if [ ! -f "$src" ]; then
        warn "源文件缺失: $rel"
        return 1
    fi

    if [ -e "$dst" ]; then
        warn "跳过: $rel (已存在)"
        SKIPPED+=("  $rel")
        return
    fi

    cp "$src" "$dst"
    [ -n "$mode" ] && chmod "$mode" "$dst"
    ok "$rel"
}

deploy ".config/mpv/mpv.conf"
deploy ".config/mpv/input.conf"
deploy ".config/mpv/scripts/shader-keys.lua"
deploy ".local/bin/mpv-wrapper.sh" "+x"

# 生成 ff2mpv-rust.json（路径依赖 home 目录，不纳入 files）
FF2MPV_JSON="$HOME_DIR/.config/ff2mpv-rust.json"
if [ -e "$FF2MPV_JSON" ]; then
    warn "跳过: .config/ff2mpv-rust.json (已存在)"
    SKIPPED+=("  .config/ff2mpv-rust.json")
else
    cat > "$FF2MPV_JSON" << EOF
{
    "player_command": "$HOME_DIR/.local/bin/mpv-wrapper.sh",
    "player_args": ["--"]
}
EOF
    ok ".config/ff2mpv-rust.json"
fi
echo

# ------------------- Celluloid symlink -------------------
echo "--- Celluloid ---"
CELL_LINK="$HOME_DIR/.config/celluloid/scripts/shader-keys.lua"
CELL_SRC="$HOME_DIR/.config/mpv/scripts/shader-keys.lua"
if [ -e "$CELL_LINK" ]; then
    warn "已存在: .config/celluloid/scripts/shader-keys.lua"
else
    ln -sf "$CELL_SRC" "$CELL_LINK"
    ok ".config/celluloid/scripts/shader-keys.lua -> mpv/scripts/shader-keys.lua"
fi
echo

# ------------------- 完成 -------------------
echo "========================================"
ok "安装完成"
echo

if [ ${#SKIPPED_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}以下包已安装，已跳过:${NC}"
    for p in "${SKIPPED_PKGS[@]}"; do echo "$p"; done
    echo
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}以下文件已存在，未覆盖:${NC}"
    for f in "${SKIPPED[@]}"; do echo "$f"; done
    echo
    echo -e "${YELLOW}请参照 mpv-helper-kit 文档手动合并上述文件的差异部分。${NC}"
    echo
fi

echo "  Celluloid 设置: 首选项 → 配置文件 → 勾选"
echo "    [√] 加载 mpv 配置文件"
echo "    [√] 加载 mpv 输入配置文件"
echo
echo "  快捷键:"
echo "    Ctrl+Alt+f  FSRCNNX 开关"
echo "    Ctrl+Alt+a  Anime4K L→M→S→关"
echo "    Ctrl+Alt+c  CAS 0.0→0.5→1.0→关"
echo "    Ctrl+Alt+i  显示状态"
echo
