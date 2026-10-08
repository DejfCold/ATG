#!/usr/bin/env python3
"""Build a self-contained ATG installer from the maintained source files."""

from __future__ import annotations

import argparse
import base64
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", type=Path, default=ROOT / "dist/atg-installer")
    args = parser.parse_args()

    template = (ROOT / "installer-template.sh.in").read_text()
    runtime = (ROOT / "installer-runtime.sh").read_text()
    runtime = runtime.removeprefix("#!/usr/bin/env bash\n")
    values = {
        "@@ATG_SH_BASE64@@": base64.b64encode((ROOT / "atg.sh").read_bytes()).decode("ascii"),
        "@@ATG_SERVICE_BASE64@@": base64.b64encode((ROOT / "atg.service").read_bytes()).decode("ascii"),
        "@@ATG_PATH_BASE64@@": base64.b64encode((ROOT / "atg.path").read_bytes()).decode("ascii"),
        "@@INSTALL_RUNTIME@@": runtime.rstrip(),
    }
    for marker, value in values.items():
        if template.count(marker) != 1:
            raise SystemExit(f"Expected exactly one {marker} marker in installer template")
        template = template.replace(marker, value)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(template)
    args.output.chmod(0o755)
    print(f"Built {args.output}")


if __name__ == "__main__":
    main()
