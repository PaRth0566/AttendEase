import re

def generate_scene_sdf(n_shapes):
    print("float sceneSDF(vec2 p, int n, float k) {")
    print("    if (n <= 0) return 1e9;")
    print("    bool hasSub = false;")
    print("    float s0 = sdf0(p);")
    print("    if (n == 1) return s0;")
    print("    float fwd = s0;")
    print("    float bwd;")
    print()

    for i in range(1, n_shapes):
        print(f"    // ── n = {i+1} ────────────────────────────────────────────────────────────────")
        print(f"    float s{i}  = sdf{i}(p);")
        print(f"    hasSub = hasSub || (uShapeData[{i*7}] < 0.0);")
        print(f"    fwd = applyBlend(fwd, s{i}, uShapeData[{i*7}], k);")
        
        # generate bwd left fold
        b_vars = [f"s{j}" for j in range(i, -1, -1)]
        prev = b_vars[0]
        step = ord('a')
        for j in range(1, len(b_vars)-1):
            var_name = f"b{i+1}{chr(step)}"
            print(f"    float {var_name} = smoothUnion({prev}, {b_vars[j]}, k);")
            prev = var_name
            step += 1
        print(f"    bwd = smoothUnion({prev}, {b_vars[-1]}, k);")
        print(f"    if (n == {i+1}) return hasSub ? fwd : mix(fwd, bwd, 0.5);")
        print()

    print("    return fwd;")
    print("}")

generate_scene_sdf(16)
