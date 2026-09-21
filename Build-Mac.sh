#!/usr/bin/env bash
# PKG Sender macOS .app + zip. Does not touch the Windows installer scripts.
#   ./Build-Mac.sh           # current CPU (arm64 or x64)
#   APP_VERSION=1.2.6 ./Build-Mac.sh arm64
set -euo pipefail
cd "$(dirname "$0")"
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1

ARCH="${1:-}"
if [[ -z "$ARCH" ]]; then
  case "$(uname -m)" in
    arm64) ARCH=arm64 ;;
    x86_64) ARCH=x64 ;;
    *) echo "Unknown CPU $(uname -m) — pass arm64 or x64"; exit 1 ;;
  esac
fi
RID="osx-$ARCH"

DOTNET="${DOTNET:-}"
if [[ -z "$DOTNET" ]]; then
  if [[ -x "$HOME/.dotnet/dotnet" ]]; then
    DOTNET="$HOME/.dotnet/dotnet"
    export DOTNET_ROOT="$HOME/.dotnet"
    export PATH="$HOME/.dotnet:$PATH"
  else
    DOTNET="dotnet"
  fi
fi

VER="${APP_VERSION:-}"
if [[ -z "$VER" ]]; then
  VER=$(sed -n 's/.*<Version>\([^<]*\)<\/Version>.*/\1/p' library/PkgSender.csproj | head -1 | tr -d '[:space:]')
fi
if [[ -z "$VER" ]]; then
  echo "Could not read Version (set APP_VERSION)"
  exit 1
fi

echo "Publishing PKG Sender $VER for $RID"

PUB="dist/osx-$ARCH"
APP="dist/macos/PkgSender.app"
ZIP="dist/PkgSender-macOS-$ARCH-$VER.zip"
rm -rf "$PUB" "$APP" "$ZIP"
mkdir -p "$PUB" dist/macos

"$DOTNET" publish library/PkgSender.csproj -c Release -r "$RID" --self-contained true \
  -p:UseAppHost=true \
  -p:PublishSingleFile=false \
  -p:IncludeNativeLibrariesForSelfExtract=false \
  -p:DebugType=None -p:DebugSymbols=false \
  -p:Version="$VER" \
  -o "$PUB" --nologo -v q

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -a "$PUB"/. "$APP/Contents/MacOS/"
chmod +x "$APP/Contents/MacOS/PkgSender"

if [[ -f payload/pkg-receiver.elf ]]; then
  cp -f payload/pkg-receiver.elf "$APP/Contents/MacOS/pkg-receiver.elf"
  cp -f payload/pkg-receiver.elf dist/macos/pkg-receiver.elf
fi
for src in pkgviewer.py ../pkg-viewer/pkgviewer.py; do
  if [[ -f "$src" ]]; then
    cp -f "$src" "$APP/Contents/MacOS/pkgviewer.py"
    break
  fi
done

sed "s/@VERSION@/$VER/g" macos/Info.plist > "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"

ICON_SRC="library/Assets/logo.png"
if [[ -f "$ICON_SRC" ]] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
  ICONSET="$(mktemp -d)/PkgSender.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/PkgSender.icns"
  rm -rf "$(dirname "$ICONSET")"
fi

if command -v codesign >/dev/null; then
  codesign --force --deep --sign - \
    --entitlements macos/PkgSender.entitlements \
    "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP" || true
fi
xattr -cr "$APP" 2>/dev/null || true

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/PkgSender.app"
ZIP_ABS="$(pwd)/$ZIP"
(
  cd "$STAGE"
  if [[ -f "$OLDPWD/dist/macos/pkg-receiver.elf" ]]; then
    cp "$OLDPWD/dist/macos/pkg-receiver.elf" pkg-receiver.elf
    zip -r -y "$ZIP_ABS" PkgSender.app pkg-receiver.elf
  else
    zip -r -y "$ZIP_ABS" PkgSender.app
  fi
)
rm -rf "$STAGE"

echo
echo "App: $APP"
echo "Zip: $ZIP"
