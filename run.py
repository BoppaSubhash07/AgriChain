"""One-click VS Code entry point for AgriChain.

Open this file in VS Code and click the Run (Play) button at top-right,
or press F5 anywhere in the workspace.
"""

import os
import sys
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent / "AgriChain"
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))
os.chdir(APP_DIR)

from app import main

if __name__ == "__main__":
    main()
