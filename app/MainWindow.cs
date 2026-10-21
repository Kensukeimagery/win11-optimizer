using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;

namespace Win11Optimizer
{
    // The window: a quiet side bar and five pages. Everything it does is done by the tool's own scripts.
    class MainWindow
    {
        const string MasterBat = "1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat";
        const string RevertBat = "2_Revert_Everything - System_Restore (Run as Administrator).bat";

        public Window Win;
        public bool Demo;                      // for the pictures: made-up status, nothing is started
        string pictureTarget;                  // set while a dialog is drawn into a picture file instead of being shown

        ContentControl pageHost;
        ScrollViewer pageScroll;
        Border activity;
        TextBlock activityTitle;
        TextBox activityLog;
        TextBlock versionText;
        Button closeButton, copyButton;
        ProgressBar activityBar;
        RadioButton[] navButtons;
        string[] navNames = new string[] { "Home", "Tweaks", "Tools", "Undo", "About" };

        string currentPage = "Home";
        List<StatusItem> status = new List<StatusItem>();
        string statusState = "loading";        // loading, done, failed
        int okCount, totalCount, changedCount;
        bool busy;
        bool restoreOffered;
        bool buildingUi;
        readonly object statusLock = new object();

        // ------------------------------------------------------------------ shell
        const string ShellXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Windows 11 Optimizer' Width='1060' Height='720' MinWidth='900' MinHeight='600'
        Background='{DynamicResource Bg}' Foreground='{DynamicResource Ink}'
        FontFamily='Segoe UI Variable Text, Segoe UI, Leelawadee UI' FontSize='14'
        UseLayoutRounding='True' SnapsToDevicePixels='True' WindowStartupLocation='CenterScreen'>
  <Grid Background='{DynamicResource Bg}'>
    <Grid.ColumnDefinitions><ColumnDefinition Width='236'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions>
    <Border Background='{DynamicResource Surface}' BorderBrush='{DynamicResource Line}' BorderThickness='0,0,1,0'>
      <DockPanel Margin='16,22,16,16'>
        <StackPanel DockPanel.Dock='Top' Orientation='Horizontal' Margin='6,0,0,26'>
          <Border Width='32' Height='32' CornerRadius='9' Background='{DynamicResource Accent}'>
            <Path Data='M 9,16.5 L 14,21 L 23,11' Stroke='White' StrokeThickness='2.6' StrokeStartLineCap='Round' StrokeEndLineCap='Round' StrokeLineJoin='Round'/>
          </Border>
          <StackPanel Margin='12,0,0,0' VerticalAlignment='Center'>
            <TextBlock Text='Windows 11' FontSize='12' Foreground='{DynamicResource Muted}'/>
            <TextBlock Text='Optimizer' FontSize='17' FontWeight='SemiBold' Margin='0,-2,0,0'/>
          </StackPanel>
        </StackPanel>
        <TextBlock x:Name='VersionText' DockPanel.Dock='Bottom' Margin='8,0,0,0' FontSize='12' Foreground='{DynamicResource Muted}'/>
        <StackPanel x:Name='LangPanel' DockPanel.Dock='Bottom' Orientation='Horizontal' Margin='6,0,0,14' KeyboardNavigation.TabIndex='1' KeyboardNavigation.DirectionalNavigation='None'/>
        <StackPanel x:Name='Nav' KeyboardNavigation.TabIndex='0' KeyboardNavigation.DirectionalNavigation='None'/>
      </DockPanel>
    </Border>
    <Grid Grid.Column='1' KeyboardNavigation.TabIndex='2'>
      <Grid.RowDefinitions><RowDefinition Height='*'/><RowDefinition Height='Auto'/></Grid.RowDefinitions>
      <ScrollViewer x:Name='PageScroll' VerticalScrollBarVisibility='Auto' Focusable='False'>
        <ContentControl x:Name='PageHost' Margin='40,34,40,34' Focusable='False'/>
      </ScrollViewer>
      <Border x:Name='Activity' Grid.Row='1' Visibility='Collapsed' Background='{DynamicResource Surface}' BorderBrush='{DynamicResource Line}' BorderThickness='0,1,0,0'>
        <Grid Margin='24,14,24,16'>
          <Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/><RowDefinition Height='*'/></Grid.RowDefinitions>
          <DockPanel>
            <Button x:Name='ActivityClose' DockPanel.Dock='Right' Content='Close' Style='{StaticResource GhostButton}' Padding='14,6' FontSize='12'/>
            <Button x:Name='ActivityCopy' DockPanel.Dock='Right' Content='Copy' Style='{StaticResource GhostButton}' Padding='14,6' FontSize='12' Margin='0,0,8,0'/>
            <TextBlock x:Name='ActivityTitle' FontWeight='SemiBold' VerticalAlignment='Center'/>
          </DockPanel>
          <ProgressBar x:Name='ActivityBar' Grid.Row='1' Height='3' Margin='0,10,0,10' IsIndeterminate='True' Foreground='{DynamicResource Accent}' Background='{DynamicResource Line}' BorderThickness='0'/>
          <TextBox x:Name='ActivityLog' Grid.Row='2' Height='190' IsReadOnly='True' FontFamily='Consolas' FontSize='12' Background='{DynamicResource LogBg}' Foreground='#D6DCE8' BorderThickness='0' Padding='12' VerticalScrollBarVisibility='Auto' HorizontalScrollBarVisibility='Auto' TextWrapping='NoWrap'/>
        </Grid>
      </Border>
    </Grid>
  </Grid>
</Window>";

