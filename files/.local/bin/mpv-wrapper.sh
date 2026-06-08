#!/bin/sh
url=""
for arg in "$@"; do url="$arg"; done

notify-send "收到链接，请等待播放器启动" "$url" -t 3000 2>/dev/null &

cookie_file="${XDG_CACHE_HOME:-$HOME/.cache}/yt-dlp/cookies.txt"

if [ ! -f "$cookie_file" ] || [ $(( $(date +%s) - $(stat -c %Y "$cookie_file") )) -ge $((6 * 3600)) ]; then
    notify-send "正在刷新 Cookie" "从 Chrome 导出登录状态到本地缓存" -t 3000 2>/dev/null &
    mkdir -p "$(dirname "$cookie_file")"
    yt-dlp --cookies-from-browser chrome --cookies "$cookie_file" --skip-download "https://www.youtube.com" 2>/dev/null
    notify-send "Cookie 刷新完成" "有效期 6 小时" -t 3000 2>/dev/null &
fi

case "$url" in
    *list=*|*bilibili.com/list/*|*bilibili.com/space/*|*nicovideo.jp/mylist/*|*nicovideo.jp/series/*|*nicovideo.jp/user/*)
        ;;
    *youtube.com/watch?*|*youtu.be/*|*bilibili.com/video/*|*nicovideo.jp/watch/*|*vimeo.com/*[0-9]*|*twitch.tv/videos/*)
        exec mpv --force-window=yes "$url"
        ;;
    *)
        exec mpv --force-window=yes "$url"
        ;;
esac

urls=$(yt-dlp --cookies-from-browser chrome --flat-playlist --print url \
    --extractor-args "youtubetab:skip=authcheck" "$url" 2>/dev/null)
count=$(echo "$urls" | grep -c '^https\?://')

if [ "$count" -gt 1 ]; then
    notify-send "播放列表就绪" "共 $count 个视频，正在启动播放器" -t 3000 2>/dev/null &
    echo "$urls" | mpv --playlist=- --force-window=yes
else
    notify-send "正在启动播放器" "$url" -t 3000 2>/dev/null &
    exec mpv --force-window=yes "$url"
fi
