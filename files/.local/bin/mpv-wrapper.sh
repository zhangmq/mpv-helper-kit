#!/bin/sh
# ff2mpv-rust 传参格式：wrapper.sh [player_args...] [--] <URL>
url=""
for arg in "$@"; do url="$arg"; done

# Cookie 缓存
cookie_file="${XDG_CACHE_HOME:-$HOME/.cache}/yt-dlp/cookies.txt"
cookie_ttl=$((6 * 3600))

refresh_cookies() {
    mkdir -p "$(dirname "$cookie_file")"
    yt-dlp --cookies-from-browser chrome --cookies "$cookie_file" --skip-download "about:blank" 2>/dev/null
}

[ ! -f "$cookie_file" ] || [ $(( $(date +%s) - $(stat -c %Y "$cookie_file") )) -ge "$cookie_ttl" ] && refresh_cookies

# 单视频快速通道（不含播放列表参数）
case "$url" in
    *list=*|*bilibili.com/list/*|*bilibili.com/space/*|*nicovideo.jp/mylist/*|*nicovideo.jp/series/*|*nicovideo.jp/user/*)
        ;;  # 播放列表 → 走 yt-dlp 检测
    *youtube.com/watch?*|*youtu.be/*|*bilibili.com/video/*|*nicovideo.jp/watch/*|*vimeo.com/*[0-9]*|*twitch.tv/videos/*)
        exec mpv --force-window=yes "$url"
        ;;
esac

# 其余 URL（含播放列表）用 yt-dlp 自动检测
urls=$(yt-dlp --cookies "$cookie_file" --flat-playlist --print url "$url" 2>/dev/null)
count=$(echo "$urls" | grep -c '^https\?://')

if [ "$count" -gt 1 ]; then
    echo "$urls" | mpv --playlist=- --force-window=yes
else
    exec mpv --force-window=yes "$url"
fi
