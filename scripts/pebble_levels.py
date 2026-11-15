"""Generate and curate 推石过水洼 levels. Deterministic (fixed seed), emits Swift.

Legend: '#' bush, '.' path, '~' puddle, 'o' pebble, 'C' cat, 'G' keepsake.
The cat walks 4 ways; it pushes a pebble one cell if the cell beyond is path/goal (no pebble)
or a puddle (the pebble fills it and becomes path). The cat can't walk into a puddle.
"""
import random, sys
from collections import deque

DIRS = [(-1, 0), (0, 1), (1, 0), (0, -1)]  # up right down left


def parse(rows):
    H, W = len(rows), len(rows[0])
    walls, puddles, pebbles = set(), set(), set()
    cat = goal = None
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == '#': walls.add((r, c))
            elif ch == '~': puddles.add((r, c))
            elif ch == 'o': pebbles.add((r, c))
            elif ch == 'C': cat = (r, c)
            elif ch == 'G': goal = (r, c)
    return H, W, walls, puddles, pebbles, cat, goal


def step(H, W, walls, puddles, state, d):
    cat, pebbles, filled = state
    dr, dc = DIRS[d]
    t = (cat[0] + dr, cat[1] + dc)
    if not (0 <= t[0] < H and 0 <= t[1] < W) or t in walls: return None
    if t in puddles and t not in filled: return None
    if t in pebbles:
        b = (t[0] + dr, t[1] + dc)
        if not (0 <= b[0] < H and 0 <= b[1] < W) or b in walls or b in pebbles: return None
        np = set(pebbles); np.discard(t)
        nf = filled
        if b in puddles and b not in filled:
            nf = filled | {b}
        else:
            np.add(b)
        return (t, frozenset(np), frozenset(nf)), True
    return (t, pebbles, filled), False


def solve(rows, limit=200000):
    H, W, walls, puddles, pebbles, cat, goal = parse(rows)
    start = (cat, frozenset(pebbles), frozenset())
    seen = {start: (None, None, 0)}
    q = deque([start])
    while q:
        s = q.popleft()
        if s[0] == goal:
            # rebuild path to count pushes
            path, pushes, cur = [], 0, s
            while seen[cur][0] is not None:
                prev, d, p = seen[cur]
                path.append(d); pushes += p; cur = prev
            return len(path), pushes, path[::-1]
        for d in range(4):
            res = step(H, W, walls, puddles, s, d)
            if res is None: continue
            ns, pushed = res
            if ns not in seen:
                seen[ns] = (s, d, 1 if pushed else 0)
                if len(seen) > limit: return None
                q.append(ns)
    return None


def reachable_without_fill(rows):
    H, W, walls, puddles, pebbles, cat, goal = parse(rows)
    blocked = walls | puddles | pebbles
    q, seen = deque([cat]), {cat}
    while q:
        p = q.popleft()
        if p == goal: return True
        for dr, dc in DIRS:
            t = (p[0] + dr, p[1] + dc)
            if 0 <= t[0] < H and 0 <= t[1] < W and t not in blocked and t not in seen:
                seen.add(t); q.append(t)
    return False


def make(rng, tier):
    W, H = [(6, 5), (7, 6), (7, 6)][tier]
    grid = [['.'] * W for _ in range(H)]
    vertical = rng.random() < 0.6
    width = 1 if tier < 2 else 2
    if vertical:
        x0 = rng.randint(2, W - 2 - width)
        for y in range(H):
            for k in range(width): grid[y][x0 + k] = '~'
        left = [(y, x) for y in range(H) for x in range(0, x0)]
        right = [(y, x) for y in range(H) for x in range(x0 + width, W)]
    else:
        y0 = rng.randint(2, H - 2 - width)
        for x in range(W):
            for k in range(width): grid[y0 + k][x] = '~'
        left = [(y, x) for y in range(0, y0) for x in range(W)]
        right = [(y, x) for y in range(y0 + width, H) for x in range(W)]
    # a few bushes, some inside the river to make the crossing point matter
    for _ in range(rng.randint(2, 4 + tier * 2)):
        y, x = rng.randrange(H), rng.randrange(W)
        grid[y][x] = '#'
    pebble_count = [rng.randint(1, 2), rng.randint(2, 3), 3][tier]
    free_left = [p for p in left if grid[p[0]][p[1]] == '.']
    free_right = [p for p in right if grid[p[0]][p[1]] == '.']
    if len(free_left) < pebble_count + 1 or not free_right: return None
    rng.shuffle(free_left)
    cy, cx = free_left[0]; grid[cy][cx] = 'C'
    for (y, x) in free_left[1:1 + pebble_count]: grid[y][x] = 'o'
    gy, gx = rng.choice(free_right); grid[gy][gx] = 'G'
    return [''.join(r) for r in grid]


RANGES = {0: (7, 14), 1: (11, 22), 2: (15, 32)}


def main():
    rng = random.Random(20261115)
    picked = {0: [], 1: [], 2: []}
    seen_rows = set()
    attempts = 0
    while any(len(v) < 8 for v in picked.values()) and attempts < 400000:
        attempts += 1
        tier = rng.choice([t for t in picked if len(picked[t]) < 8])
        rows = make(rng, tier)
        if rows is None or tuple(rows) in seen_rows: continue
        if reachable_without_fill(rows): continue
        res = solve(rows)
        if res is None: continue
        par, pushes, path = res
        lo, hi = RANGES[tier]
        need_pushes = [1, 2, 3][tier]
        if not (lo <= par <= hi) or pushes < need_pushes: continue
        # every pebble must not be trivially in line: require at least one non-push step between pushes
        seen_rows.add(tuple(rows))
        picked[tier].append((rows, par, pushes))
    print('attempts', attempts, {t: len(v) for t, v in picked.items()}, file=sys.stderr)
    for t in picked:
        picked[t].sort(key=lambda e: (e[1], e[2]))
        for rows, par, pushes in picked[t]:
            print(f'tier {t} par {par} pushes {pushes}', file=sys.stderr)
            for r in rows: print('   ', r, file=sys.stderr)
    out = ['// Generated by scripts/pebble_levels.py (fixed seed). Do not edit by hand:',
           '// each par is the solver\'s fewest steps, so a hand edit would make the stars wrong.',
           '',
           'enum OutingPebbleLevels {',
           '    struct Level: Sendable { let tier: Int; let rows: [String]; let par: Int }',
           '    static let all: [Level] = [']
    for t in picked:
        for rows, par, pushes in picked[t]:
            out.append(f'        .init(tier: {t}, rows: [' + ', '.join(f'"{r}"' for r in rows) + f'], par: {par}),')
    out += ['    ]', '}', '']
    open(sys.argv[1], 'w').write('\n'.join(out))


if __name__ == '__main__':
    main()
