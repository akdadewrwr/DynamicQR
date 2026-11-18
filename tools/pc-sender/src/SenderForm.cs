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

        // Integer module size (no blur) so the whole code fits the client area above the status strip.
        public static int ModulePixels(int clientWidth, int clientHeight, int matrixSize)
        {
            return Math.Max(1, Math.Min(clientWidth, clientHeight - StatusHeight) / matrixSize);
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

            // A normal, resizable window (starts maximized); F11 toggles borderless full screen.
            Text = "DynamicQr sender";
            BackColor = Color.White;
            FormBorderStyle = FormBorderStyle.Sizable;
            StartPosition = FormStartPosition.CenterScreen;
            Rectangle work = Screen.PrimaryScreen.WorkingArea;
            Size = new Size(work.Width * 3 / 4, work.Height * 3 / 4);
            MinimumSize = new Size(320, 320);
            WindowState = FormWindowState.Maximized;
            DoubleBuffered = true;
            ResizeRedraw = true;
            KeyPreview = true;

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
                case Keys.F11:
                    ToggleFullScreen();
                    break;
                case Keys.Escape:
                    if (FormBorderStyle == FormBorderStyle.None) ToggleFullScreen();
                    else Close();
                    break;
            }
            base.OnKeyDown(e);
        }

        private void ToggleFullScreen()
        {
            if (FormBorderStyle == FormBorderStyle.None)
            {
                FormBorderStyle = FormBorderStyle.Sizable;
                WindowState = FormWindowState.Normal;
                WindowState = FormWindowState.Maximized;
            }
            else
            {
                FormBorderStyle = FormBorderStyle.None;
                WindowState = FormWindowState.Normal;
                WindowState = FormWindowState.Maximized;
            }
            Invalidate();
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
                int px = ModulePixels(ClientSize.Width, ClientSize.Height, size);
                int left = Math.Max(0, (ClientSize.Width - size * px) / 2);
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
                Dot + ((int)t.TotalMinutes).ToString("00") + ":" + t.Seconds.ToString("00");
            string hints = "     + / - speed" + Dot + "Space pause" + Dot + "F11 full screen" + Dot + "Esc quit";
            using (Font font = new Font("Segoe UI", 11))
            {
                SizeF sz = g.MeasureString(status + hints, font);
                if (sz.Width <= ClientSize.Width) status += hints;   // hints only when they fit
                else sz = g.MeasureString(status, font);
                g.DrawString(status, font, Brushes.Gray, (ClientSize.Width - sz.Width) / 2, ClientSize.Height - StatusHeight + (StatusHeight - sz.Height) / 2);
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            timer.Stop();
            base.OnFormClosed(e);
        }
    }
}
