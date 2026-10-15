"""BVH (100STYLE) -> one looping walk cycle, as the angles of the cast's few joints (person.gd).

The cast's rig: a pelvis ("body": yaw/pitch/roll), one waist bend ("upper": pitch/yaw/roll over the pelvis), a head
(pitch/yaw), and per side a hip (thigh: forward swing + sideways), a knee (bend), an ankle (foot pitch), a shoulder
(upper arm: forward swing + sideways out) and an elbow (bend). The angles are measured geometrically from the
mocap's joint positions (FK), not its rotation channels, so the source skeleton's axis conventions don't matter.

  python -I bvh2gait.py <file.bvh> <out.json> [cycles to average]
"""
import json, math, sys
import numpy as np


def parse(path):
    toks = open(path).read().split()
    i = 0
    joints = []  # [name, parent, offset, channels]
    stack = []
    while True:
        t = toks[i]
        if t in ("ROOT", "JOINT"):
            joints.append([toks[i + 1], stack[-1] if stack else -1, None, []])
            i += 2
        elif t == "End":
            joints.append(["_end%d" % len(joints), stack[-1], None, []])
            i += 2
        elif t == "{":
            stack.append(len(joints) - 1)
            i += 1
        elif t == "}":
            stack.pop()
            i += 1
        elif t == "OFFSET":
            joints[stack[-1]][2] = np.array([float(x) for x in toks[i + 1:i + 4]])
            i += 4
        elif t == "CHANNELS":
            n = int(toks[i + 1])
            joints[stack[-1]][3] = toks[i + 2:i + 2 + n]
            i += 2 + n
        elif t == "MOTION":
            break
        else:
            i += 1
    nf = int(toks[i + 2])
    dt = float(toks[i + 5])
    data = np.array([float(x) for x in toks[i + 6:]]).reshape(nf, -1)
    return joints, data, dt


def rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return {"X": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]), "Y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]), "Z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


def fk(joints, frame):  # -> world position and rotation of every joint
    pos, R = [], []
    k = 0
    for name, parent, off, ch in joints:
        r = np.eye(3)
        p = off.copy()
        for c in ch:
            v = frame[k]
            k += 1
            if c.endswith("position"):
                p["XYZ".index(c[0])] = v
            else:
                r = r @ rot(c[0], v)
        if parent < 0:
            pos.append(p)
            R.append(r)
        else:
            pos.append(pos[parent] + R[parent] @ p)
            R.append(R[parent] @ r)
    return np.array(pos), R


def find(joints, *keys):  # the first joint whose name has all of these in it (case-blind)
    for i, j in enumerate(joints):
        n = j[0].lower()
        if all(k in n for k in keys):
            return i
    raise KeyError(keys)


def load(src):  # -> the parsed file, its joints we use, and every frame's joint positions (y up)
    joints, data, dt = parse(src)
    names = [j[0] for j in joints]
    J = {}
    J["hips"] = 0
    J["spine"] = [i for i, n in enumerate(names) if "spine" in n.lower() or "chest" in n.lower()]
    J["neck"] = find(joints, "neck")
    J["head"] = find(joints, "head")
    for side, key in (("L", "left"), ("R", "right")):
        J["hip" + side] = find(joints, key, "up") if any(key in n.lower() and "upleg" in n.lower() for n in names) else find(joints, key, "hip")
        legs = [i for i, n in enumerate(names) if key in n.lower() and n.lower().endswith("leg") and "up" not in n.lower()]  # (LeftLeg, not LeftUpLeg)
        J["knee" + side] = legs[0] if legs else find(joints, key, "knee")
        J["ankle" + side] = find(joints, key, "foot") if any(key in n.lower() and "foot" in n.lower() for n in names) else find(joints, key, "ankle")
        J["toe" + side] = find(joints, key, "toe")
        J["sh" + side] = find(joints, key, "arm") if any(key in n.lower() and n.lower().endswith("arm") and "fore" not in n.lower() for n in names) else find(joints, key, "shoulder")
        J["el" + side] = find(joints, key, "forearm") if any(key in n.lower() and "forearm" in n.lower() for n in names) else find(joints, key, "elbow")
        J["wr" + side] = find(joints, key, "hand") if any(key in n.lower() and "hand" in n.lower() for n in names) else find(joints, key, "wrist")
    P = np.array([fk(joints, f)[0] for f in data])  # frames x joints x 3
    up = np.array([0.0, 1.0, 0.0])
    if abs(P[:, J["head"], 2].mean() - P[:, 0, 2].mean()) > abs(P[:, J["head"], 1].mean() - P[:, 0, 1].mean()):
        P = P[:, :, [0, 2, 1]] * np.array([1, 1, -1])  # (z up: to y up)
    return joints, data, dt, J, P