        public MainWindow(bool demo)
        {
            Demo = demo;
            Win = (Window)XamlReader.Parse(ShellXaml);
            Rect work = SystemParameters.WorkArea;
            Win.Width = Math.Min(Win.Width, work.Width - 30);
            Win.Height = Math.Min(Win.Height, work.Height - 30);
            Win.MinWidth = Math.Min(Win.MinWidth, Win.Width);
            Win.MinHeight = Math.Min(Win.MinHeight, Win.Height);
            pageHost = (ContentControl)Win.FindName("PageHost");
            pageScroll = (ScrollViewer)Win.FindName("PageScroll");
            activity = (Border)Win.FindName("Activity");
            activityTitle = (TextBlock)Win.FindName("ActivityTitle");
            activityLog = (TextBox)Win.FindName("ActivityLog");
            activityBar = (ProgressBar)Win.FindName("ActivityBar");
            StackPanel nav = (StackPanel)Win.FindName("Nav");
            versionText = (TextBlock)Win.FindName("VersionText");
            closeButton = (Button)Win.FindName("ActivityClose");
            copyButton = (Button)Win.FindName("ActivityCopy");

            navButtons = new RadioButton[navNames.Length];
            for (int i = 0; i < navNames.Length; i++)
            {
                RadioButton rb = new RadioButton();
                rb.Content = Loc.T(navNames[i]);
                rb.GroupName = "nav";
                rb.Style = (Style)Application.Current.FindResource("NavButton");
                string name = navNames[i];
                rb.Checked += delegate(object s, RoutedEventArgs e) { if (!buildingUi) ShowPage(name); };
                nav.Children.Add(rb);
                navButtons[i] = rb;
            }
            nav.PreviewKeyDown += delegate(object s, KeyEventArgs e)
            {
                int step = (e.Key == Key.Down) ? 1 : (e.Key == Key.Up ? -1 : 0);
                if (step == 0) return;
                int cur = Array.IndexOf(navNames, currentPage);
                int next = Math.Max(0, Math.Min(navNames.Length - 1, cur + step));
                e.Handled = true;
                if (next != cur) ShowPage(navNames[next]);
                navButtons[next].Focus();
            };
            closeButton.Click += delegate { activity.Visibility = Visibility.Collapsed; };
            copyButton.Click += delegate { try { Clipboard.SetText(activityLog.Text); } catch { } };

            StackPanel langPanel = (StackPanel)Win.FindName("LangPanel");
            string[] langCodes = new string[] { "en", "th" };
            string[] langNames = new string[] { "English", "ไทย" };
            for (int i = 0; i < 2; i++)
            {
                RadioButton lb = new RadioButton();
                lb.Content = langNames[i];
                lb.GroupName = "lang";
                lb.Style = S("LangStyle");
                lb.IsChecked = (Loc.Lang == langCodes[i]);
                string code = langCodes[i];
                lb.Checked += delegate(object s, RoutedEventArgs e) { if (!buildingUi && Loc.Lang != code) { Loc.Lang = code; Loc.Save(); ApplyLanguage(); } };
                langPanel.Children.Add(lb);
            }
            langPanel.PreviewKeyDown += delegate(object s, KeyEventArgs e)
            {
                int step = (e.Key == Key.Right) ? 1 : (e.Key == Key.Left ? -1 : 0);
                if (step == 0) return;
                e.Handled = true;
                int want = (Loc.Lang == "th") ? 1 : 0;
                want = Math.Max(0, Math.Min(1, want + step));
                ((RadioButton)langPanel.Children[want]).IsChecked = true;
                ((RadioButton)langPanel.Children[want]).Focus();
            };
            ApplyLanguage();

            if (Demo) MakeDemoStatus();
            ShowPage("Home");
            if (!Demo) RefreshStatus();
        }

        // the window texts in the chosen language
        void ApplyLanguage()
        {
            for (int i = 0; i < navNames.Length; i++) navButtons[i].Content = Loc.T(navNames[i]);
            versionText.Text = Loc.T("Version") + " " + Runner.Version();
            closeButton.Content = Loc.T("Close");
            copyButton.Content = Loc.T("Copy");
            Rebuild();
        }

        // ------------------------------------------------------------------ small building blocks
        static Style S(string key) { return (Style)Application.Current.FindResource(key); }

        static TextBlock Txt(string text, double size, FontWeight weight, string brush)
        {
            TextBlock t = new TextBlock();
            t.Text = Loc.T(text);
            t.FontSize = size;
            t.FontWeight = weight;
            t.Foreground = Theme.Get(brush);
            t.TextWrapping = TextWrapping.Wrap;
            return t;
        }

        static Button Btn(string text, bool primary, RoutedEventHandler click)
        {
            Button b = new Button();
            b.Content = Loc.T(text);
            b.Style = S(primary ? "PrimaryButton" : "GhostButton");
            b.Click += click;
            return b;
        }

        static Border Card(UIElement child, double bottom)
        {
            Border b = new Border();
            b.Style = S("CardStyle");
            b.Child = child;
            b.Margin = new Thickness(0, 0, 0, bottom);
            return b;
        }

        static StackPanel Header(string title, string sub)
        {
            StackPanel sp = new StackPanel();
            sp.Margin = new Thickness(0, 0, 0, 24);
            sp.Children.Add(Txt(title, 28, FontWeights.SemiBold, "Ink"));
            TextBlock s = Txt(sub, 14, FontWeights.Normal, "Muted");
            s.Margin = new Thickness(0, 6, 0, 0);
            sp.Children.Add(s);
            return sp;
        }

        void Dispatch(Action a) { Win.Dispatcher.BeginInvoke(DispatcherPriority.Normal, a); }

