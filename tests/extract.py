"""Extract exact installer payloads for tests; never execute the installer."""
from pathlib import Path
import re

def extract(destination, source=None):
    source = source or Path(__file__).resolve().parents[1] / 'install.sh'
    text = Path(source).read_text()
    files = {}
    for name, tag, body in re.findall(r'''cat > "\$STAGE/([^"\n]+)" <<'([^']+)'\n(.*?)\n\2''', text, re.S):
        target = Path(destination) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body + '\n')
        files[name] = body
    assert len(files) >= 15, 'Installer payload extraction failed'
    return files

if __name__ == '__main__':
    import sys
    print('Extracted', len(extract(sys.argv[1])), 'payloads')
