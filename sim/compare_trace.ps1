<#
.SYNOPSIS
    Compares a simulation trace (sim/run_sim.ps1) against a MAME debugger trace.

.DESCRIPTION
    MAME trace: produced with the debugger command
        trace nib_trace.log,maincpu,noloop,{tracelog "%08X ",totalcycles}
    so each line is "<total cycles hex> <PC>: <disassembly>".

    Checks that the PC sequence matches, and that per-instruction cycle counts
    (including wait states) match. Stops at the first difference.

.EXAMPLE
    .\sim\compare_trace.ps1 -Mame C:\path\nib_trace.log
#>
param(
    [Parameter(Mandatory = $true)][string]$Mame,
    [string]$Sim = (Join-Path $PSScriptRoot 'out\sim_trace.log')
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

public static class TraceCompare {
    public static string Run(string mamePath, string simPath) {
        var mPc = new List<int>(); var mCyc = new List<long>(); var mText = new List<string>();
        foreach (var line in File.ReadLines(mamePath)) {
            if (line.Length < 14 || line[8] != ' ' || line[13] != ':') continue;
            mCyc.Add(long.Parse(line.Substring(0, 8), NumberStyles.HexNumber));
            mPc.Add(int.Parse(line.Substring(9, 4), NumberStyles.HexNumber));
            mText.Add(line.Substring(9));
        }
        var sPc = new List<int>(); var sCyc = new List<long>();
        foreach (var line in File.ReadLines(simPath)) {
            var p = line.Split(' ');
            if (p.Length < 2) continue;
            sPc.Add(int.Parse(p[0], NumberStyles.HexNumber));
            sCyc.Add(long.Parse(p[1]));
        }

        int s0 = sPc.IndexOf(mPc[0]);
        if (s0 < 0) return "FAIL: sim never reaches MAME's first PC " + mPc[0].ToString("X4");

        // Interrupt entry (the step into the IRQ/NMI handler) is allowed to differ
        // in cycles: MAME and T65 place wait states in that sequence differently.
        // The drift is tracked and reported; any other difference stops the run.
        int n = Math.Min(mPc.Count, sPc.Count - s0) - 1;
        int interrupts = 0;
        long drift = 0;
        for (int i = 0; i < n; i++) {
            if (mPc[i] != sPc[s0 + i]) {
                return String.Format("FAIL: PC differs at instruction {0}: MAME {1:X4}, sim {2:X4} (after {3} interrupts, drift {4} cycles)\n{5}",
                    i, mPc[i], sPc[s0 + i], interrupts, drift, Context(mText, i));
            }
            long md = mCyc[i + 1] - mCyc[i];
            long sd = sCyc[s0 + i + 1] - sCyc[s0 + i];
            bool entry = mPc[i + 1] == 0x3009 || mPc[i + 1] == 0x3000;
            if (entry) {
                interrupts++;
                drift += sd - md;
            } else if (sd != md) {
                return String.Format("FAIL: cycle count differs at instruction {0} ({1}): MAME {2}, sim {3}\n{4}",
                    i, mText[i], md, sd, Context(mText, i));
            }
        }
        return String.Format("PASS: {0} instructions match ({1} interrupts, sim drift {2} cycles at interrupt entries). Last: {3}",
            n, interrupts, drift, mText[n - 1]);
    }

    static string Context(List<string> t, int i) {
        var s = "";
        for (int k = Math.Max(0, i - 6); k <= Math.Min(t.Count - 1, i + 2); k++)
            s += (k == i ? "  >> " : "     ") + t[k] + "\n";
        return s;
    }
}
'@

[TraceCompare]::Run((Resolve-Path $Mame).Path, (Resolve-Path $Sim).Path)
