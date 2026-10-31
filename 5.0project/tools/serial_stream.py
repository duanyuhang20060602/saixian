class Decoder:
    """Separate atomic UART heartbeat lines from one-byte application replies."""
    def __init__(self): self.line = None
    def feed(self, data):
        events = []
        for c in data:
            if self.line is not None:
                self.line.append(c)
                if c == 10:
                    events.append(('heartbeat', self.line.decode('ascii', errors='replace').strip()))
                    self.line = None
                elif len(self.line) > 96:
                    self.line = None
            elif c == ord('U'):
                self.line = bytearray([c])
            elif c in b'KERH01234':
                events.append(('reply', chr(c)))
        return events