        // A small dialog in the same style. Returns the index of the button that was pressed, or -1.
        public int Ask(string title, string text, params string[] buttons)
        {
            Window w = new Window();
            w.Owner = Win;
            w.Title = Loc.T(title);
            w.SizeToContent = SizeToContent.Height;
            w.Width = 460;
            w.ResizeMode = ResizeMode.NoResize;
            w.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            w.Background = Theme.Get("Surface");
            w.Foreground = Theme.Get("Ink");
            w.FontFamily = Win.FontFamily;
            w.ShowInTaskbar = false;
            StackPanel sp = new StackPanel();
            sp.Margin = new Thickness(26, 24, 26, 22);
            sp.Children.Add(Txt(title, 18, FontWeights.SemiBold, "Ink"));
            TextBlock body = Txt(text, 14, FontWeights.Normal, "Muted");
            body.Margin = new Thickness(0, 10, 0, 22);
            sp.Children.Add(body);
            StackPanel row = new StackPanel();
            row.Orientation = Orientation.Horizontal;
            row.HorizontalAlignment = HorizontalAlignment.Right;
            int result = -1;
            for (int i = 0; i < buttons.Length; i++)
            {
                int idx = i;
                Button b = Btn(buttons[i], i == 0, delegate { result = idx; w.Close(); });
                b.Margin = new Thickness(8, 0, 0, 0);
                if (i == 0) b.IsDefault = true;
                row.Children.Add(b);
            }
            sp.Children.Add(row);
            w.Content = sp;
            w.KeyDown += delegate(object s, KeyEventArgs e) { if (e.Key == Key.Escape) w.Close(); };
            if (pictureTarget != null) { Picture(w, pictureTarget); pictureTarget = null; return 0; }
            w.ShowDialog();
            return result;
        }

        // ------------------------------------------------------------------ navigation and pages
        void ShowPage(string name)
        {
            currentPage = name;
            buildingUi = true;
            for (int i = 0; i < navNames.Length; i++) navButtons[i].IsChecked = (navNames[i] == name);
            buildingUi = false;
            UIElement page;
            if (name == "Tweaks") page = TweaksPage();
            else if (name == "Tools") page = ToolsPage();
            else if (name == "Undo") page = UndoPage();
            else if (name == "About") page = AboutPage();
            else page = HomePage();
            pageHost.Content = page;
            pageScroll.ScrollToTop();
        }

        public void Navigate(string name) { ShowPage(name); }

        // pictures of the two dialogs (the --shots mode)
        public void PictureEasy(string path) { pictureTarget = path; ShowEasyDialog(); }
        public void PictureAsk(string path) { pictureTarget = path; Ask("Make a restore point first?", "A restore point lets you go back with one click if you do not like a change. It takes a minute or two.", "Create restore point", "Skip"); }
        void Picture(Window w, string path) { w.Show(); Program.Idle(w); Program.Save(w, path); w.Close(); }
        // the same page again (new status, other language), at the same place: flipping a switch low on the page must not throw you to the top
        void Rebuild()
        {
            double offset = pageScroll.VerticalOffset;
            ShowPage(currentPage);
            if (offset > 0)
            {
                Win.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(delegate { pageScroll.ScrollToVerticalOffset(offset); }));
            }
        }

        UIElement Wrap(UIElement content)
        {
            StackPanel sp = new StackPanel();
            sp.MaxWidth = 900;
            sp.HorizontalAlignment = HorizontalAlignment.Left;
            sp.Children.Add(content);
            return sp;
        }

        // ---- Home
        UIElement HomePage()
        {
            StackPanel page = new StackPanel();
            page.Children.Add(Header("Windows 11 Optimizer", "Safe, reversible tuning for gaming PCs. Every change can be undone."));

            // Easy Setup
            StackPanel easy = new StackPanel();
            easy.Children.Add(Txt("Easy Setup", 20, FontWeights.SemiBold, "Ink"));
            TextBlock d = Txt("One guided run does everything in the right order: a restore point, drivers, Windows Update, the safe speed settings and a short summary. It takes 20 to 40 minutes, mostly waiting, and asks only what it must.", 14, FontWeights.Normal, "Muted");
            d.Margin = new Thickness(0, 8, 0, 18);
            easy.Children.Add(d);
            StackPanel row = new StackPanel();
            row.Orientation = Orientation.Horizontal;
            row.Children.Add(Btn("Start Easy Setup", true, delegate { ShowEasyDialog(); }));
            Button how = Btn("What does it do?", false, delegate { OpenManual(); });
            how.Margin = new Thickness(10, 0, 0, 0);
            row.Children.Add(how);
            easy.Children.Add(row);
            Border hero = Card(easy, 16);
            hero.Padding = new Thickness(28);
            hero.BorderBrush = Theme.Get("Accent");
            page.Children.Add(hero);

            // Status
            Grid g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            StackPanel left = new StackPanel();
            left.Children.Add(Txt("Settings in place", 13, FontWeights.SemiBold, "Muted"));
            string big; string note;
            if (statusState == "loading") { big = "Checking..."; note = "Reading your settings. Nothing is changed."; }
            else if (statusState == "failed") { big = "Not available"; note = "The check could not run. Press Check again."; }
            else
            {
                big = okCount + " " + Loc.T("of") + " " + totalCount;
                if (changedCount > 0) note = (changedCount == 1) ? Loc.T("1 setting was set earlier and Windows changed it back.") : String.Format(Loc.T("{0} settings were set earlier and Windows changed them back."), changedCount);
                else if (okCount >= totalCount && totalCount > 0) note = "Everything this tool manages is in place.";
                else note = "Easy Setup or the Tweaks page puts the rest in place.";
            }
            TextBlock bigText = Txt(big, 30, FontWeights.SemiBold, "Ink");
            bigText.Margin = new Thickness(0, 6, 0, 2);
            left.Children.Add(bigText);
            left.Children.Add(Txt(note, 13, FontWeights.Normal, "Muted"));
            Grid bar = new Grid();
            bar.Height = 6;
            bar.Margin = new Thickness(0, 14, 0, 0);
            bar.MaxWidth = 420;
            bar.HorizontalAlignment = HorizontalAlignment.Left;
            bar.Width = 420;
            Border track = new Border { CornerRadius = new CornerRadius(3), Background = Theme.Get("Line") };
            bar.Children.Add(track);
            double ratio = (totalCount > 0 && statusState == "done") ? (double)okCount / totalCount : 0;
            Border fill = new Border { CornerRadius = new CornerRadius(3), Background = Theme.Get("Accent"), HorizontalAlignment = HorizontalAlignment.Left, Width = 420 * ratio };
            bar.Children.Add(fill);
            left.Children.Add(bar);
            g.Children.Add(left);
            StackPanel right = new StackPanel();
            right.VerticalAlignment = VerticalAlignment.Center;
            Button again = Btn("Check again", false, delegate { RefreshStatus(); });
            right.Children.Add(again);
            if (changedCount > 0)
            {
                Button fix = Btn("Fix them", true, delegate { Runner.OpenConsole("/d /s /c " + Runner.Bat(@"More Tools\3_Check_Status (Run as Administrator).bat", "")); });
                fix.Margin = new Thickness(0, 8, 0, 0);
                right.Children.Add(fix);
            }
            Grid.SetColumn(right, 1);
            g.Children.Add(right);
            page.Children.Add(Card(g, 16));

            // three quick cards
            UniformGrid3 quick = new UniformGrid3();
            quick.Add(QuickCard("Restore point", "Save a point you can go back to. Do this before you change anything.", "Create now", delegate { CreateRestorePoint(null); }));
            quick.Add(QuickCard("Undo", "Turn one tweak off again, or roll the whole PC back.", "Open undo", delegate { ShowPage("Undo"); }));
            quick.Add(QuickCard("Updates", "See if there is a newer version of this tool.", "Check", delegate { CheckForUpdates(); }));
            page.Children.Add(quick.Element);
            return Wrap(page);
        }