def is_left(P, J, LEFT):  # is the capture's "Left" on its left?
    return np.mean([np.dot(P[f, J["hipL"]] - P[f, 0], LEFT[f]) for f in range(len(P))]) > 0


def leg_of(P, J):
    return np.linalg.norm(P[:, J["kneeL"]] - P[:, J["hipL"]], axis=1).mean() + np.linalg.norm(P[:, J["ankleL"]] - P[:, J["kneeL"]], axis=1).mean()


def ang(v, a, b):  # the angle of v in the plane of a (0) towards b (+90)
    return math.atan2(np.dot(v, b), np.dot(v, a))


UP = np.array([0.0, 1.0, 0.0])


def swing(v, x, y, z, s):  # a limb hanging down (-y) swung forward, then out: the joints' XYZ order (Rz Rx), so
    # forward is the asin of how far it points ahead, and out is its angle in what's left (holds up with a thigh level, squatting)
    v = v / np.linalg.norm(v)
    return math.asin(np.clip(np.dot(v, z), -1, 1)), math.atan2(np.dot(v, x), -np.dot(v, y)) * s


def angles(P, J, f, fwd, left, sideL):  # one frame's joint angles, the way person.gd's joints take them
    up = UP
    across = P[f, J["hipL"]] - P[f, J["hipR"]]  # the body's own frame: x to its left, y up, z the way the hips face
    if not sideL:
        across = -across
    across[1] = 0
    x = across / np.linalg.norm(across)
    y, z = up, np.cross(x, up)
    r = {}
    r["body_ry"] = math.atan2(np.dot(np.cross(x, up), left), np.dot(np.cross(x, up), fwd)) * -1.0
    sp = P[f, J["neck"]] - P[f, 0]  # the spine, hips to the neck
    r["body_rx"] = ang(sp, y, z)  # forward lean
    r["body_rz"] = -ang(sp, y, x)  # sideways lean (towards its left: +)
    sh = P[f, J["shL"]] - P[f, J["shR"]]
    if not sideL:
        sh = -sh
    sh[1] = 0
    r["upper_ry"] = math.atan2(np.dot(sh, z), np.dot(sh, x)) * -1.0  # the shoulders turned against the hips
    hd = P[f, J["head"]] - P[f, J["neck"]]
    r["head_rx"] = ang(hd, y, z) - r["body_rx"]
    for side in ("L", "R"):
        th = P[f, J["knee" + side]] - P[f, J["hip" + side]]
        sn = P[f, J["ankle" + side]] - P[f, J["knee" + side]]
        ft = P[f, J["toe" + side]] - P[f, J["ankle" + side]]
        ua = P[f, J["el" + side]] - P[f, J["sh" + side]]
        fa = P[f, J["wr" + side]] - P[f, J["el" + side]]
        s = 1.0 if side == "L" else -1.0
        r["hip%s_x" % side], r["hip%s_z" % side] = swing(th, x, y, z, s)  # thigh forward (+), out to its own side (+)
        r["knee%s" % side] = math.acos(np.clip(np.dot(th, sn) / np.linalg.norm(th) / np.linalg.norm(sn), -1, 1))  # bend (+)
        sh_ang = ang(sn, -y, z)  # the shin's own forward tilt
        r["ankle%s" % side] = ang(ft, z, -y) - (-sh_ang)  # toes down (+) against the shin square
        r["sh%s_x" % side], r["sh%s_z" % side] = swing(ua, x, y, z, s)  # upper arm forward (+), out to its side (+)
        r["el%s" % side] = math.acos(np.clip(np.dot(ua, fa) / np.linalg.norm(ua) / np.linalg.norm(fa), -1, 1))
    return r


def rest_zero(joints, data, J):
    # the skeleton's own rest pose (every rotation zero, facing +z, its left +x): the toe's a little lower than the
    # ankle, the neck a little forward of the hips. What those read stood still is what "flat" and "upright" are
    rest = fk(joints, np.zeros(data.shape[1]))[0]
    if abs(rest[J["head"], 2] - rest[0, 2]) > abs(rest[J["head"], 1] - rest[0, 1]):
        rest = rest[:, [0, 2, 1]] * np.array([1, 1, -1])
    Y, Z = UP, np.array([0, 0, 1.0])
    zero = {"body_rx": ang(rest[J["neck"]] - rest[0], Y, Z), "head_rx": ang(rest[J["head"]] - rest[J["neck"]], Y, Z) - ang(rest[J["neck"]] - rest[0], Y, Z)}
    for side in ("L", "R"):
        sh_ang = ang(rest[J["ankle" + side]] - rest[J["knee" + side]], -Y, Z)
        zero["ankle" + side] = ang(rest[J["toe" + side]] - rest[J["ankle" + side]], Z, -Y) + sh_ang
    print("  rest:", {k: round(math.degrees(v), 1) for k, v in zero.items()})
    return zero


