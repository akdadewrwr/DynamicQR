// DynamicQr wire protocol, sender side (spec §5.2-5.4). Must match entry/src/main/ets/protocol bit-for-bit.
// C# 5 only (compiled by Windows PowerShell 5.1 Add-Type).
using System;
using System.Collections.Generic;
using System.Text;

namespace DynamicQr
{
    public static class Base45
    {
        public const string Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

        public static string Encode(byte[] data)
        {
            StringBuilder sb = new StringBuilder((data.Length + 1) / 2 * 3);
            int i = 0;
            for (; i + 1 < data.Length; i += 2)
            {
                int n = data[i] * 256 + data[i + 1];
                sb.Append(Alphabet[n % 45]).Append(Alphabet[(n / 45) % 45]).Append(Alphabet[n / 2025]);
            }
            if (i < data.Length)
            {
                int n = data[i];
                sb.Append(Alphabet[n % 45]).Append(Alphabet[n / 45]);
            }
            return sb.ToString();
        }

        // Returns null on invalid input.
        public static byte[] Decode(string text)
        {
            int len = text.Length;
            if (len % 3 == 1) return null;
            byte[] outBytes = new byte[len / 3 * 2 + (len % 3 == 2 ? 1 : 0)];
            int o = 0;
            for (int i = 0; i < len; i += 3)
            {
                int c = Alphabet.IndexOf(text[i]);
                int d = Alphabet.IndexOf(text[i + 1]);
                if (c < 0 || d < 0) return null;
                if (i + 2 < len)
                {
                    int e = Alphabet.IndexOf(text[i + 2]);
                    if (e < 0) return null;
                    int n = c + d * 45 + e * 2025;
                    if (n > 65535) return null;
                    outBytes[o++] = (byte)(n >> 8);
                    outBytes[o++] = (byte)(n & 0xFF);
                }
                else
                {
                    int n = c + d * 45;
                    if (n > 255) return null;
                    outBytes[o++] = (byte)n;
                }
            }
            return outBytes;
        }
    }

    public static class Crc
    {
        public static uint Crc32(byte[] d, int start, int end)
        {
            uint c = 0xFFFFFFFFu;
            for (int i = start; i < end; i++)
            {
                c ^= d[i];
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320u : c >> 1;
            }
            return ~c;
        }

        public static ushort Crc16(byte[] d, int start, int end)
        {
            int c = 0xFFFF;
            for (int i = start; i < end; i++)
            {
                c ^= d[i] << 8;
                for (int k = 0; k < 8; k++) c = (c & 0x8000) != 0 ? ((c << 1) ^ 0x1021) & 0xFFFF : (c << 1) & 0xFFFF;
            }
            return (ushort)c;
        }
    }

    public static class Prng
    {
        public static uint Mix32(uint a, uint b)
        {
            unchecked
            {
                uint h = a ^ ((b + 0x9E3779B9u) * 0x85EBCA6Bu);
                h ^= h >> 16;
                h *= 0x85EBCA6Bu;
                h ^= h >> 13;
                h *= 0xC2B2AE35u;
                h ^= h >> 16;
                return h;
            }
        }
    }

    public class Mulberry32
    {
        private uint s;

        public Mulberry32(uint seed)
        {
            s = seed;
        }

        public uint Next()
        {
            unchecked
            {
                s += 0x6D2B79F5u;
                uint t = (s ^ (s >> 15)) * (1u | s);
                t = (t + ((t ^ (t >> 7)) * (61u | t))) ^ t;
                return t ^ (t >> 14);
            }
        }
    }

    public static class Lt
    {
        // Source-block indices for a block; blocks below k are systematic.
        public static int[] Neighbors(uint transferId, uint blockId, int degree, int k)
        {
            if (blockId < (uint)k) return new int[] { (int)blockId };
            Mulberry32 rng = new Mulberry32(Prng.Mix32(transferId, blockId));
            List<int> result = new List<int>(degree);
            while (result.Count < degree)
            {
                int i = (int)(rng.Next() % (uint)k);
                if (!result.Contains(i)) result.Add(i);
            }
            return result.ToArray();
        }
    }

    // Robust Soliton degree distribution (c = 0.1, delta = 0.5). Sender only: degree travels in the frame header.
    public class RobustSoliton
    {
        private readonly double[] cdf;
        private readonly int k;

