using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Win11Optimizer
{
    static class Program
    {
        // Win11 Optimizer.exe                 the window
        // Win11 Optimizer.exe --shots <dir>   writes a picture of every page with made-up data (nothing is started)
        // Win11 Optimizer.exe --lang th|en   (with --shots: the language of the pictures)
        // Win11 Optimizer.exe --selftest --out <file>   runs the checks of the app without a window and writes the result
        [STAThread]
        static int Main(string[] args)
        {
            string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            string shots = null;
            string outFile = null;
            bool selftest = false;
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--root" && i + 1 < args.Length) root = args[++i];
                else if (args[i] == "--shots" && i + 1 < args.Length) shots = args[++i];
                else if (args[i] == "--out" && i + 1 < args.Length) outFile = args[++i];
                else if (args[i] == "--selftest") selftest = true;
                else if (args[i] == "--theme" && i + 1 < args.Length) Theme.Force = args[++i];
            }
            Runner.Root = root;
            Loc.Init();
            for (int j = 0; j < args.Length; j++) { if (args[j] == "--lang" && j + 1 < args.Length && (args[j + 1] == "th" || args[j + 1] == "en")) Loc.Lang = args[j + 1]; }

            if (selftest) return SelfTest.Run(outFile);

            Application app = new Application();
            app.ShutdownMode = ShutdownMode.OnMainWindowClose;
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Win11Optimizer.Styles.xaml"))
            {
                app.Resources.MergedDictionaries.Add((ResourceDictionary)XamlReader.Load(s));
            }
            Theme.Apply(app.Resources);

            if (!Runner.LooksRight(root) && shots == null)
            {
                MessageBox.Show("Win11 Optimizer.exe has to stay in the same folder as the folders \"tools\", \"reg\" and \"reg_undo\".\n\nExtract the whole ZIP first, then open the program from that folder.",
                    "Windows 11 Optimizer", MessageBoxButton.OK, MessageBoxImage.Information);
                return 2;
            }

            MainWindow mw = new MainWindow(shots != null);
            if (shots != null) return TakePictures(app, mw, shots);
            app.Run(mw.Win);
            return 0;
        }

        internal static void Idle(Window w)
        {
            w.Dispatcher.Invoke(DispatcherPriority.ApplicationIdle, new Action(delegate { }));
        }

        static int TakePictures(Application app, MainWindow mw, string dir)
        {
            Directory.CreateDirectory(dir);
            mw.Win.Show();
            string[] pages = new string[] { "Home", "Tweaks", "Tools", "Undo", "About" };
            for (int i = 0; i < pages.Length; i++)
            {
                mw.Navigate(pages[i]);
                Idle(mw.Win);
                Save(mw.Win, Path.Combine(dir, (i + 1) + "_" + pages[i] + ".png"));
            }
            mw.PictureEasy(Path.Combine(dir, "6_Easy_dialog.png"));
            mw.PictureAsk(Path.Combine(dir, "7_Ask_dialog.png"));
            mw.Win.Close();
            return 0;
        }

        internal static void Save(Window w, string path)
        {
            w.UpdateLayout();
            FrameworkElement root = (FrameworkElement)w.Content;
            double width = root.ActualWidth;
            double height = root.ActualHeight;
            if (w.SizeToContent != SizeToContent.Manual)
            {
                // a dialog: its size is the size of what it holds
                root.Measure(new Size(w.ActualWidth, double.PositiveInfinity));
                width = w.ActualWidth;
                height = root.DesiredSize.Height;
            }
            int pw = (int)(width * 2);
            int ph = (int)(height * 2);
            DrawingVisual dv = new DrawingVisual();
            using (DrawingContext dc = dv.RenderOpen())
            {
                dc.DrawRectangle(w.Background, null, new Rect(0, 0, width, height));
                dc.DrawRectangle(new VisualBrush(root), null, new Rect(0, 0, width, height));
            }
            RenderTargetBitmap rtb = new RenderTargetBitmap(pw, ph, 192, 192, PixelFormats.Pbgra32);
            rtb.Render(dv);
            PngBitmapEncoder enc = new PngBitmapEncoder();
            enc.Frames.Add(BitmapFrame.Create(rtb));
            using (FileStream fs = File.Create(path)) { enc.Save(fs); }
        }
    }

    // Checks the parts of the app that do not need a window: the status script, its reading, and apply and revert of one tweak.
    static class SelfTest
    {
        static List<string> report = new List<string>();
        static bool allOk = true;

        static void Check(string name, bool ok, string detail)
        {
            if (!ok) allOk = false;
            report.Add((ok ? "PASS  " : "FAIL  ") + name + (detail != null && detail.Length > 0 ? "  (" + detail + ")" : ""));
        }

        static Dictionary<string, string> Status()
        {
            List<string> lines = new List<string>();
            Runner.RunWait(Runner.PowerShellExe, Runner.ScriptArgs(@"tools\Gui_Status.ps1", "-Root \"" + Runner.Root + "\""), lines, 180000);
            Dictionary<string, string> map = new Dictionary<string, string>();
            foreach (StatusItem s in StatusReader.Parse(lines)) { if (!map.ContainsKey(s.Id)) map[s.Id] = s.Status; }
            return map;
        }

        static string Run(string args, out int code)
        {
            List<string> lines = new List<string>();
            code = Runner.RunWait("cmd.exe", args, lines, 240000);
            return string.Join("\n", lines.ToArray());
        }

        public static int Run(string outFile)
        {
            bool admin = false;
            try { admin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); } catch { }
            Check("running as administrator", admin, null);
            Check("tool folder is complete", Runner.LooksRight(Runner.Root), Runner.Root);
            Check("version is read", Runner.Version().Length > 0, Runner.Version());

            Dictionary<string, string> before = Status();
            bool allIds = true;
            foreach (Tweak t in Catalog.All) { if (!before.ContainsKey(t.Id)) allIds = false; }
            Check("the status script lists every tweak of the catalog", allIds, before.Count + " items");

            string bat = "1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat";
            int code;
            string o1 = Run("/d /s /c " + Runner.Bat(bat, "/apply 10"), out code);
            Check("/apply 10 finishes", code == 0 && o1.IndexOf("applied", StringComparison.OrdinalIgnoreCase) >= 0, "exit " + code);
            Dictionary<string, string> mid = Status();
            Check("tweak 10 reads On after /apply", mid.ContainsKey("10") && mid["10"] == "OK", mid.ContainsKey("10") ? mid["10"] : "missing");

            string o2 = Run("/d /s /c " + Runner.Bat(bat, "/revert 10"), out code);
            Check("/revert 10 finishes", code == 0 && o2.IndexOf("reverted", StringComparison.OrdinalIgnoreCase) >= 0, "exit " + code);
            Dictionary<string, string> after = Status();
            Check("tweak 10 reads Off after /revert", after.ContainsKey("10") && after["10"] != "OK", after.ContainsKey("10") ? after["10"] : "missing");

            int ok, total;
            List<StatusItem> items = new List<StatusItem>();
            foreach (KeyValuePair<string, string> kv in after) { StatusItem si = new StatusItem(); si.Id = kv.Key; si.Status = kv.Value; items.Add(si); }
            StatusReader.Count(items, out ok, out total);
            Check("the counts make sense", total >= 8 && ok <= total, ok + " of " + total);

            report.Add(allOk ? "ALL PASSED" : "SOME FAILED");
            string text = string.Join("\r\n", report.ToArray()) + "\r\n";
            if (outFile != null) { try { File.WriteAllText(outFile, text, new UTF8Encoding(false)); } catch { } }
            return allOk ? 0 : 1;
        }
    }
}
