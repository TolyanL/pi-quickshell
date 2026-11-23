import json
import os
from pathlib import Path

PRIORITY = ('idle', 'working', 'asking', 'error')


def collect(directory):
    rows = []
    for path in sorted(directory.glob('*.json')):
        try:
            pid = int(path.stem)
            stat = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
            record = json.loads(path.read_text())
            if record['start'] != stat[19] or stat[0] == 'Z':
                continue
            group = [dict(name=record['name'], state=record['state'], depth=0)]
            group.extend(dict(name=c['name'], state=c['state'], depth=c['depth'])
                         for c in record['children'])
            if all(isinstance(r['name'], str) and r['state'] in PRIORITY for r in group):
                rows.extend(group)
        except (OSError, ValueError, KeyError, IndexError, TypeError):
            continue
    return dict(state=max((r['state'] for r in rows), key=PRIORITY.index, default='idle'), rows=rows)


if __name__ == '__main__':
    directory = Path(os.environ.get('XDG_RUNTIME_DIR') or f'/run/user/{os.getuid()}') / 'pi-quickshell'
    print(json.dumps(collect(directory)))
