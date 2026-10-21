<#
.SYNOPSIS
    Converts simulated audio (sim/out/audio.raw) to a WAV, and optionally
    compares it with a MAME recording (mame -wavwrite) of the same inputs.

.DESCRIPTION
    Both are 48 kHz mono 16-bit. The two are aligned on the first non-silent
    sample, refined by cross-correlation, then compared in 0.1 s windows
    (RMS level of each and correlation). -Plot draws both waveforms overlaid
    for a stretch of time.

.EXAMPLE
    .\sim\audio_tool.ps1 -Mame C:\mame\nib_game.wav -Plot 1.0
#>
param(
    [string]$Raw = (Join-Path $PSScriptRoot 'out\audio.raw'),
    [string]$Mame,
    [double]$Plot = -1,         # seconds after the first sound to plot (50 ms window)
    [int]$Windows = 40
)

$ErrorActionPreference = 'Stop'
$Raw = (Resolve-Path $Raw).Path
$wav = [IO.Path]::ChangeExtension($Raw, '.wav')

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Drawing;

public static class AudioTool {
    public static short[] ReadRaw(string path) {
        var b = File.ReadAllBytes(path);
        var s = new short[b.Length / 2];
        for (int i = 0; i < s.Length; i++) s[i] = (short)(b[2 * i] | (b[2 * i + 1] << 8));
        return s;
    }

    public static short[] ReadWav(string path) {
        var b = File.ReadAllBytes(path);
        int pos = 12;
        while (pos + 8 <= b.Length) {
            string id = Encoding.ASCII.GetString(b, pos, 4);
            int len = BitConverter.ToInt32(b, pos + 4);
            if (id == "data") {
                var s = new short[len / 2];
                for (int i = 0; i < s.Length; i++) s[i] = BitConverter.ToInt16(b, pos + 8 + 2 * i);
                return s;
            }
            pos += 8 + len;
        }
        throw new Exception("no data chunk");
    }

    public static void WriteWav(string path, short[] s) {
        using (var w = new BinaryWriter(File.Create(path))) {
            w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + s.Length * 2);
            w.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); w.Write(16); w.Write((short)1); w.Write((short)1);
            w.Write(48000); w.Write(96000); w.Write((short)2); w.Write((short)16);
            w.Write(Encoding.ASCII.GetBytes("data")); w.Write(s.Length * 2);
            foreach (var v in s) w.Write(v);
        }
    }

    public static int Onset(short[] s) {
        for (int i = 0; i < s.Length; i++) if (Math.Abs((int)s[i]) > 64) return i;
        return -1;
    }

    // best lag of b relative to a (b[i + lag] ~ a[i]) within +-range, over n samples from a0
    public static int BestLag(short[] a, int a0, short[] b, int b0, int n, int range) {
        double best = double.MinValue; int bestLag = 0;
        for (int lag = -range; lag <= range; lag++) {
            double sum = 0;
            for (int i = 0; i < n; i++) {
                int j = b0 + i + lag;
                if (a0 + i >= a.Length || j < 0 || j >= b.Length) break;
                sum += (double)a[a0 + i] * b[j];
            }
            if (sum > best) { best = sum; bestLag = lag; }
        }
        return bestLag;
    }

    public static string Compare(short[] a, int a0, short[] b, int b0, int windows) {
        var sb = new StringBuilder();
        sb.AppendLine("  time    MAME rms   sim rms   correlation");
        int n = 4800;
        for (int w = 0; w < windows; w++) {
            double sa = 0, sb2 = 0, sab = 0; int cnt = 0;
            for (int i = 0; i < n; i++) {
                int ia = a0 + w * n + i, ib = b0 + w * n + i;
                if (ia >= a.Length || ib >= b.Length) break;
                sa += (double)a[ia] * a[ia]; sb2 += (double)b[ib] * b[ib]; sab += (double)a[ia] * b[ib]; cnt++;
            }
            if (cnt == 0) break;
            double corr = (sa > 0 && sb2 > 0) ? sab / Math.Sqrt(sa * sb2) : double.NaN;
            sb.AppendLine(String.Format("  {0,4:0.0}s  {1,8:0}  {2,8:0}   {3,8:0.000}",
                w * 0.1, Math.Sqrt(sa / cnt), Math.Sqrt(sb2 / cnt), corr));
        }
        return sb.ToString();
    }

    public static void Plot(string path, short[] a, int a0, short[] b, int b0, int n) {
        int W = 1200, H = 400;
        using (var bmp = new Bitmap(W, H))
        using (var g = Graphics.FromImage(bmp)) {
            g.Clear(Color.White);
            g.DrawLine(Pens.LightGray, 0, H / 2, W, H / 2);
            DrawTrace(g, a, a0, n, W, H, Pens.Blue);
            DrawTrace(g, b, b0, n, W, H, Pens.Red);
            g.DrawString("blue: MAME   red: core (sim)", SystemFonts.DefaultFont, Brushes.Black, 4, 4);
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
    }

    static void DrawTrace(Graphics g, short[] s, int s0, int n, int W, int H, Pen pen) {
        PointF prev = PointF.Empty;
        for (int i = 0; i < n && s0 + i < s.Length; i++) {
            var p = new PointF(i * (float)W / n, H / 2 - s[s0 + i] * (H / 2f) / 32768f);
            if (i > 0) g.DrawLine(pen, prev, p);
            prev = p;
        }
    }
}
'@

$sim = [AudioTool]::ReadRaw($Raw)
[AudioTool]::WriteWav($wav, $sim)
Write-Host "Wrote $wav ($([math]::Round($sim.Length / 48000.0, 2)) s)"

if ($Mame) {
    $ref = [AudioTool]::ReadWav((Resolve-Path $Mame).Path)
    $oa = [AudioTool]::Onset($ref); $ob = [AudioTool]::Onset($sim)
    if ($oa -lt 0 -or $ob -lt 0) { throw "no sound found (MAME onset $oa, sim onset $ob)" }
    $lag = [AudioTool]::BestLag($ref, $oa, $sim, $ob, 9600, 800)
    $ob += $lag
    Write-Host ("First sound: MAME {0:0.000} s, sim {1:0.000} s (aligned with lag {2} samples)" -f ($oa / 48000.0), ($ob / 48000.0), $lag)
    Write-Host ([AudioTool]::Compare($ref, $oa, $sim, $ob, $Windows))
    if ($Plot -ge 0) {
        $png = [IO.Path]::ChangeExtension($Raw, ".plot_$($Plot).png")
        $off = [int]($Plot * 48000)
        [AudioTool]::Plot($png, $ref, $oa + $off, $sim, $ob + $off, 2400)
        Write-Host "Plot: $png"
    }
}
