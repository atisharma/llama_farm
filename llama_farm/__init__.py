import readline
import logging
import hy
from importlib.metadata import version, PackageNotFoundError

import llama_farm.repl


try:
    __version__ = version("package-name")
except PackageNotFoundError:
    # package is not installed
    pass
