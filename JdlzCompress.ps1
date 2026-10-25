Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
public static class JdlzC {
    const int MinMatch = 3;
    const int MaxDistLong = 2064;   // type 0: distance 17..2064, length 3..34
    const int MaxLenLong = 34;
    const int MaxDistShort = 16;    // type 1: distance 1..16, length 3..4098
    const int MaxLenShort = 4098;
    const int HashBits = 16;
    const int MaxChain = 256;

    static int Hash3(byte[] d, int i) { return ((d[i] << 10) ^ (d[i + 1] << 5) ^ d[i + 2]) & ((1 << HashBits) - 1); }

    public static byte[] Compress(byte[] data) {
        var tokens = new List<int[]>(); // {0, byte} literal | {1, tipo, dist, len}
        int n = data.Length;
        int[] head = new int[1 << HashBits];
        int[] prev = new int[n];
        for (int i = 0; i < head.Length; i++) head[i] = -1;
        int pos = 0;
        while (pos < n) {
            int bestLen = 0, bestDist = 0, bestType = 0;
            // type 1: short distances, long lengths (RLE)
            for (int dist = 1; dist <= MaxDistShort && dist <= pos; dist++) {
                int l = 0; int max = Math.Min(MaxLenShort, n - pos);
                while (l < max && data[pos + l] == data[pos + l - dist]) l++;
                if (l > bestLen) { bestLen = l; bestDist = dist; bestType = 1; }
            }
            // type 0: long distances via hash chain
            if (pos + 2 < n) {
                int h = Hash3(data, pos);
                int cand = head[h]; int chain = 0;
                while (cand >= 0 && chain < MaxChain) {
                    int dist = pos - cand;
                    if (dist > MaxDistLong) break;
                    if (dist >= 17) {
                        int l = 0; int max = Math.Min(MaxLenLong, n - pos);
                        while (l < max && data[cand + l] == data[pos + l]) l++;
                        if (l > bestLen) { bestLen = l; bestDist = dist; bestType = 0; if (l == MaxLenLong && bestType == 0) { } }
                    }
                    cand = prev[cand]; chain++;
                }
            }
            int adv;
            if (bestLen >= MinMatch) { tokens.Add(new int[] { 1, bestType, bestDist, bestLen }); adv = bestLen; }
            else { tokens.Add(new int[] { 0, data[pos] }); adv = 1; }
            for (int k = 0; k < adv; k++) {
                int p = pos + k;
                if (p + 2 < n) { int h = Hash3(data, p); prev[p] = head[h]; head[h] = p; }
            }
            pos += adv;
        }
        // serialize while emulating how the decoder reads flag bytes
        var o = new List<byte>(n / 2);
        o.AddRange(new byte[] { 0x4A, 0x44, 0x4C, 0x5A, 0x02, 0x10, 0x00, 0x00 });
        o.AddRange(BitConverter.GetBytes(n));
        o.AddRange(new byte[4]);
        int f1pos = -1, f1cnt = 0, f2pos = -1, f2cnt = 0;
        foreach (var t in tokens) {
            if (f1cnt == 0) { f1pos = o.Count; o.Add(0); f1cnt = 8; }
            if (f2cnt == 0) { f2pos = o.Count; o.Add(0); f2cnt = 8; }
            int f1bit = 8 - f1cnt;
            if (t[0] == 0) {
                o.Add((byte)t[1]);
            } else {
                o[f1pos] |= (byte)(1 << f1bit);
                int f2bit = 8 - f2cnt;
                int len = t[3] - 3;
                if (t[1] == 1) {
                    o[f2pos] |= (byte)(1 << f2bit);
                    o.Add((byte)(((len >> 8) << 4) | (t[2] - 1)));
                    o.Add((byte)(len & 0xFF));
                } else {
                    int d = t[2] - 17;
                    o.Add((byte)(((d >> 8) << 5) | len));
                    o.Add((byte)(d & 0xFF));
                }
                f2cnt--;
            }
            f1cnt--;
        }
        byte[] r = o.ToArray();
        BitConverter.GetBytes(r.Length).CopyTo(r, 12);
        return r;
    }
}
"@
