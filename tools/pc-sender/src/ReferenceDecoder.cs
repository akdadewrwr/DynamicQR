// Minimal C# receiver used only by the self-test to prove the sender's frames decode.
using System;
using System.Collections.Generic;

namespace DynamicQr
{
    public class ReferenceDecoder
    {
        private class Pending
        {
            public byte[] Data;
            public HashSet<int> Remaining;
        }

        private byte[][] sources;
        private int resolved;
        private int k;
        private int blockSize;
        private int bundleLen;
        private uint transferId;
        private uint bundleCrc;
        private readonly HashSet<uint> seen = new HashSet<uint>();
        private readonly List<Pending> pending = new List<Pending>();

        public bool IsComplete { get { return sources != null && resolved == k; } }

        public byte[] Bundle
        {
            get
            {
                if (!IsComplete) return null;
                byte[] b = new byte[bundleLen];
                for (int i = 0; i < k; i++)
                    Buffer.BlockCopy(sources[i], 0, b, i * blockSize, Math.Min(blockSize, bundleLen - i * blockSize));
                return Crc.Crc32(b, 0, b.Length) == bundleCrc ? b : null;
            }
        }

        // Returns true if the text was a new valid frame.
        public bool AddFrameText(string text)
        {
            byte[] f = Base45.Decode(text);
            if (f == null || f.Length < 24 || f[0] != 1) return false;
            int bs = f[9] | (f[10] << 8);
            if (bs < 1 || f.Length != 23 + bs) return false;
            int n = 21 + bs;
            if (Crc.Crc16(f, 0, n) != (f[n] | (f[n + 1] << 8))) return false;
            uint tid = BitConverter.ToUInt32(f, 1);
            int len = (int)BitConverter.ToUInt32(f, 5);
            uint crc = BitConverter.ToUInt32(f, 11);
            uint blockId = BitConverter.ToUInt32(f, 15);
            int degree = f[19] | (f[20] << 8);
            if (sources == null || tid != transferId)
            {
                transferId = tid;
                blockSize = bs;
                bundleLen = len;
                bundleCrc = crc;
                k = (len + bs - 1) / bs;
                sources = new byte[k][];
                resolved = 0;
                seen.Clear();
                pending.Clear();
            }
            if (!seen.Add(blockId)) return false;
            byte[] data = new byte[bs];
            Buffer.BlockCopy(f, 21, data, 0, bs);
            Pending p = new Pending();
            p.Data = data;
            p.Remaining = new HashSet<int>(Lt.Neighbors(tid, blockId, degree, k));
            pending.Add(p);
            Peel();
            return true;
        }

        private void Peel()
        {
            bool progress = true;
            while (progress)
            {
                progress = false;
                for (int i = pending.Count - 1; i >= 0; i--)
                {
                    Pending p = pending[i];
                    foreach (int idx in new List<int>(p.Remaining))
                    {
                        if (sources[idx] != null)
                        {
                            Xor(p.Data, sources[idx]);
                            p.Remaining.Remove(idx);
                        }
                    }
                    if (p.Remaining.Count == 1)
                    {
                        int only = 0;
                        foreach (int idx in p.Remaining) only = idx;
                        sources[only] = p.Data;
                        resolved++;
                        progress = true;
                        pending.RemoveAt(i);
                    }
                    else if (p.Remaining.Count == 0)
                    {
                        pending.RemoveAt(i);
                    }
                }
            }
        }

        private static void Xor(byte[] a, byte[] b)
        {
            for (int i = 0; i < a.Length; i++) a[i] ^= b[i];
        }
    }
}
