#!/bin/sh
url=""
for arg in "$@"; do url="$arg"; done

log_file="${XDG_CACHE_HOME:-$HOME/.cache}/yt-dlp/wrapper.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$log_file"
}

log "=== wrapper invoked ==="
log "raw args: $*"
log "url: $url"

notify-send "收到链接，请等待播放器启动" "$url" -t 3000 2>/dev/null &

cookie_file="${XDG_CACHE_HOME:-$HOME/.cache}/yt-dlp/cookies.txt"

# 每次调用都从 Chrome 重新导出 cookie
# 导出 URL 避开 YouTube，防止触发 Google 的 cookie 轮换
log "exporting cookies from Chrome (fresh each invocation)"
mkdir -p "$(dirname "$cookie_file")"
yt-dlp --cookies-from-browser chrome --cookies "$cookie_file" \
    --skip-download "https://httpbin.org/ip" 2>> "$log_file"
export_rc=$?
cookie_entries=$(grep -cvE '^#|^$' "$cookie_file" 2>/dev/null || echo 0)
log "cookie export exit=$export_rc, entries=$cookie_entries"

# 截取 yt-dlp stderr 中的 ERROR 行（不含 WARNING）
first_error() {
    grep -i "ERROR" | head -1 | sed 's/^.*ERROR: //'
}

# --- 播放列表：wrapper 直接控制 yt-dlp，可拦截错误 ---
case "$url" in
    *list=*|*bilibili.com/list/*|*bilibili.com/space/*|*nicovideo.jp/mylist/*|*nicovideo.jp/series/*|*nicovideo.jp/user/*)
        log "route: playlist"
        log "extracting playlist with cookie file"
        urls=$(yt-dlp --cookies "$cookie_file" --flat-playlist --print url \
            --extractor-args "youtubetab:skip=authcheck" "$url" 2>&1)
        rc=$?
        log "playlist exit=$rc"

        ytdl_err=$(echo "$urls" | first_error)
        if [ -n "$ytdl_err" ]; then
            log "playlist error, retrying with --cookies-from-browser: $ytdl_err"
            notify-send "播放视频失败" "$ytdl_err" -t 7000 2>/dev/null &
            urls=$(yt-dlp --cookies-from-browser chrome --flat-playlist --print url \
                --extractor-args "youtubetab:skip=authcheck" "$url" 2>> "$log_file")
            rc=$?
            log "playlist retry exit=$rc"
            mpv_cookie="cookies-from-browser=chrome"
        else
            mpv_cookie="cookies=$cookie_file"
        fi

        count=$(echo "$urls" | grep -c '^https\?://')
        log "playlist url count: $count"

        if [ "$count" -gt 1 ]; then
            notify-send "播放列表就绪" "共 $count 个视频，正在启动播放器" -t 3000 2>/dev/null &
            log "starting mpv with $count urls"
            echo "$urls" | mpv --playlist=- --force-window=yes \
                --ytdl-raw-options="$mpv_cookie,no-playlist="
        else
            log "only $count urls, direct mpv"
            notify-send "正在启动播放器" "$url" -t 3000 2>/dev/null &
            exec mpv --force-window=yes --ytdl-raw-options="$mpv_cookie,no-playlist=" "$url"
        fi
        exit
        ;;
esac

# --- 单视频 / 未知 URL：exec mpv，stderr 直接给用户看 ---
log "route: single video / unknown, exec mpv"
exec mpv --force-window=yes --ytdl-raw-options="cookies=$cookie_file,no-playlist=" "$url"
