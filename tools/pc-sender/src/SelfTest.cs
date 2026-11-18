// Self-test for the sender (run: DynamicQrSender.ps1 -SelfTest). C# 5 only.
using System;
using System.Collections.Generic;
using System.Text;
using QRCoder;

namespace DynamicQr
{
    public static class SelfTest
    {
        private static int failures;

        private static void Check(string name, bool ok, string detail)
        {
            if (ok)
            {
                Console.WriteLine("PASS " + name);
            }
            else
            {
                failures++;
                Console.WriteLine("FAIL " + name + ": " + detail);
            }
        }

        private static void Check(string name, Func<bool> test)
        {
            try
            {
                Check(name, test(), "returned false");
            }
            catch (Exception e)
            {
                Check(name, false, e.GetType().Name + ": " + e.Message);
            }
        }

        private static byte[] RandomBytes(int n, int seed)
        {
            byte[] b = new byte[n];
            new Random(seed).NextBytes(b);
            return b;
        }

        private static bool SameBytes(byte[] a, byte[] b)
        {
            if (a == null || b == null || a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        private static string Join(uint[] v)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < v.Length; i++) { if (i > 0) sb.Append(','); sb.Append(v[i]); }
            return sb.ToString();
        }

        private static int RoundTrip(byte[] bundle, int blockSize, uint startId, double loss, int seed)
        {
            FrameEncoder enc = new FrameEncoder(bundle, blockSize, 0x0BADF00Du);
            ReferenceDecoder dec = new ReferenceDecoder();
            Random rnd = new Random(seed);
            int used = 0;
            for (uint id = startId; !dec.IsComplete; id++)
            {
                if (id > startId + 50 * enc.K + 1000) throw new Exception("decoder did not complete");
                if (rnd.NextDouble() < loss) continue;
                dec.AddFrameText(enc.FrameText(id));
                used++;
            }
            if (!SameBytes(dec.Bundle, bundle)) throw new Exception("bundle mismatch");
            return used;
        }

        public static bool Run()
        {
            failures = 0;
            byte[] digits = Encoding.ASCII.GetBytes("123456789");

            Check("crc32 check value", Crc.Crc32(digits, 0, digits.Length) == 0xCBF43926u,
                Crc.Crc32(digits, 0, digits.Length).ToString("X8"));
            Check("crc16 check value", Crc.Crc16(digits, 0, digits.Length) == 0x29B1,
                Crc.Crc16(digits, 0, digits.Length).ToString("X4"));
            Check("base45 Hello!!", Base45.Encode(Encoding.ASCII.GetBytes("Hello!!")) == "%69 VD92EX0",
                Base45.Encode(Encoding.ASCII.GetBytes("Hello!!")));
            Check("base45 AB", Base45.Encode(Encoding.ASCII.GetBytes("AB")) == "BB8",
                Base45.Encode(Encoding.ASCII.GetBytes("AB")));
            Check("mix32 pinned", Prng.Mix32(0, 0) == 2287948138u && Prng.Mix32(0x12345678u, 1000) == 222234753u,
                Prng.Mix32(0, 0) + " " + Prng.Mix32(0x12345678u, 1000));

            Mulberry32 m = new Mulberry32(1);
            uint[] seq = new uint[] { m.Next(), m.Next(), m.Next(), m.Next(), m.Next() };
            Check("mulberry32 pinned", Join(seq) == "2693262067,11749833,2265367787,4213581821,4159151403", Join(seq));

            int[] nb = Lt.Neighbors(0x12345678u, 1000, 5, 188);
            Check("lt neighbours pinned", nb.Length == 5 && nb[0] == 19 && nb[1] == 168 && nb[2] == 24 && nb[3] == 11 && nb[4] == 20,
                string.Join(",", Array.ConvertAll(nb, x => x.ToString())));
            Check("lt systematic below K", Lt.Neighbors(0x12345678u, 7, 3, 188).Length == 1 && Lt.Neighbors(0x12345678u, 7, 3, 188)[0] == 7, "");

            Check("robust soliton range and mean", delegate
            {
                RobustSoliton rs = new RobustSoliton(188);
                Mulberry32 r = new Mulberry32(99);
                double sum = 0;
                for (int i = 0; i < 10000; i++)
                {
                    int d = rs.Sample(r.Next());
                    if (d < 1 || d > 188) return false;
                    sum += d;
                }
                double mean = sum / 10000;
                return mean > 3 && mean < 15;
            });
            Check("robust soliton K=1", delegate { return new RobustSoliton(1).Sample(0xFFFFFFFFu) == 1; });

            Check("round trip 150000 B, 50% loss, start 300", delegate
            {
                byte[] bundle = RandomBytes(150000, 1);
                int k = (150000 + 799) / 800;
                int used = RoundTrip(bundle, 800, 300, 0.5, 1);
                Console.WriteLine("     frames used " + used + " for K=" + k);
                return used < 1.5 * k;
            });
            Check("round trip K=1", delegate { RoundTrip(RandomBytes(10, 2), 800, 5, 0.0, 2); return true; });

            Check("frame text uses only Base45 alphabet", delegate
            {
                const string alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
                FrameEncoder enc = new FrameEncoder(RandomBytes(5000, 3), 800, 77);
                for (uint id = 0; id < 30; id++)
                {
                    foreach (char c in enc.FrameText(id)) if (alphabet.IndexOf(c) < 0) return false;
                }
                return true;
            });

            Check("bundle writer layout", delegate
            {
                List<KeyValuePair<string, byte[]>> files = new List<KeyValuePair<string, byte[]>>();
                files.Add(new KeyValuePair<string, byte[]>("x", new byte[] { 7 }));
                byte[] b = BundleWriter.Pack(files);
                return SameBytes(b, new byte[] { 0x44, 0x51, 0x42, 0x31, 1, 0, 1, 0, 0x78, 1, 0, 0, 0, 7 });
            });

            Check("QR version <= 25 at block size 800, ECC L", delegate
            {
                FrameEncoder enc = new FrameEncoder(RandomBytes(5000, 4), 800, 77);
                QRCodeData data = new QRCodeGenerator().CreateQrCode(enc.FrameText(10), QRCodeGenerator.ECCLevel.L);
                Console.WriteLine("     QR version " + data.Version);
                return data.Version <= 25;
            });

            ImageChecks();

            Check("window module size fits the smaller of width and height minus status strip", delegate
            {
                return SenderForm.ModulePixels(1920, 1080, 105) == 9      // landscape: height limits
                    && SenderForm.ModulePixels(1080, 1920, 105) == 10     // portrait: width limits
                    && SenderForm.ModulePixels(800, 600, 105) == 5        // small resized window
                    && SenderForm.ModulePixels(100, 100, 105) == 1;       // never below 1 px
            });
            Check("fps is clamped to 1..30", delegate
            {
                return SenderForm.ClampFps(0) == 1 && SenderForm.ClampFps(31) == 30 && SenderForm.ClampFps(12) == 12;
            });

            Console.WriteLine(failures == 0 ? "SELFTEST PASS" : "SELFTEST FAIL (" + failures + ")");
            return failures == 0;
        }

