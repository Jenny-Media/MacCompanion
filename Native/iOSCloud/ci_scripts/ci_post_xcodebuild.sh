#!/bin/bash
set -euo pipefail
"$(brew --prefix python@3.14)/libexec/bin/python3" \
  "${CI_PRIMARY_REPOSITORY_PATH:?}/scripts/prepare_cloud_ios_packages.py" \
  --derived-data "${CI_DERIVED_DATA_PATH:?}" --verify-only
