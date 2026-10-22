#!/bin/bash
# 当贝 H1 截图：screencap 被海思 DISP 抓屏路径卡死，改用 screenrecord + ffmpeg 取帧
# 用法：./shot.sh <输出.png> <设备地址，如 192.0.2.10:5555>
set -e
OUT=${1:-/tmp/shot.png}
D=${2:?用法: shot.sh <输出.png> <盒子IP>:5555}
MP4=/tmp/rec-shot.mp4

adb -s "$D" shell "rm -f /sdcard/rec.mp4; screenrecord --time-limit 2 --bit-rate 8000000 --size 1920x1080 /sdcard/rec.mp4" >/dev/null 2>&1
adb -s "$D" pull /sdcard/rec.mp4 "$MP4" >/dev/null 2>&1
ffmpeg -loglevel error -y -i "$MP4" -frames:v 1 "$OUT"
ls -l "$OUT"