def main():
    src, out = sys.argv[1], sys.argv[2]
    want_cycles = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    joints, data, dt, J, P = load(src)
    up = UP
    # facing: the way the hips are going at that moment (the captures walk up and down the room, turning at each end),
    # half a second either side; and to the left of that
    k = max(1, int(round(0.5 / dt)))
    FWD = []
    for f in range(len(P)):
        v = P[min(len(P) - 1, f + k), 0] - P[max(0, f - k), 0]
        v[1] = 0
        FWD.append(v / np.linalg.norm(v) if np.linalg.norm(v) > 1e-6 else (FWD[-1] if FWD else np.array([0.0, 0.0, 1.0])))
    FWD = np.array(FWD)
    LEFT = np.cross(up, FWD)
    sideL = is_left(P, J, LEFT)
    leg = leg_of(P, J)
    rows = []
    for f in range(len(P)):
        r = angles(P, J, f, FWD[f], LEFT[f], sideL)
        r["y"] = (P[f, 0, 1] - P[:, 0, 1].mean()) / leg  # the hips riding up and down (in legs)
        r["foot"] = np.dot(P[f, J["ankleL"]] - P[f, 0], FWD[f])  # (for finding the cycle)
        r["straight"] = abs(np.dot(FWD[max(0, f - k)], FWD[min(len(P) - 1, f + k)]))  # (not mid-turn)
        rows.append(r)
    # the cycle: the left foot's furthest forward, each stride
    fo = np.array([r["foot"] for r in rows])
    peaks = [f for f in range(2, len(fo) - 2) if fo[f] == fo[f - 2:f + 3].max() and fo[f] > np.percentile(fo, 70)]
    peaks = [p for i, p in enumerate(peaks) if i == 0 or p - peaks[i - 1] > 10]
    straight = [p for i, p in enumerate(peaks[:-1]) if min(rows[f]["straight"] for f in range(p, peaks[i + 1])) > 0.97]  # cycles walking straight
    if len(straight) >= want_cycles:
        runs, cur = [], [straight[0]]
        for p in straight[1:]:
            if peaks.index(p) == peaks.index(cur[-1]) + 1:
                cur.append(p)
            else:
                runs.append(cur)
                cur = [p]
        runs.append(cur)
        best = max(runs, key=len)
        if len(best) >= want_cycles:
            peaks = best + [peaks[peaks.index(best[-1]) + 1]]
    mid = len(peaks) // 2
    pick = peaks[max(0, mid - want_cycles // 2): max(0, mid - want_cycles // 2) + want_cycles + 1]
    N = 64
    keys = [k for k in rows[0] if k not in ("foot", "straight")]
    acc = {k: np.zeros(N) for k in keys}
    strides = []
    for a, b in zip(pick, pick[1:]):
        t = np.linspace(a, b, N, endpoint=False)
        for k in keys:
            v = np.unwrap(np.array([rows[f][k] for f in range(a, b + 1)])) if not k == "y" else np.array([rows[f][k] for f in range(a, b + 1)])
            acc[k] += np.interp(t, np.arange(a, b + 1), v)
        strides.append(np.linalg.norm((P[b, 0] - P[a, 0])[[0, 2]]))
    n = len(pick) - 1
    zero = rest_zero(joints, data, J)
    curves = {k: [round(float(x / n - zero.get(k, 0.0)), 4) for x in acc[k]] for k in keys}
    period = float(np.mean(np.diff(pick))) * dt
    stride = float(np.mean(strides)) / leg  # one full cycle's travel, in legs
    json.dump({"src": src.replace("\\", "/").split("/")[-1], "n": N, "cycles": n, "period": round(period, 4), "stride": round(stride, 4),
               "speed": round(float(np.mean(strides)) / period, 3), "leg": round(float(leg), 3), "curves": curves}, open(out, "w"))
    print(out, "cycles", n, "period", round(period, 3), "s", "stride", round(stride, 3), "legs", "speed", round(float(np.mean(strides)) / period, 2), "units/s")


if __name__ == "__main__":
    main()
