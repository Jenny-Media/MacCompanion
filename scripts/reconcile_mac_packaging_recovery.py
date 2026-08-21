#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from mac_packaging_equivalence import (
    MacPackagingEquivalenceError,
    reconcile_recovery_root,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Reconcile one retained Mac packaging-equivalence mount root"
    )
    parser.add_argument("recovery_root", type=Path)
    parser.add_argument(
        "--allow-nonforce-detach",
        action="store_true",
        help="authorize detaching only the exact read-only image owned by this recovery record",
    )
    arguments = parser.parse_args()
    if not arguments.allow_nonforce_detach:
        parser.error("recovery requires --allow-nonforce-detach")
    reconcile_recovery_root(
        arguments.recovery_root,
        allow_nonforce_detach=True,
    )
    print(f"reconciled {arguments.recovery_root}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (MacPackagingEquivalenceError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
