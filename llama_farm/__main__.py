import hy
import sys
from .repl import run

if __name__ == "__main__":
  sys.exit(run() or 0)
