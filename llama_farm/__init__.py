import readline
import logging
import hy
from importlib.metadata import version, PackageNotFoundError

import llama_farm.repl


try:
    __version__ = version("llama_farm")
except PackageNotFoundError:
    # package is not installed
    __version__ = "unknown, not installed via pip"
    pass
