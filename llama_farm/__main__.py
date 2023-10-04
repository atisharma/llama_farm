import hy
import sys

from llama-farm.repl import run

if __name__ == "__main__":
 sys.exit(run() or 0)

# to capture stderr

#import os
#from contextlib import contextmanager
#
#@contextmanager
#def redirect_stderr(file_obj):
#    original_stderr = sys.stderr
#    sys.stderr = file_obj
#    try:
#        yield
#    finally:
#        sys.stderr = original_stderr
#
#if __name__ == "__main__":
#  # Redirect stderr to a log file
#  with open('llama_farm.stderr', 'w') as log_file:
#      with redirect_stderr(log_file):
#          sys.exit(run() or 0)
#
