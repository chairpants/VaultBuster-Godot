"""BVH (CMU mocap) -> one move, start to end, as the angles of the cast's few joints (person.gd), like bvh2gait.py's
walks but played once: down to the floor and back up, a reach, a lean on the counter.

Facing is the hips' at the start (held for the whole move, so turning shows as body_ry); "y" is how far the hips have
dropped from where they started, "z" how far they've gone forward of the feet (back: -), in legs.

  python -I bvh2move.py <file.bvh>                       (the hips' height over time, to find the move)
  python -I bvh2move.py <file.bvh> <out.json> <start s> <end s>
"""
import json, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # (python -I leaves the script's own folder out)
from bvh2gait import load, is_left, leg_of, angles, rest_zero, UP


def main():
    joints, data, dt, J, P = load(sys.argv[1])
    leg = leg_of(P, J)
    if len(sys.argv) < 5:
        for f in range(0, len(P), max(1, int(0.25 / dt))):
            h = (P[f, 0, 1] - P[0, 0, 1]) / leg
            print("%6.2fs  hips %+.2f legs  %s" % (f * dt, h, "#" * int(max(0.0, 40 + h * 60))))
        return
    out, a, b = sys.argv[2], int(float(sys.argv[3]) / dt), int(float(sys.argv[4]) / dt)
    across = np.mean([P[f, J["hipL"]] - P[f, J["hipR"]] for f in range(a, a + max(1, int(0.25 / dt)))], axis=0)
    across[1] = 0
    fwd = np.cross(across / np.linalg.norm(across), UP)
    toes = np.mean([P[f, J["toeL"]] - P[f, J["ankleL"]] for f in range(a, b)], axis=0)
    if np.dot(toes, fwd) < 0:  # (the toes say which way is forward: if it's the other way, "Left" is on the right)
        fwd = -fwd
    left = np.cross(UP, fwd)
    sideL = is_left(P[a:b], J, [left] * (b - a))
    zero = rest_zero(joints, data, J)
    N = max(2, int(round((b - a) * dt * 30)))  # 30 a second
    rows = [angles(P, J, f, fwd, left, sideL) for f in range(a, b + 1)]
    t = np.linspace(0, b - a, N)
    curves = {}
    for k in rows[0]:
        v = np.unwrap([r[k] for r in rows])
        curves[k] = [round(float(x - zero.get(k, 0.0)), 4) for x in np.interp(t, np.arange(b - a + 1), v)]
    mid = lambda f: (P[f, J["ankleL"]] + P[f, J["ankleR"]]) / 2.0
    curves["z"] = [round(float(x), 4) for x in np.interp(t, np.arange(b - a + 1), [np.dot(P[f, 0] - mid(f) - (P[a, 0] - mid(a)), fwd) / leg for f in range(a, b + 1)])]  # the hips forward of the feet
    curves["y"] = [round(float(x), 4) for x in np.interp(t, np.arange(b - a + 1), [(P[f, 0, 1] - P[a, 0, 1]) / leg for f in range(a, b + 1)])]
    json.dump({"src": sys.argv[1].replace("\\", "/").split("/")[-1], "start": float(sys.argv[3]), "n": N, "length": round((b - a) * dt, 4), "curves": curves}, open(out, "w"))
    print(out, N, "frames", round((b - a) * dt, 2), "s", "lowest", round(min(curves["y"]), 2), "legs")


if __name__ == "__main__":
    main()
