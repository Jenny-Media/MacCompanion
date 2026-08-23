#!/bin/zsh

set -euo pipefail

if [[ "${ACTION:-}" != "install" ]]; then
  exit 0
fi

target_build_dir="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
wrapper_name="${WRAPPER_NAME:?WRAPPER_NAME is required}"
framework="${target_build_dir}/${wrapper_name}/Contents/Frameworks/Sparkle.framework"

case "${framework}" in
  "${target_build_dir}"/*/Contents/Frameworks/Sparkle.framework) ;;
  *)
    print -u2 -- "refusing unsafe Sparkle framework path"
    exit 1
    ;;
esac

if [[ ! -d "${framework}" || -L "${framework}" ]]; then
  print -u2 -- "expected a real embedded Sparkle.framework"
  exit 1
fi

versioned_services="${framework}/Versions/B/XPCServices"
root_services="${framework}/XPCServices"

if [[ -e "${versioned_services}" || -L "${versioned_services}" ]]; then
  /bin/rm -R -- "${versioned_services}"
fi
if [[ -e "${root_services}" || -L "${root_services}" ]]; then
  /bin/rm -R -- "${root_services}"
fi

if [[ -e "${versioned_services}" || -L "${versioned_services}" || -e "${root_services}" || -L "${root_services}" ]]; then
  print -u2 -- "Sparkle XPC services remain after stripping"
  exit 1
fi

retained_executables=(
  "${framework}/Versions/B/Sparkle"
  "${framework}/Versions/B/Autoupdate"
  "${framework}/Versions/B/Updater.app/Contents/MacOS/Updater"
)
for retained in "${retained_executables[@]}"; do
  if [[ ! -f "${retained}" || -L "${retained}" || ! -x "${retained}" ]]; then
    print -u2 -- "required Sparkle runtime executable is missing or unsafe"
    exit 1
  fi
done

for forbidden in BinaryDelta generate_appcast generate_keys sign_update; do
  if /usr/bin/find "${framework}" -name "${forbidden}" -print -quit | /usr/bin/grep -q .; then
    print -u2 -- "Sparkle release tool entered the application framework: ${forbidden}"
    exit 1
  fi
done

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]]; then
  identity="${EXPANDED_CODE_SIGN_IDENTITY:?EXPANDED_CODE_SIGN_IDENTITY is required for signed install builds}"
  retained_nested_code=(
    "${framework}/Versions/B/Updater.app"
    "${framework}/Versions/B/Autoupdate"
  )
  for subject in "${retained_nested_code[@]}"; do
    /usr/bin/codesign \
      --force \
      --sign "${identity}" \
      --options runtime \
      --timestamp \
      --preserve-metadata=identifier,entitlements \
      "${subject}"
  done
  /usr/bin/codesign \
    --force \
    --sign "${identity}" \
    --options runtime \
    --timestamp \
    --preserve-metadata=identifier,entitlements \
    "${framework}"

  for subject in "${retained_nested_code[@]}" "${framework}"; do
    /usr/bin/codesign --verify --strict --verbose=4 "${subject}"
  done
fi
