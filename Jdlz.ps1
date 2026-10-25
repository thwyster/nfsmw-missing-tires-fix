Add-Type -TypeDefinition @"
using System;
public static class Jdlz {
    public static byte[] Decompress(byte[] input, int start) {
        int outLen = BitConverter.ToInt32(input, start + 8);
        int compLen = BitConverter.ToInt32(input, start + 12);
        byte[] output = new byte[outLen];
        int flags1 = 1, flags2 = 1, t, length;
        int inPos = start + 16, end = start + compLen, outPos = 0;
        while (inPos < end && outPos < outLen) {
            if (flags1 == 1) flags1 = input[inPos++] | 0x100;
            if (flags2 == 1) flags2 = input[inPos++] | 0x100;
            if ((flags1 & 1) == 1) {
                if ((flags2 & 1) == 1) {
                    length = (input[inPos + 1] | ((input[inPos] & 0xF0) << 4)) + 3;
                    t = (input[inPos] & 0x0F) + 1;
                } else {
                    t = (input[inPos + 1] | ((input[inPos] & 0xE0) << 3)) + 17;
                    length = (input[inPos] & 0x1F) + 3;
                }
                inPos += 2;
                for (int i = 0; i < length && outPos + i < outLen; ++i) output[outPos + i] = output[outPos + i - t];
                outPos += length;
                flags2 >>= 1;
            } else {
                output[outPos++] = input[inPos++];
            }
            flags1 >>= 1;
        }
        return output;
    }
}
"@

function Get-JdlzOffsets([byte[]]$b) {
    $offs = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $b.Length - 16; $i++) {
        if ($b[$i] -eq 0x4A -and $b[$i+1] -eq 0x44 -and $b[$i+2] -eq 0x4C -and $b[$i+3] -eq 0x5A -and $b[$i+4] -eq 0x02 -and $b[$i+5] -eq 0x10) { $offs.Add($i) }
    }
    return $offs
}
