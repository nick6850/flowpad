#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
staging_dir="$project_dir/.build/app-bundle"
app_dir="$staging_dir/Flowpad.app"
contents_dir="$app_dir/Contents"

cd "$project_dir"
swift build -c release

if [[ -e "$staging_dir" ]]; then
    resolved_staging="${staging_dir:A}"
    expected_staging="${project_dir:A}/.build/app-bundle"
    [[ "$resolved_staging" == "$expected_staging" ]] || {
        print -u2 "Refusing to replace unexpected staging path: $resolved_staging"
        exit 1
    }
    rm -rf -- "$resolved_staging"
fi

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$project_dir/.build/release/Flowpad" "$contents_dir/MacOS/Flowpad"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

if [[ -f "$project_dir/Resources/AppIcon.icns" ]]; then
    cp "$project_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
print "$app_dir"