        private static string TempImage(System.Drawing.Bitmap bmp, System.Drawing.Imaging.ImageFormat fmt, string ext)
        {
            string path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "dqr-selftest-" + Guid.NewGuid().ToString("N") + ext);
            bmp.Save(path, fmt);
            return path;
        }

        private static System.Drawing.Bitmap Decode(byte[] jpeg)
        {
            return new System.Drawing.Bitmap(new System.IO.MemoryStream(jpeg));
        }

        private static bool IsJpeg(byte[] b)
        {
            return b.Length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
        }

        private static void ImageChecks()
        {
            Check("large PNG with alpha -> 1280x960 JPEG on white", delegate
            {
                string path;
                using (System.Drawing.Bitmap src = new System.Drawing.Bitmap(4000, 3000, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
                {
                    using (System.Drawing.Graphics g = System.Drawing.Graphics.FromImage(src))
                    {
                        g.Clear(System.Drawing.Color.Transparent);
                        g.FillRectangle(System.Drawing.Brushes.Red, 2000, 0, 2000, 3000);
                    }
                    path = TempImage(src, System.Drawing.Imaging.ImageFormat.Png, ".png");
                }
                try
                {
                    byte[] jpeg = ImagePrep.Prepare(path, 1280, 80);
                    using (System.Drawing.Bitmap outBmp = Decode(jpeg))
                    {
                        System.Drawing.Color px = outBmp.GetPixel(100, 100);
                        return IsJpeg(jpeg) && outBmp.Width == 1280 && outBmp.Height == 960 && px.R >= 250 && px.G >= 250 && px.B >= 250;
                    }
                }
                finally { System.IO.File.Delete(path); }
            });

            Check("small image is not upscaled", delegate
            {
                string path;
                using (System.Drawing.Bitmap src = new System.Drawing.Bitmap(800, 600)) path = TempImage(src, System.Drawing.Imaging.ImageFormat.Bmp, ".bmp");
                try
                {
                    using (System.Drawing.Bitmap outBmp = Decode(ImagePrep.Prepare(path, 1280, 80))) return outBmp.Width == 800 && outBmp.Height == 600;
                }
                finally { System.IO.File.Delete(path); }
            });

            Check("EXIF orientation 6 is applied and metadata removed", delegate
            {
                string path;
                using (System.Drawing.Bitmap src = new System.Drawing.Bitmap(400, 200))
                {
                    System.Drawing.Imaging.PropertyItem item = (System.Drawing.Imaging.PropertyItem)
                        System.Runtime.Serialization.FormatterServices.GetUninitializedObject(typeof(System.Drawing.Imaging.PropertyItem));
                    item.Id = 0x0112;
                    item.Type = 3;
                    item.Len = 2;
                    item.Value = new byte[] { 6, 0 };
                    src.SetPropertyItem(item);
                    path = TempImage(src, System.Drawing.Imaging.ImageFormat.Jpeg, ".jpg");
                }
                try
                {
                    using (System.Drawing.Bitmap outBmp = Decode(ImagePrep.Prepare(path, 1280, 80)))
                    {
                        bool noOrientation = Array.IndexOf(outBmp.PropertyIdList, 0x0112) < 0;
                        return outBmp.Width == 200 && outBmp.Height == 400 && noOrientation;
                    }
                }
                finally { System.IO.File.Delete(path); }
            });

            Check("output names are .jpg and unique (case-insensitive)", delegate
            {
                HashSet<string> taken = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                string a = ImagePrep.OutputName(@"C:\x\a.png", taken);
                string b = ImagePrep.OutputName(@"C:\y\A.jpg", taken);
                string c = ImagePrep.OutputName(@"C:\z\a.bmp", taken);
                return a == "a.jpg" && b == "A_2.jpg" && c == "a_3.jpg";
            });

            Check("supported extensions", delegate
            {
                return ImagePrep.IsSupported("x.JPG") && ImagePrep.IsSupported("x.tiff") && ImagePrep.IsSupported("x.gif")
                    && !ImagePrep.IsSupported("x.webp") && !ImagePrep.IsSupported("x.heic") && !ImagePrep.IsSupported("x");
            });
        }
    }
}
