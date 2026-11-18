// Full-screen window that plays the endless fountain-coded QR animation (spec §5.5).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using QRCoder;

namespace DynamicQr
{
    public class SenderForm : Form
    {
        public const int StatusHeight = 40;
        private const string Dot = " · ";

        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        private readonly FrameEncoder encoder;
        private readonly QRCodeGenerator generator = new QRCodeGenerator();
        private readonly QRCodeGenerator.ECCLevel ecc;
        private readonly Timer timer = new Timer();
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly string summary;
        private List<BitArray> matrix;
        private uint blockId;
        private int fps;
        private bool paused;

        // Without this, Windows bitmap-scales the window on high-DPI screens and blurs the QR modules.
        public static void EnableDpiAwareness()
        {
            try { SetProcessDPIAware(); } catch (Exception) { }
        }

        public static int ModulePixels(int clientHeight, int matrixSize)
        {
            return Math.Max(1, (clientHeight - StatusHeight) / matrixSize);
        }

        public static int ClampFps(int value)
        {
            return Math.Max(1, Math.Min(30, value));
        }

        public SenderForm(FrameEncoder enc, int fps, QRCodeGenerator.ECCLevel ecc, int fileCount, int bundleLen)
        {
            encoder = enc;
            this.ecc = ecc;
            this.fps = ClampFps(fps);
            summary = fileCount + (fileCount == 1 ? " file" : " files") + Dot + (bundleLen + 1023) / 1024 + " KB" + Dot + "K=" + enc.K;

            Text = "DynamicQr sender";
            BackColor = Color.White;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = Screen.PrimaryScreen.Bounds;
            WindowState = FormWindowState.Maximized;
            TopMost = true;
            DoubleBuffered = true;
            KeyPreview = true;
            Cursor.Hide();

            ShowFrame();
            timer.Interval = 1000 / this.fps;
            timer.Tick += delegate { if (!paused) { blockId++; ShowFrame(); } };
            timer.Start();
        }

        private void ShowFrame()
        {
            matrix = generator.CreateQrCode(encoder.FrameText(blockId), ecc).ModuleMatrix;
            Invalidate();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            switch (e.KeyCode)
            {
                case Keys.Oemplus:
                case Keys.Add:
                    SetFps(fps + 1);
                    break;
                case Keys.OemMinus:
                case Keys.Subtract:
                    SetFps(fps - 1);
                    break;
                case Keys.Space:
                    paused = !paused;
                    Invalidate();
                    break;
                case Keys.Escape:
                    Close();
                    break;
            }
            base.OnKeyDown(e);
        }

        private void SetFps(int value)
        {
            fps = ClampFps(value);
            timer.Interval = 1000 / fps;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Color.White);
            if (matrix != null)
            {
                int size = matrix.Count;
                int px = ModulePixels(ClientSize.Height, size);
                int left = (ClientSize.Width - size * px) / 2;
                int top = Math.Max(0, (ClientSize.Height - StatusHeight - size * px) / 2);
                for (int y = 0; y < size; y++)
                {
                    BitArray row = matrix[y];
                    for (int x = 0; x < size; x++)
                    {
                        if (row[x]) g.FillRectangle(Brushes.Black, left + x * px, top + y * px, px, px);
                    }
                }
            }
            TimeSpan t = clock.Elapsed;
            string status = summary + Dot + "block " + blockId + Dot + fps + " fps" + (paused ? Dot + "PAUSED" : "") +
                Dot + ((int)t.TotalMinutes).ToString("00") + ":" + t.Seconds.ToString("00") +
                "     + / - speed" + Dot + "Space pause" + Dot + "Esc quit";
            using (Font font = new Font("Segoe UI", 11))
            {
                SizeF sz = g.MeasureString(status, font);
                g.DrawString(status, font, Brushes.Gray, (ClientSize.Width - sz.Width) / 2, ClientSize.Height - StatusHeight + (StatusHeight - sz.Height) / 2);
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            timer.Stop();
            Cursor.Show();
            base.OnFormClosed(e);
        }
    }
}
