import sys
import select
import tty
import termios

class NonBlockingConsole(object):

    def __enter__(self):
        self.old_settings = termios.tcgetattr(sys.stdin)
        tty.setcbreak(sys.stdin.fileno())
        return self

    def __exit__(self, type, value, traceback):
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self.old_settings)


    def get_data(self):
        if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
            return sys.stdin.read(1)
        return False


def echo():
    with NonBlockingConsole() as nbc:
        while 1:
            key = nbc.get_data()
            if key == '\x1b':  # x1b is ESC
                break
            elif key == '':
            elif key:
                print(key)
