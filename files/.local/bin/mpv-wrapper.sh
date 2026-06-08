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

# 每次调用都从 Chrome 重新导出 cookie，不做 TTL 缓存
# 导出 URL 不用 YouTube，防止触发 Google 的 cookie 轮换
log "exporting cookies from Chrome (fresh each invocation)"
mkdir -p "$(dirname "$cookie_file")"
yt-dlp --cookies-from-browser chrome --cookies "$cookie_file" \
    --skip-download "https://httpbin.org/ip" 2>> "$log_file"
export_rc=$?
cookie_entries=$(grep -cvE '^#|^$' "$cookie_file" 2>/dev/null || echo 0)
log "cookie export exit=$export_rc, entries=$cookie_entries"

# 验证导出的 cookie 在 YouTube 上是否有效
# 用 --print title 比 --skip-download 更轻量，减少触发 Google 安全检测的可能
cookie_valid=0
if [ "$cookie_entries" -ge 10 ]; then
    log "validating cookies against YouTube"
    validate_output=$(yt-dlp --cookies "$cookie_file" --print title \
        "https://www.youtube.com/watch?v=jNQXAC9IVRw" 2>&1)
    validate_rc=$?
    log "cookie validation exit=$validate_rc"

    if [ $validate_rc -eq 0 ]; then
        cookie_valid=1
        log "cookie validation: OK"
    elif echo "$validate_output" | grep -qiE "sign in|not a bot|cookies.*(invalid|no longer valid|expired)"; then
        log "cookie validation: AUTH ERROR — Chrome session likely stale"
    else
        log "cookie validation: other error (may still work)"
        log "yt-dlp said: $(echo "$validate_output" | tail -1)"
        cookie_valid=1  # 非认证错误，继续尝试
    fi
fi

if [ "$cookie_valid" -eq 0 ]; then
    log "WARNING: cookies not valid, falling back to --cookies-from-browser"
    notify-send "Chrome 登录态已过期" \
        "请先在 Chrome 中打开一次 YouTube 并确认已登录，再重新投送链接" \
        -t 10000 2>/dev/null &
    # 回退：用 --cookies-from-browser 作为 cookie 来源
    cookie_arg="--cookies-from-browser chrome"
    mpv_cookie_override="cookies-from-browser=chrome"
else
    cookie_arg="--cookies $cookie_file"
    mpv_cookie_override="cookies=$cookie_file"
fi

case "$url" in
    *list=*|*bilibili.com/list/*|*bilibili.com/space/*|*nicovideo.jp/mylist/*|*nicovideo.jp/series/*|*nicovideo.jp/user/*)
        log "route: playlist pattern matched, will extract with yt-dlp"
        ;;
    *youtube.com/watch?*|*youtu.be/*|*bilibili.com/video/*|*nicovideo.jp/watch/*|*vimeo.com/*[0-9]*|*twitch.tv/videos/*)
        log "route: single video ($mpv_cookie_override)"
        exec mpv --force-window=yes --ytdl-raw-options="$mpv_cookie_override,no-playlist=" "$url"
        ;;
    *)
        log "route: unknown URL, exec mpv directly ($mpv_cookie_override)"
        exec mpv --force-window=yes --ytdl-raw-options="$mpv_cookie_override,no-playlist=" "$url"
        ;;
esac

log "extracting playlist: $url (using $cookie_arg)"
urls=$(yt-dlp $cookie_arg --flat-playlist --print url \
    --extractor-args "youtubetab:skip=authcheck" "$url" 2>> "$log_file")
rc=$?
log "yt-dlp playlist exit=$rc"
count=$(echo "$urls" | grep -c '^https\?://')
log "playlist url count: $count"

if [ "$count" -gt 1 ]; then
    notify-send "播放列表就绪" "共 $count 个视频，正在启动播放器" -t 3000 2>/dev/null &
    log "starting mpv with $count urls ($mpv_cookie_override)"
    echo "$urls" | mpv --playlist=- --force-window=yes \
        --ytdl-raw-options="$mpv_cookie_override,no-playlist="
else
    log "only $count urls, falling back to direct mpv ($mpv_cookie_override)"
    notify-send "正在启动播放器" "$url" -t 3000 2>/dev/null &
    exec mpv --force-window=yes --ytdl-raw-options="$mpv_cookie_override,no-playlist=" "$url"
fi
