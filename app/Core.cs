// Windows 11 Optimizer - the app (Win11 Optimizer.exe). Plain C# 5 so that the compiler that ships with Windows can build it.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace Win11Optimizer
{
    // Light or dark, as Windows is set. The brushes are looked up by name from Styles.xaml and from the code.
    static class Theme
    {
        public static bool Dark;
        public static string Force;     // "light" or "dark" (for the pictures); otherwise Windows decides

        public static void Apply(ResourceDictionary r)
        {
            Dark = (Force == null) ? IsDark() : (Force == "dark");
            Set(r, "Bg", Dark ? "#0F1115" : "#F5F6F8");
            Set(r, "Surface", Dark ? "#171A20" : "#FFFFFF");
            Set(r, "SurfaceAlt", Dark ? "#20242C" : "#EEF0F4");
            Set(r, "Line", Dark ? "#2B303A" : "#E1E4EA");
            Set(r, "Ink", Dark ? "#E9ECF2" : "#14181F");
            Set(r, "Muted", Dark ? "#9CA5B4" : "#5B6472");
            Set(r, "Accent", Dark ? "#3563E9" : "#2563EB");
            Set(r, "AccentSoft", Dark ? "#1B2742" : "#E8EFFD");
            Set(r, "Good", Dark ? "#4ADE80" : "#15803D");
            Set(r, "Warn", Dark ? "#FBBF24" : "#B45309");
            Set(r, "Bad", Dark ? "#F87171" : "#B91C1C");
            Set(r, "LogBg", Dark ? "#0B0D11" : "#10141B");
        }

        static bool IsDark()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    object v = (k == null) ? null : k.GetValue("AppsUseLightTheme");
                    return (v is int) && ((int)v == 0);
                }
            }
            catch { return false; }
        }

        static void Set(ResourceDictionary r, string key, string hex)
        {
            SolidColorBrush b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            b.Freeze();
            r[key] = b;
        }

        public static Brush Get(string key) { return (Brush)Application.Current.Resources[key]; }
    }

    // One tweak of the tool (the numbers are the ones in the manual and in the main menu).
    class Tweak
    {
        public string Id;
        public string Title;
        public string Desc;
        public string Group;       // Recommended, Optional, Power
        public bool Caution;       // asks twice before it is turned on
        public string Status = "UNKNOWN";

        public Tweak(string id, string group, string title, string desc, bool caution)
        {
            Id = id; Group = group; Title = title; Desc = desc; Caution = caution;
        }

        public bool IsOn { get { return Status == "OK"; } }
    }

    static class Catalog
    {
        public static readonly List<Tweak> All = new List<Tweak>
        {
            new Tweak("01", "Recommended", "Game Bar recording off", "Stops Xbox Game Bar from recording in the background (Game DVR). Game Mode stays on.", false),
            new Tweak("02", "Recommended", "Power throttling off", "Windows no longer slows down programs it thinks are in the background. A little more power use.", false),
            new Tweak("03", "Recommended", "Gaming priority", "Gives games higher CPU, graphics and disk priority.", false),
            new Tweak("04", "Recommended", "Foreground priority", "The program in front, such as your game, gets more CPU time than the ones behind it.", false),
            new Tweak("05", "Recommended", "Telemetry off", "Sends less diagnostic data to Microsoft.", false),
            new Tweak("06", "Recommended", "System responsiveness", "Keeps menus and apps lively while a game is running.", false),
            new Tweak("07", "Recommended", "Delivery Optimization off", "Windows Update no longer shares updates with other PCs.", false),
            new Tweak("08", "Recommended", "GPU scheduling on", "Lets the graphics card schedule its own work. Needs a restart.", false),
            new Tweak("09", "Optional", "Fullscreen exclusive", "Uses true fullscreen in games instead of borderless windows.", false),
            new Tweak("10", "Optional", "Mouse without acceleration", "The pointer moves exactly as far as your hand does.", false),
            new Tweak("11", "Optional", "Keyboard fast repeat", "Keys repeat sooner and faster.", false),
            new Tweak("12", "Optional", "Network memory fix", "Fixes a memory problem in a Windows network driver on some PCs.", false),
            new Tweak("13", "Optional", "Memory Integrity off", "Can raise FPS on some PCs but lowers protection against malware. Needs a restart.", true),
            new Tweak("15", "Optional", "Finer timer", "A finer system timer for smoother frame pacing. More battery use on laptops.", false),
            new Tweak("16", "Optional", "CPU boost", "Keeps the processor boosting. The PC runs hotter and louder; not for laptops.", false),
            new Tweak("14", "Power", "CPU power options", "Unlocks hidden CPU power options and sets the plugged-in power plan. For desktops.", false)
        };

        public static Tweak Find(string id)
        {
            foreach (Tweak t in All) { if (t.Id == id) return t; }
            return null;
        }
    }

    // Starts the tool's scripts and gives their output back line by line.
    static class Runner
    {
        public static string Root;

        public static string PowerShellExe
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe"); }
        }

        public static string Path1(string relative) { return Path.Combine(Root, relative); }

        public static string ScriptArgs(string relative, string extra)
        {
            return "-NoProfile -ExecutionPolicy Bypass -File \"" + Path1(relative) + "\" " + extra;
        }

        public static string Version()
        {
            try { return File.ReadAllText(Path1("VERSION")).Trim(); } catch { return ""; }
        }

        public static bool LooksRight(string root)
        {
            return File.Exists(Path.Combine(root, @"tools\Easy_Setup.ps1")) && Directory.Exists(Path.Combine(root, "reg")) && File.Exists(Path.Combine(root, @"tools\Gui_Status.ps1"));
        }

        // Runs a program without a window. onLine is called for every output line (from another thread), onExit with the exit code.
        public static Process RunCaptured(string file, string args, Action<string> onLine, Action<int> onExit)
        {
            ProcessStartInfo psi = new ProcessStartInfo(file, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = Root;
            psi.RedirectStandardInput = true;       // closed at once: a question in the script gets its default answer
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;
            Process p = new Process();
            p.StartInfo = psi;
            p.EnableRaisingEvents = true;
            p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null && onLine != null) onLine(e.Data); };
            p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null && onLine != null) onLine(e.Data); };
            p.Exited += delegate(object s, EventArgs e)
            {
                int code = -1;
                try { p.WaitForExit(); code = p.ExitCode; } catch { }
                if (onExit != null) onExit(code);
            };
            p.Start();
            try { p.StandardInput.Close(); } catch { }
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            return p;
        }

        // Runs a program and waits for it (used by the self test and the status check).
        public static int RunWait(string file, string args, List<string> lines, int timeoutMs)
        {
            ProcessStartInfo psi = new ProcessStartInfo(file, args);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = Root;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.UTF8;
            Process p = Process.Start(psi);
            try { p.StandardInput.Close(); } catch { }
            System.Threading.Tasks.Task<string> err = p.StandardError.ReadToEndAsync();
            System.Threading.Tasks.Task<string> output = p.StandardOutput.ReadToEndAsync();
            if (!p.WaitForExit(timeoutMs)) { try { p.Kill(); } catch { } return -1; }
            string text = output.Result;
            foreach (string l in text.Replace("\r", "").Split('\n')) { if (l.Length > 0) lines.Add(l); }
            return p.ExitCode;
        }

        // Opens a normal console window (for the questions that need you). It stays open until a key is pressed.
        public static Process OpenConsole(string cmdArguments)
        {
            ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", cmdArguments);
            psi.WorkingDirectory = Root;
            psi.UseShellExecute = true;
            return Process.Start(psi);
        }

        public static string Bat(string relative, string extra)
        {
            return "\"\"" + Path1(relative) + "\" " + extra + "\"";
        }

        public static void Open(string pathOrUrl)
        {
            try { Process.Start(new ProcessStartInfo(pathOrUrl) { UseShellExecute = true, WorkingDirectory = Root }); } catch { }
        }

        public static string Find(string folder, string pattern)
        {
            try
            {
                string dir = Path1(folder);
                if (!Directory.Exists(dir)) return null;
                string[] files = Directory.GetFiles(dir, pattern);
                if (files.Length == 0) return null;
                Array.Sort(files);
                return files[files.Length - 1];
            }
            catch { return null; }
        }
    }

    // Reads the lines of tools\Gui_Status.ps1: "<id>|<status>|<title>"
    class StatusItem
    {
        public string Id;
        public string Status;
        public string Title;
    }

    static class StatusReader
    {
        public static List<StatusItem> Parse(IEnumerable<string> lines)
        {
            List<StatusItem> list = new List<StatusItem>();
            foreach (string l in lines)
            {
                string[] parts = l.Split(new char[] { '|' }, 3);
                if (parts.Length < 2) continue;
                if (parts[0].Length == 0 || parts[1].Length == 0) continue;
                StatusItem s = new StatusItem();
                s.Id = parts[0].Trim();
                s.Status = parts[1].Trim();
                s.Title = parts.Length > 2 ? parts[2].Trim() : "";
                list.Add(s);
            }
            return list;
        }

        // "in place" and "of": the same idea as the summary of Easy Setup (skipped and unknown settings are left out)
        public static void Count(List<StatusItem> items, out int ok, out int total)
        {
            ok = 0; total = 0;
            foreach (StatusItem s in items)
            {
                if (s.Status == "OK") { ok++; total++; }
                else if (s.Status == "CHANGED" || s.Status == "MISSING") { total++; }
            }
        }
    }
}
