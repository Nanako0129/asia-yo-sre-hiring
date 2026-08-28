from pathlib import Path
from subprocess import run
import sys


question_dir = Path(__file__).parent
result = run(
    [sys.executable, "solution.py"],
    cwd=question_dir,
    capture_output=True,
    text=True,
    check=True,
)

assert result.stdout == "4 twinkle\n", result.stdout
