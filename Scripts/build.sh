#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/.build"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/CFinder.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
PLUGINS_DIR="$APP_CONTENTS/PlugIns"
EXTENSION_BUNDLE="$PLUGINS_DIR/SFinderSync.appex"
EXT_CONTENTS="$EXTENSION_BUNDLE/Contents"

echo "==> [1/5] Dọn dẹp thư mục dist..."
rm -rf "$DIST_DIR"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources" "$EXT_CONTENTS/MacOS" "$EXT_CONTENTS/Resources"

echo "==> [2/5] Biên dịch Swift Package (Release mode)..."
cd "$PROJECT_ROOT"
swift build -c release

RELEASE_DIR="$BUILD_DIR/arm64-apple-macosx/release"

echo "==> [3/5] Đóng gói Host Application..."
cp "$RELEASE_DIR/SFinderHost" "$APP_CONTENTS/MacOS/SFinderHost"
cp "$PROJECT_ROOT/InfoPlists/Host-Info.plist" "$APP_CONTENTS/Info.plist"

if [ -d "$PROJECT_ROOT/Resources" ]; then
    cp -R "$PROJECT_ROOT/Resources"/* "$APP_CONTENTS/Resources/"
fi

echo "==> [4/5] Biên dịch Finder Extension (SFinderSync.appex)..."
swiftc -O \
    -target arm64-apple-macosx14.0 \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -framework Cocoa \
    -framework FinderSync \
    "$RELEASE_DIR/SFinderSync.build/FinderSync.swift.o" \
    "$RELEASE_DIR"/SFinderCore.build/*.o \
    -o "$EXT_CONTENTS/MacOS/SFinderSync"

chmod +x "$EXT_CONTENTS/MacOS/SFinderSync"
cp "$PROJECT_ROOT/InfoPlists/Extension-Info.plist" "$EXT_CONTENTS/Info.plist"
if [ -d "$PROJECT_ROOT/Resources" ]; then
    cp -R "$PROJECT_ROOT/Resources"/* "$EXT_CONTENTS/Resources/"
fi

echo "==> [5/5] Ký mã bằng Chứng chỉ Bất biến (SFinder Development Certificate)..."
SIGN_ID="SFinder Development"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    echo "Khởi tạo chứng chỉ $SIGN_ID..."
    openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
        -out /tmp/sfinder_cert.pem -keyout /tmp/sfinder_key.pem \
        -subj "/CN=SFinder Development" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "basicConstraints=critical,CA:FALSE" 2>/dev/null
    openssl pkcs12 -export -legacy -inkey /tmp/sfinder_key.pem -in /tmp/sfinder_cert.pem -out /tmp/sfinder_cert.p12 -passout pass:sfinder 2>/dev/null
    security import /tmp/sfinder_cert.p12 -k ~/Library/Keychains/login.keychain-db -P sfinder -T /usr/bin/codesign 2>/dev/null || true
    security add-trusted-cert -d -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/sfinder_cert.pem 2>/dev/null || true
fi

codesign --force --sign "$SIGN_ID" --entitlements "$PROJECT_ROOT/InfoPlists/Extension.entitlements" --identifier "com.sfinder.app.sync" "$EXT_CONTENTS/MacOS/SFinderSync"
codesign --force --sign "$SIGN_ID" --identifier "com.sfinder.app" "$APP_CONTENTS/MacOS/SFinderHost"
codesign --force --sign "$SIGN_ID" --entitlements "$PROJECT_ROOT/InfoPlists/Extension.entitlements" --identifier "com.sfinder.app.sync" "$EXTENSION_BUNDLE"
codesign --force --sign "$SIGN_ID" --identifier "com.sfinder.app" "$APP_BUNDLE"

echo "==> Đăng ký Extension với pluginkit..."
pluginkit -a "$EXTENSION_BUNDLE" || true
pluginkit -e use -i com.sfinder.app.sync || true

echo "=========================================================="
echo "  CFinder Build Thành Công!"
echo "  Đường dẫn: $APP_BUNDLE"
echo "=========================================================="
