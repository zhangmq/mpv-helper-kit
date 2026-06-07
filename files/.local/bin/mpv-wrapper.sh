#!/bin/sh
# ff2mpv-rust 传参格式：wrapper.sh [player_args...] [--] <URL>
url=""
for arg in "$@"; do url="$arg"; done

cookie_file="${XDG_CACHE_HOME:-$HOME/.cache}/yt-dlp/cookies.txt"
cookie_ttl=$((6 * 3600))

# Cookie 过期时刷新
if [ ! -f "$cookie_file" ] || [ $(( $(date +%s) - $(stat -c %Y "$cookie_file") )) -ge "$cookie_ttl" ]; then
    mkdir -p "$(dirname "$cookie_file")"
    yt-dlp --cookies-from-browser chrome --cookies "$cookie_file" --skip-download "https://www.youtube.com" 2>/dev/null
    notify-send "mpv-helper-kit" "Cookie 已刷新" -t 3000 2>/dev/null &
fi

# 单视频快速通道（YouTube Mix 等含 RD 列表的 watch 页面也在此列）
case "$url" in
    *list=RD*|*youtube.com/watch?*|*youtu.be/*|*bilibili.com/video/*|*nicovideo.jp/watch/*|*vimeo.com/*[0-9]*|*twitch.tv/videos/*)
        exec mpv --force-window=yes "$url"
        ;;
    *list=*|*bilibili.com/list/*|*bilibili.com/space/*|*nicovideo.jp/mylist/*|*nicovideo.jp/series/*|*nicovideo.jp/user/*)
        ;;
    *)
        exec mpv --force-window=yes "$url"
        ;;
esac

# 播放列表
urls=$(yt-dlp --cookies "$cookie_file" --flat-playlist --print url "$url" 2>/dev/null)
count=$(echo "$urls" | grep -c '^https\?://')

if [ "$count" -gt 1 ]; then
    echo "$urls" | mpv --playlist=- --force-window=yes
elif [ "$count" -eq 1 ]; then
    exec mpv --force-window=yes "$(echo "$urls" | head -1)"
else
    notify-send "mpv-helper-kit" "播放列表提取失败，尝试直接播放" -t 5000 2>/dev/null &
    exec mpv --force-window=yes "$url"
fi