        class UniformGrid3
        {
            public Grid Element = new Grid();
            int n;
            public void Add(UIElement e)
            {
                if (n > 0) Element.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(16) });
                Element.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                Grid.SetColumn(e, Element.ColumnDefinitions.Count - 1);
                Element.Children.Add(e);
                n++;
            }
        }

        UIElement QuickCard(string title, string text, string button, RoutedEventHandler click)
        {
            StackPanel sp = new StackPanel();
            sp.Children.Add(Txt(title, 15, FontWeights.SemiBold, "Ink"));
            TextBlock t = Txt(text, 13, FontWeights.Normal, "Muted");
            t.Margin = new Thickness(0, 6, 0, 14);
            t.MinHeight = 54;
            sp.Children.Add(t);
            Button b = Btn(button, false, click);
            b.HorizontalAlignment = HorizontalAlignment.Left;
            sp.Children.Add(b);
            return Card(sp, 0);
        }

        // ---- Tweaks
        UIElement TweaksPage()
        {
            StackPanel page = new StackPanel();
            page.Children.Add(Header("Tweaks", "Each switch puts one setting in place or takes it back. A restore point is offered before the first change."));

            DockPanel actions = new DockPanel();
            actions.Margin = new Thickness(0, 0, 0, 18);
            Button refresh = Btn("Refresh", false, delegate { RefreshStatus(); });
            DockPanel.SetDock(refresh, Dock.Right);
            actions.Children.Add(refresh);
            Button rec = Btn("Turn on all recommended", true, delegate { ApplyRecommended(); });
            rec.HorizontalAlignment = HorizontalAlignment.Left;
            actions.Children.Add(rec);
            page.Children.Add(actions);

            string[] groups = new string[] { "Recommended", "Optional", "Power" };
            string[] groupText = new string[] { "Recommended: safe for everyone", "Optional: you decide", "Power: for desktops" };
            for (int gi = 0; gi < groups.Length; gi++)
            {
                TextBlock gt = Txt(groupText[gi], 13, FontWeights.SemiBold, "Muted");
                gt.Margin = new Thickness(4, 4, 0, 8);
                page.Children.Add(gt);
                StackPanel list = new StackPanel();
                bool first = true;
                foreach (Tweak t in Catalog.All)
                {
                    if (t.Group != groups[gi]) continue;
                    if (!first)
                    {
                        Border sep = new Border { Height = 1, Background = Theme.Get("Line"), Margin = new Thickness(0, 2, 0, 2) };
                        list.Children.Add(sep);
                    }
                    first = false;
                    list.Children.Add(TweakRow(t));
                }
                Border card = Card(list, 20);
                card.Padding = new Thickness(20, 10, 20, 10);
                page.Children.Add(card);
            }
            return Wrap(page);
        }

        UIElement TweakRow(Tweak t)
        {
            Grid g = new Grid();
            g.Margin = new Thickness(0, 10, 0, 10);
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            StackPanel text = new StackPanel();
            text.Children.Add(Txt(t.Id + "   " + Loc.T(t.Title), 14, FontWeights.SemiBold, "Ink"));
            TextBlock d = Txt(t.Desc, 13, FontWeights.Normal, "Muted");
            d.Margin = new Thickness(0, 2, 24, 0);
            text.Children.Add(d);
            g.Children.Add(text);

            string label; string brush;
            if (statusState == "loading") { label = "..."; brush = "Muted"; }
            else if (t.Status == "OK") { label = "On"; brush = "Good"; }
            else if (t.Status == "CHANGED") { label = "Changed by Windows"; brush = "Warn"; }
            else { label = "Off"; brush = "Muted"; }
            TextBlock st = Txt(label, 12, FontWeights.SemiBold, brush);
            st.VerticalAlignment = VerticalAlignment.Center;
            st.Margin = new Thickness(0, 0, 14, 0);
            Grid.SetColumn(st, 1);
            g.Children.Add(st);

            CheckBox sw = new CheckBox();
            sw.Style = S("SwitchStyle");
            sw.VerticalAlignment = VerticalAlignment.Center;
            sw.IsChecked = t.IsOn;
            sw.IsEnabled = (statusState == "done");
            sw.SetValue(System.Windows.Automation.AutomationProperties.NameProperty, t.Title);
            Tweak tt = t;
            sw.Click += delegate { OnSwitch(tt, sw); };
            Grid.SetColumn(sw, 2);
            g.Children.Add(sw);
            return g;
        }

        // ---- Tools
        class ToolDef
        {
            public string Title, Text, Button; public bool InApp; public Action Run;
            public ToolDef(string title, string text, bool inApp, Action run) { Title = title; Text = text; InApp = inApp; Run = run; Button = inApp ? "Run here" : "Open"; }
        }

        UIElement ToolsPage()
        {
            StackPanel page = new StackPanel();
            page.Children.Add(Header("Tools", "Look at your PC, check it, and keep it tidy. Most of these only read; none of them delete anything without asking."));
            List<ToolDef> tools = new List<ToolDef>();
            tools.Add(new ToolDef("Check status", "See which settings Windows changed back, and fix them.", false, delegate { Runner.OpenConsole("/d /s /c " + Runner.Bat(@"More Tools\3_Check_Status (Run as Administrator).bat", "")); }));
            tools.Add(new ToolDef("PC specs", "Your PC on one page, in plain words. Your name and serial numbers are left out.", true, delegate { RunScript("PC specs", @"tools\PC_Specs.ps1", "-Root \"" + Runner.Root + "\""); }));
            tools.Add(new ToolDef("PC health", "Crashes, drive health, screen refresh rate, memory speed and cable speed.", true, delegate { RunScript("PC health", @"tools\PC_Health.ps1", "-Root \"" + Runner.Root + "\""); }));
            tools.Add(new ToolDef("System report", "What uses your processor and memory, and what starts with Windows.", true, delegate { RunScript("System report", @"tools\System_Report.ps1", ""); }));
            tools.Add(new ToolDef("Network test", "Ping, jitter, packet loss and DNS speed. You choose what to test.", false, delegate { Runner.OpenConsole("/d /s /c " + Runner.Bat(@"More Tools\4_Network_Test.bat", "")); }));
            tools.Add(new ToolDef("Drivers", "Find missing or old drivers. Installs only what you choose.", false, delegate { Runner.OpenConsole("/d /s /c " + Runner.Bat(@"More Tools\7_Driver_Check (Run as Administrator).bat", "")); }));
            tools.Add(new ToolDef("Clean up", "Old reports and backups. You choose what goes.", false, delegate { Runner.OpenConsole("/d /s /c " + Runner.Bat(@"More Tools\L_Clean_Up.bat", "")); }));
            tools.Add(new ToolDef("Support bundle", "One file that you can attach to a problem report. Private details are replaced.", true, delegate { RunScript("Support bundle", @"tools\Support_Bundle.ps1", "-Root \"" + Runner.Root + "\""); }));
            tools.Add(new ToolDef("Classic menu", "The original text menu with every option.", false, delegate { Runner.OpenConsole("/d /s /c " + Runner.Bat(MasterBat, "")); }));

            WrapPanel wp = new WrapPanel();
            foreach (ToolDef td in tools)
            {
                StackPanel sp = new StackPanel();
                sp.Children.Add(Txt(td.Title, 15, FontWeights.SemiBold, "Ink"));
                TextBlock t = Txt(td.Text, 13, FontWeights.Normal, "Muted");
                t.Margin = new Thickness(0, 6, 0, 14);
                t.MinHeight = 54;
                sp.Children.Add(t);
                DockPanel bottom = new DockPanel();
                ToolDef cap = td;
                Button b = Btn(td.Button, false, delegate { if (!Demo) cap.Run(); });
                DockPanel.SetDock(b, Dock.Left);
                bottom.Children.Add(b);
                TextBlock hint = Txt(td.InApp ? "Shows the result below" : "Opens a window", 12, FontWeights.Normal, "Muted");
                hint.VerticalAlignment = VerticalAlignment.Center;
                hint.Margin = new Thickness(12, 0, 0, 0);
                bottom.Children.Add(hint);
                sp.Children.Add(bottom);
                Border c = Card(sp, 14);
                c.Width = 270;
                c.Margin = new Thickness(0, 0, 14, 14);
                wp.Children.Add(c);
            }
            page.Children.Add(wp);
            return Wrap(page);
        }

        // ---- Undo
        UIElement UndoPage()
        {
            StackPanel page = new StackPanel();
            page.Children.Add(Header("Undo", "Everything this tool does can be taken back. Pick the smallest step that fixes your problem."));

            StackPanel one = new StackPanel();
            one.Children.Add(Txt("One tweak", 17, FontWeights.SemiBold, "Ink"));
            TextBlock d1 = Txt("Mouse feels odd? Turn that one switch off on the Tweaks page. The Windows default comes back at once.", 14, FontWeights.Normal, "Muted");
            d1.Margin = new Thickness(0, 6, 0, 14);
            one.Children.Add(d1);
            Button b1 = Btn("Open Tweaks", false, delegate { ShowPage("Tweaks"); });
            b1.HorizontalAlignment = HorizontalAlignment.Left;
            one.Children.Add(b1);
            page.Children.Add(Card(one, 14));

            StackPanel all = new StackPanel();
            all.Children.Add(Txt("The whole PC", 17, FontWeights.SemiBold, "Ink"));
            TextBlock d2 = Txt("Goes back to the restore point named Before_PC_Optimizer with Windows System Restore. Programs you installed after that point are removed, your files stay. The PC restarts.", 14, FontWeights.Normal, "Muted");
            d2.Margin = new Thickness(0, 6, 0, 14);
            all.Children.Add(d2);
            Button b2 = Btn("Roll back the PC", false, delegate { RollBack(); });
            b2.HorizontalAlignment = HorizontalAlignment.Left;
            all.Children.Add(b2);
            page.Children.Add(Card(all, 14));

            StackPanel files = new StackPanel();
            files.Children.Add(Txt("Backups and reports", 17, FontWeights.SemiBold, "Ink"));
            TextBlock d3 = Txt("Before a setting is changed, its old value is saved in the Backup folder. Double-click a file there to restore that value by hand.", 14, FontWeights.Normal, "Muted");
            d3.Margin = new Thickness(0, 6, 0, 14);
            files.Children.Add(d3);
            StackPanel fr = new StackPanel();
            fr.Orientation = Orientation.Horizontal;
            fr.Children.Add(Btn("Open Backup folder", false, delegate { OpenFolder("Backup"); }));
            Button lg = Btn("Open Logs folder", false, delegate { OpenFolder("Logs"); });
            lg.Margin = new Thickness(10, 0, 0, 0);
            fr.Children.Add(lg);
            files.Children.Add(fr);
            page.Children.Add(Card(files, 14));
            return Wrap(page);
        }

        // ---- About
        UIElement AboutPage()
        {
            StackPanel page = new StackPanel();
            page.Children.Add(Header("About", Loc.T("Windows 11 Optimizer, version") + " " + Runner.Version()));

            StackPanel a = new StackPanel();
            a.Children.Add(Txt("Open source, free, no installer", 17, FontWeights.SemiBold, "Ink"));
            TextBlock t = Txt("This window only starts the tool's own scripts, which are plain text files in the folders next to it. Nothing is sent anywhere except the update check to github.com and the driver search to Microsoft. MIT licence.", 14, FontWeights.Normal, "Muted");
            t.Margin = new Thickness(0, 6, 0, 16);
            a.Children.Add(t);
            StackPanel r = new StackPanel();
            r.Orientation = Orientation.Horizontal;
            r.Children.Add(Btn("Manual (English)", false, delegate { OpenManual(); }));
            Button th = Btn("คู่มือภาษาไทย", false, delegate { OpenManualThai(); });
            th.Margin = new Thickness(10, 0, 0, 0);
            r.Children.Add(th);
            Button gh = Btn("GitHub", false, delegate { Runner.Open("https://github.com/Kensukeimagery/win11-optimizer"); });
            gh.Margin = new Thickness(10, 0, 0, 0);
            r.Children.Add(gh);
            Button up = Btn("Check for updates", false, delegate { CheckForUpdates(); });
            up.Margin = new Thickness(10, 0, 0, 0);
            r.Children.Add(up);
            a.Children.Add(r);
            page.Children.Add(Card(a, 14));

            StackPanel w = new StackPanel();
            w.Children.Add(Txt("Use at your own risk", 17, FontWeights.SemiBold, "Ink"));
            TextBlock wt = Txt("The tweaks change Windows settings. A restore point is offered first and every change has an undo. Built for desktops with Windows 11; on a laptop the heat and battery tweaks are left out of Easy Setup. Gains are small and depend on the game.", 14, FontWeights.Normal, "Muted");
            wt.Margin = new Thickness(0, 6, 0, 0);
            w.Children.Add(wt);
            page.Children.Add(Card(w, 14));
            return Wrap(page);
        }

        // ------------------------------------------------------------------ actions
        void OpenManual() { string f = Runner.Find("docs", "Manual_EN_*.pdf"); if (f != null) Runner.Open(f); else Runner.Open("https://github.com/Kensukeimagery/win11-optimizer#readme"); }
        void OpenManualThai() { string f = Runner.Find("docs", "Manual_TH_*.pdf"); if (f != null) Runner.Open(f); else Runner.Open("https://github.com/Kensukeimagery/win11-optimizer/blob/main/README.th.md"); }

        void OpenFolder(string name)
        {
            string p = Runner.Path1(name);
            try { Directory.CreateDirectory(p); } catch { }
            Runner.Open(p);
        }

        void RollBack()
        {
            if (Ask("Roll back the whole PC?", "This opens Windows System Restore and restarts the PC. Save your work first.", "Continue", "Cancel") != 0) return;
            Runner.OpenConsole("/d /s /c " + Runner.Bat(RevertBat, ""));
        }

        void CheckForUpdates()
        {
            if (Ask("Check for a new version?", "This window closes so that the update can replace it. If there is a newer version you are asked before anything is installed. Open this window again afterwards.", "Check", "Cancel") != 0) return;
            Runner.OpenConsole("/d /s /c " + Runner.Bat(@"More Tools\6_Check_For_Updates.bat", ""));
            Win.Close();
        }

        void RunScript(string title, string script, string args)
        {
            RunInApp(title, Runner.PowerShellExe, Runner.ScriptArgs(script, args), null);
        }

        void CreateRestorePoint(Action<int> then)
        {
            RunInApp("Making the restore point (1 to 5 minutes)", Runner.PowerShellExe, Runner.ScriptArgs(@"tools\Create_Restore_Point.ps1", "-TimeoutSeconds 600 -Description Before_PC_Optimizer"), delegate(int code)
            {
                restoreOffered = true;
                if (code == 0) AppendLog(Loc.T("[OK] Restore point made: Before_PC_Optimizer"));
                else AppendLog(Loc.T("[!] The restore point could not be made. Turn on System Protection for drive C: in Windows if you want one."));
                if (then != null) then(code);
            });
        }

        void ApplyRecommended()
        {
            if (busy) return;
            // one run through the tool's own recommended set
            if (!restoreOffered)
            {
                restoreOffered = true;
                int r = Ask("Make a restore point first?", "A restore point lets you go back with one click. It takes a minute or two.", "Create restore point", "Skip");
                if (r == 0) { CreateRestorePoint(delegate(int c) { RunRecommended(); }); return; }
            }
            RunRecommended();
        }

        void RunRecommended()
        {
            RunInApp("Turning on the recommended tweaks", "cmd.exe", "/d /s /c " + Runner.Bat(MasterBat, "/easy safe"), delegate(int code) { RefreshStatus(); });
        }

        void OnSwitch(Tweak t, CheckBox sw)
        {
            if (Demo) return;
            bool wantOn = sw.IsChecked == true;
            if (busy) { sw.IsChecked = !wantOn; Ask("Please wait", "Another task is still running. Try again when it is finished.", "OK"); return; }
            if (wantOn && t.Caution)
            {
                if (Ask("Turn off Memory Integrity?", Loc.T(t.Desc) + "\n\n" + Loc.T("Only do this on a PC you trust."), "Turn it off", "Cancel") != 0) { sw.IsChecked = false; return; }
            }
            if (!restoreOffered)
            {
                restoreOffered = true;
                int r = Ask("Make a restore point first?", "A restore point lets you go back with one click if you do not like a change. It takes a minute or two.", "Create restore point", "Skip");
                if (r == 0) { CreateRestorePoint(delegate(int c) { SetTweak(t, wantOn); }); return; }
            }
            SetTweak(t, wantOn);
        }

        void SetTweak(Tweak t, bool on)
        {
            string verb = on ? "/apply " : "/revert ";
            RunInApp(Loc.T(on ? "Turning on" : "Turning off") + " " + Loc.T(t.Title), "cmd.exe", "/d /s /c " + Runner.Bat(MasterBat, verb + t.Id), delegate(int code) { RefreshStatus(); });
        }

        // ---- Easy Setup: the questions here, the guided run in its own console window (it needs your answers, for example for Windows Update)
        void ShowEasyDialog()
        {
            Window w = new Window();
            w.Owner = Win;
            w.Title = "Easy Setup";
            w.SizeToContent = SizeToContent.Height;
            w.Width = 520;
            w.ResizeMode = ResizeMode.NoResize;
            w.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            w.Background = Theme.Get("Surface");
            w.Foreground = Theme.Get("Ink");
            w.FontFamily = Win.FontFamily;
            w.ShowInTaskbar = false;

            StackPanel sp = new StackPanel();
            sp.Margin = new Thickness(28, 26, 28, 24);
            sp.Children.Add(Txt("How do you use this PC?", 20, FontWeights.SemiBold, "Ink"));
            TextBlock sub = Txt("This only decides which tweaks are added. You can change any of them later.", 14, FontWeights.Normal, "Muted");
            sub.Margin = new Thickness(0, 6, 0, 18);
            sp.Children.Add(sub);

            RadioButton rbSafe = Choice("Everyday", "The safe settings only. Good for every PC.", true);
            RadioButton rbGames = Choice("Gaming", "Adds mouse, keyboard, timer and CPU boost.", false);
            RadioButton rbMax = Choice("Gaming, maximum", "Every optional tweak at once. The effect on FPS is small and depends on the game.", false);
            sp.Children.Add(rbSafe);
            sp.Children.Add(rbGames);
            sp.Children.Add(rbMax);

            StackPanel mi = new StackPanel();
            mi.Margin = new Thickness(4, 0, 0, 10);
            mi.Visibility = Visibility.Collapsed;
            CheckBox cb = new CheckBox();
            cb.Content = Loc.T("Also turn off Memory Integrity (lowers protection)");
            cb.Foreground = Theme.Get("Ink");
            cb.Margin = new Thickness(0, 0, 0, 8);
            mi.Children.Add(cb);
            TextBox yes = new TextBox();
            yes.Width = 120;
            yes.HorizontalAlignment = HorizontalAlignment.Left;
            yes.Padding = new Thickness(8, 5, 8, 5);
            yes.IsEnabled = false;
            yes.ToolTip = Loc.T("Type YES to confirm");
            TextBlock yesNote = Txt("Type YES to confirm", 12, FontWeights.Normal, "Muted");
            yesNote.Margin = new Thickness(0, 4, 0, 0);
            mi.Children.Add(yes);
            mi.Children.Add(yesNote);
            sp.Children.Add(mi);
            cb.Click += delegate { yes.IsEnabled = cb.IsChecked == true; if (!yes.IsEnabled) yes.Text = ""; };
            rbMax.Checked += delegate { mi.Visibility = Visibility.Visible; };
            rbMax.Unchecked += delegate { mi.Visibility = Visibility.Collapsed; cb.IsChecked = false; yes.IsEnabled = false; yes.Text = ""; };

            StackPanel row = new StackPanel();
            row.Orientation = Orientation.Horizontal;
            row.HorizontalAlignment = HorizontalAlignment.Right;
            row.Margin = new Thickness(0, 12, 0, 0);
            Button cancel = Btn("Cancel", false, delegate { w.Close(); });
            Button start = Btn("Start", true, delegate
            {
                string mode = "safe";
                if (rbGames.IsChecked == true) mode = "games";
                if (rbMax.IsChecked == true) mode = (cb.IsChecked == true) ? "max13" : "max";
                if (mode == "max13" && yes.Text.Trim() != "YES") { Ask("Type YES", "To turn off Memory Integrity, type YES in the box.", "OK"); return; }
                w.Close();
                StartEasy(mode);
            });
            start.Margin = new Thickness(10, 0, 0, 0);
            start.IsDefault = true;
            row.Children.Add(cancel);
            row.Children.Add(start);
            sp.Children.Add(row);
            w.Content = sp;
            w.KeyDown += delegate(object s, KeyEventArgs e) { if (e.Key == Key.Escape) w.Close(); };
            if (pictureTarget != null) { Picture(w, pictureTarget); pictureTarget = null; return; }
            w.ShowDialog();
        }

        static RadioButton Choice(string title, string text, bool on)
        {
            StackPanel sp = new StackPanel();
            sp.Children.Add(Txt(title, 15, FontWeights.SemiBold, "Ink"));
            TextBlock t = Txt(text, 13, FontWeights.Normal, "Muted");
            t.Margin = new Thickness(0, 2, 0, 0);
            sp.Children.Add(t);
            RadioButton rb = new RadioButton();
            rb.Style = S("ChoiceStyle");
            rb.GroupName = "easy";
            rb.Content = sp;
            rb.IsChecked = on;
            return rb;
        }

        void StartEasy(string mode)
        {
            string ps = "\"" + Runner.PowerShellExe + "\" -NoProfile -ExecutionPolicy Bypass -File \"" + Runner.Path1(@"tools\Easy_Setup.ps1") + "\" -Root \"" + Runner.Root + "\" -Mode " + mode;
            string cmd = "/d /s /c \"chcp 65001 >nul & color 0B & " + ps + " & echo. & pause\"";
            ShowActivityNote("Easy Setup is running in its own window. Answer its questions there. This window updates when it finishes.");
            Process p = Runner.OpenConsole(cmd);
            if (p != null)
            {
                p.EnableRaisingEvents = true;
                p.Exited += delegate { Dispatch(delegate { activity.Visibility = Visibility.Collapsed; RefreshStatus(); }); };
            }
        }

        // ------------------------------------------------------------------ the activity panel
        void ShowActivityNote(string text)
        {
            activity.Visibility = Visibility.Visible;
            activityTitle.Text = Loc.T(text);
            activityBar.Visibility = Visibility.Visible;
            activityLog.Text = "";
        }

        void AppendLog(string line)
        {
            activityLog.AppendText(line + "\r\n");
            activityLog.ScrollToEnd();
        }

        void RunInApp(string title, string file, string args, Action<int> done)
        {
            if (busy) { Ask("Please wait", "Another task is still running.", "OK"); return; }
            busy = true;
            activity.Visibility = Visibility.Visible;
            activityTitle.Text = Loc.T(title) + "...";
            activityBar.Visibility = Visibility.Visible;
            activityLog.Text = "";
            try
            {
                Runner.RunCaptured(file, args,
                    delegate(string line) { if (line.IndexOf("Input redirection is not supported", StringComparison.OrdinalIgnoreCase) < 0) Dispatch(delegate { AppendLog(line); }); },
                    delegate(int code)
                    {
                        Dispatch(delegate
                        {
                            busy = false;
                            activityBar.Visibility = Visibility.Collapsed;
                            activityTitle.Text = (code == 0) ? Loc.T("Finished:") + " " + Loc.T(title) : String.Format(Loc.T("Stopped with a problem (code {0}):"), code) + " " + Loc.T(title);
                            if (done != null) done(code);
                        });
                    });
            }
            catch (Exception ex)
            {
                busy = false;
                activityBar.Visibility = Visibility.Collapsed;
                activityTitle.Text = Loc.T("Could not start:") + " " + Loc.T(title);
                AppendLog(ex.Message);
            }
        }

        // ------------------------------------------------------------------ status
        void RefreshStatus()
        {
            if (Demo) return;
            statusState = "loading";
            Rebuild();
            List<string> lines = new List<string>();
            try
            {
                Runner.RunCaptured(Runner.PowerShellExe, Runner.ScriptArgs(@"tools\Gui_Status.ps1", "-Root \"" + Runner.Root + "\""),
                    delegate(string l) { lock (statusLock) { lines.Add(l); } },
                    delegate(int code)
                    {
                        List<string> copy;
                        lock (statusLock) { copy = new List<string>(lines); }
                        Dispatch(delegate { ApplyStatus(StatusReader.Parse(copy), code); });
                    });
            }
            catch { ApplyStatus(new List<StatusItem>(), -1); }
        }

        void ApplyStatus(List<StatusItem> items, int code)
        {
            status = items;
            if (items.Count == 0) { statusState = "failed"; Rebuild(); return; }
            foreach (Tweak t in Catalog.All)
            {
                t.Status = "UNKNOWN";
                foreach (StatusItem s in items) { if (s.Id == t.Id) { t.Status = s.Status; break; } }
            }
            StatusReader.Count(items, out okCount, out totalCount);
            changedCount = 0;
            foreach (StatusItem s in items) { if (s.Status == "CHANGED") changedCount++; }
            statusState = "done";
            Rebuild();
        }

        void MakeDemoStatus()
        {
            foreach (Tweak t in Catalog.All) { t.Status = "OK"; }
            Catalog.Find("09").Status = "NOT CHOSEN";
            Catalog.Find("12").Status = "NOT CHOSEN";
            Catalog.Find("13").Status = "NOT CHOSEN";
            Catalog.Find("06").Status = "CHANGED";
            okCount = 18; totalCount = 19; changedCount = 1;
            statusState = "done";
        }
    }
}