        public RobustSoliton(int k)
        {
            this.k = k;
            cdf = new double[k + 1];
            if (k == 1)
            {
                cdf[1] = 1;
                return;
            }
            const double c = 0.1, delta = 0.5;
            double r = c * Math.Log(k / delta) * Math.Sqrt(k);
            int pivot = Math.Min(k, Math.Max(1, (int)Math.Floor(k / r)));
            double[] mu = new double[k + 1];
            double z = 0;
            for (int d = 1; d <= k; d++)
            {
                double rho = d == 1 ? 1.0 / k : 1.0 / ((double)d * (d - 1));
                double tau = 0;
                if (d < pivot) tau = r / ((double)d * k);
                else if (d == pivot) tau = r * Math.Log(r / delta) / k;
                mu[d] = rho + Math.Max(0, tau);
                z += mu[d];
            }
            double acc = 0;
            for (int d = 1; d <= k; d++)
            {
                acc += mu[d] / z;
                cdf[d] = acc;
            }
            cdf[k] = 1;
        }

        public int Sample(uint r)
        {
            double u = r / 4294967296.0;
            int d = 1;
            while (d < k && cdf[d] <= u) d++;
            return d;
        }
    }

    public static class BundleWriter
    {
        // "DQB1", u16 count, then per file: u16 nameLen, UTF-8 name, u32 dataLen, data (little-endian).
        public static byte[] Pack(IList<KeyValuePair<string, byte[]>> files)
        {
            List<byte> outBytes = new List<byte>();
            outBytes.AddRange(Encoding.ASCII.GetBytes("DQB1"));
            outBytes.AddRange(BitConverter.GetBytes((ushort)files.Count));
            foreach (KeyValuePair<string, byte[]> f in files)
            {
                byte[] name = Encoding.UTF8.GetBytes(f.Key);
                outBytes.AddRange(BitConverter.GetBytes((ushort)name.Length));
                outBytes.AddRange(name);
                outBytes.AddRange(BitConverter.GetBytes((uint)f.Value.Length));
                outBytes.AddRange(f.Value);
            }
            return outBytes.ToArray();
        }
    }

    public class FrameEncoder
    {
        public const int HeaderLen = 21;

        private readonly byte[][] blocks;
        private readonly int blockSize;
        private readonly int bundleLen;
        private readonly uint transferId;
        private readonly RobustSoliton soliton;

        public int K { get; private set; }
        public uint BundleCrc32 { get; private set; }
        public uint TransferId { get { return transferId; } }

        public FrameEncoder(byte[] bundle, int blockSize, uint transferId)
        {
            if (blockSize < 1 || blockSize > 65535) throw new ArgumentException("blockSize must be 1..65535");
            if (bundle.Length < 1) throw new ArgumentException("bundle is empty");
            this.blockSize = blockSize;
            this.transferId = transferId;
            bundleLen = bundle.Length;
            K = (bundle.Length + blockSize - 1) / blockSize;
            BundleCrc32 = Crc.Crc32(bundle, 0, bundle.Length);
            blocks = new byte[K][];
            for (int i = 0; i < K; i++)
            {
                blocks[i] = new byte[blockSize];
                Buffer.BlockCopy(bundle, i * blockSize, blocks[i], 0, Math.Min(blockSize, bundle.Length - i * blockSize));
            }
            soliton = new RobustSoliton(K);
        }

        public int Degree(uint blockId)
        {
            if (blockId < (uint)K) return 1;
            return soliton.Sample(new Mulberry32(Prng.Mix32(transferId, blockId) ^ 0xA5A5A5A5u).Next());
        }

        public string FrameText(uint blockId)
        {
            int degree = Degree(blockId);
            byte[] frame = new byte[HeaderLen + blockSize + 2];
            frame[0] = 1;
            PutU32(frame, 1, transferId);
            PutU32(frame, 5, (uint)bundleLen);
            PutU16(frame, 9, blockSize);
            PutU32(frame, 11, BundleCrc32);
            PutU32(frame, 15, blockId);
            PutU16(frame, 19, degree);
            foreach (int idx in Lt.Neighbors(transferId, blockId, degree, K))
            {
                byte[] src = blocks[idx];
                for (int j = 0; j < blockSize; j++) frame[HeaderLen + j] ^= src[j];
            }
            int n = HeaderLen + blockSize;
            PutU16(frame, n, Crc.Crc16(frame, 0, n));
            return Base45.Encode(frame);
        }

        private static void PutU16(byte[] b, int o, int v)
        {
            b[o] = (byte)(v & 0xFF);
            b[o + 1] = (byte)((v >> 8) & 0xFF);
        }

        private static void PutU32(byte[] b, int o, uint v)
        {
            b[o] = (byte)(v & 0xFF);
            b[o + 1] = (byte)((v >> 8) & 0xFF);
            b[o + 2] = (byte)((v >> 16) & 0xFF);
            b[o + 3] = (byte)((v >> 24) & 0xFF);
        }
    }
}
