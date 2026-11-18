// Shrinks images before sending (spec §5.1): EXIF orientation applied, long side <= maxSide, flattened on white, JPEG.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace DynamicQr
{
    public static class ImagePrep
    {
        private static readonly string[] Supported = { ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff" };
        private const int OrientationTag = 0x0112;

        public static bool IsSupported(string path)
        {
            string ext = Path.GetExtension(path);
            if (string.IsNullOrEmpty(ext)) return false;
            return Array.IndexOf(Supported, ext.ToLowerInvariant()) >= 0;
        }

        // "<base>.jpg", then "<base>_2.jpg", "<base>_3.jpg"... ; taken must be case-insensitive.
        public static string OutputName(string path, ISet<string> taken)
        {
            string stem = Path.GetFileNameWithoutExtension(path);
            string name = stem + ".jpg";
            for (int n = 2; taken.Contains(name); n++) name = stem + "_" + n + ".jpg";
            taken.Add(name);
            return name;
        }

        public static byte[] Prepare(string path, int maxSide, long quality)
        {
            byte[] raw = File.ReadAllBytes(path);
            using (MemoryStream ms = new MemoryStream(raw))
            using (Image loaded = Image.FromStream(ms))
            using (Bitmap oriented = new Bitmap(loaded))
            {
                RotateFlipType flip = OrientationToFlip(loaded);
                if (flip != RotateFlipType.RotateNoneFlipNone) oriented.RotateFlip(flip);

                int w = oriented.Width, h = oriented.Height;
                int longSide = Math.Max(w, h);
                if (longSide > maxSide)
                {
                    double scale = (double)maxSide / longSide;
                    w = Math.Max(1, (int)Math.Round(w * scale));
                    h = Math.Max(1, (int)Math.Round(h * scale));
                }

                using (Bitmap canvas = new Bitmap(w, h, PixelFormat.Format24bppRgb))
                {
                    using (Graphics g = Graphics.FromImage(canvas))
                    using (ImageAttributes attrs = new ImageAttributes())
                    {
                        g.Clear(Color.White);
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        g.CompositingQuality = CompositingQuality.HighQuality;
                        g.SmoothingMode = SmoothingMode.HighQuality;
                        attrs.SetWrapMode(WrapMode.TileFlipXY);
                        g.DrawImage(oriented, new Rectangle(0, 0, w, h), 0, 0, oriented.Width, oriented.Height, GraphicsUnit.Pixel, attrs);
                    }
                    using (MemoryStream outStream = new MemoryStream())
                    {
                        EncoderParameters p = new EncoderParameters(1);
                        p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
                        canvas.Save(outStream, JpegCodec(), p);
                        return outStream.ToArray();
                    }
                }
            }
        }

        private static RotateFlipType OrientationToFlip(Image img)
        {
            if (Array.IndexOf(img.PropertyIdList, OrientationTag) < 0) return RotateFlipType.RotateNoneFlipNone;
            byte[] v = img.GetPropertyItem(OrientationTag).Value;
            if (v == null || v.Length < 2) return RotateFlipType.RotateNoneFlipNone;
            switch (BitConverter.ToUInt16(v, 0))
            {
                case 2: return RotateFlipType.RotateNoneFlipX;
                case 3: return RotateFlipType.Rotate180FlipNone;
                case 4: return RotateFlipType.Rotate180FlipX;
                case 5: return RotateFlipType.Rotate90FlipX;
                case 6: return RotateFlipType.Rotate90FlipNone;
                case 7: return RotateFlipType.Rotate270FlipX;
                case 8: return RotateFlipType.Rotate270FlipNone;
                default: return RotateFlipType.RotateNoneFlipNone;
            }
        }

        private static ImageCodecInfo JpegCodec()
        {
            foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders())
                if (c.FormatID == ImageFormat.Jpeg.Guid) return c;
            throw new InvalidOperationException("No JPEG encoder available");
        }
    }
}
