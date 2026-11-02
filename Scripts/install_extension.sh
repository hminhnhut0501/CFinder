#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_APP="$PROJECT_ROOT/dist/CFinder.app"
DEST_APP="/Applications/CFinder.app"

echo "=================================================="
echo "🚀 CÀI ĐẶT CFINDER VÀO HỆ THỐNG"
echo "=================================================="

if [ ! -d "$DIST_APP" ]; then
    echo "⚠️ Chưa tìm thấy bản build CFinder.app trong thư mục dist."
    echo "Đang tiến hành build..."
    "$SCRIPT_DIR/build.sh"
fi

echo "==> [1/3] Cài đặt CFinder.app vào /Applications..."
rm -rf "$DEST_APP"
rm -rf "/Applications/SFinder.app"
cp -R "$DIST_APP" "$DEST_APP"

echo "==> [2/3] Đăng ký LaunchServices & PlugInKit..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST_APP"
pluginkit -a "$DEST_APP/Contents/PlugIns/SFinderSync.appex"
pluginkit -e use -i com.sfinder.app.sync

echo "==> [3/3] Khởi động lại Finder để nhận tiện ích mở rộng..."
killall Finder || true

echo ""
echo "✅ ĐÃ CÀI ĐẶT CFINDER THÀNH CÔNG!"
