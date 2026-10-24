using System;
using System.Collections.Generic;
using System.Globalization;
using Microsoft.Win32;

namespace Win11Optimizer
{
    // The window speaks English or Thai. The English text of the program is the key: Loc.T("English") gives the Thai text when Thai is on,
    // and the English text itself when there is no Thai for it. The choice is kept in HKCU\Software\PCOptimizer (AppLang).
    static class Loc
    {
        public static string Lang = "en";

        public static void Init()
        {
            string saved = null;
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Software\PCOptimizer"))
                {
                    if (k != null) saved = k.GetValue("AppLang") as string;
                }
            }
            catch { }
            if (saved == "th" || saved == "en") Lang = saved;
            else Lang = (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "th") ? "th" : "en";
        }

        public static void Save()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(@"Software\PCOptimizer"))
                {
                    if (k != null) k.SetValue("AppLang", Lang, RegistryValueKind.String);
                }
            }
            catch { }
        }

        public static string T(string en)
        {
            if (Lang != "th" || en == null) return en;
            string th;
            return Th.TryGetValue(en, out th) ? th : en;
        }

        // every English text of the window that has a Thai text
        public static readonly Dictionary<string, string> Th = new Dictionary<string, string>
        {
            // navigation
            { "Home", "หน้าหลัก" }, { "Tweaks", "การปรับแต่ง" }, { "Tools", "เครื่องมือ" }, { "Undo", "ย้อนกลับ" }, { "About", "เกี่ยวกับ" },
            { "Version", "เวอร์ชัน" },
            // home
            { "Safe, reversible tuning for gaming PCs. Every change can be undone.", "ปรับแต่งเครื่องเล่นเกมอย่างปลอดภัยและย้อนกลับได้ ทุกการเปลี่ยนแปลงยกเลิกได้" },
            { "Easy Setup", "Easy Setup" },
            { "One guided run does everything in the right order: a restore point, drivers, Windows Update, the safe speed settings and a short summary. It takes 20 to 40 minutes, mostly waiting, and asks only what it must.",
              "กดครั้งเดียวทำให้ครบตามลำดับที่ถูกต้อง: จุดกู้คืน ไดรเวอร์ Windows Update ค่าเพิ่มความเร็วที่ปลอดภัย และสรุปผลสั้นๆ ใช้เวลา 20 ถึง 40 นาที ส่วนใหญ่คือรอ และถามเฉพาะที่จำเป็น" },
            { "Start Easy Setup", "เริ่ม Easy Setup" },
            { "What does it do?", "ทำอะไรบ้าง?" },
            { "Settings in place", "การตั้งค่าที่อยู่ครบ" },
            { "Checking...", "กำลังตรวจ..." },
            { "Reading your settings. Nothing is changed.", "กำลังอ่านการตั้งค่าของคุณ ไม่มีอะไรถูกเปลี่ยน" },
            { "Not available", "ใช้ไม่ได้" },
            { "The check could not run. Press Check again.", "ตรวจไม่ได้ ลองกดตรวจอีกครั้ง" },
            { "of", "จาก" },
            { "1 setting was set earlier and Windows changed it back.", "มี 1 ค่าที่เคยตั้งไว้ แต่ Windows เปลี่ยนกลับ" },
            { "{0} settings were set earlier and Windows changed them back.", "มี {0} ค่าที่เคยตั้งไว้ แต่ Windows เปลี่ยนกลับ" },
            { "Everything this tool manages is in place.", "ทุกอย่างที่เครื่องมือนี้ดูแลอยู่ครบแล้ว" },
            { "Easy Setup or the Tweaks page puts the rest in place.", "Easy Setup หรือหน้าการปรับแต่งช่วยตั้งส่วนที่เหลือให้ได้" },
            { "Check again", "ตรวจอีกครั้ง" },
            { "Fix them", "แก้ให้" },
            { "Restore point", "จุดกู้คืน" },
            { "Save a point you can go back to. Do this before you change anything.", "บันทึกจุดที่ย้อนกลับมาได้ ควรทำก่อนเปลี่ยนอะไร" },
            { "Create now", "สร้างเลย" },
            { "Turn one tweak off again, or roll the whole PC back.", "ปิดการปรับแต่งทีละข้อ หรือย้อนทั้งเครื่อง" },
            { "Open undo", "เปิดหน้าย้อนกลับ" },
            { "Updates", "อัปเดต" },
            { "See if there is a newer version of this tool.", "ดูว่ามีเครื่องมือเวอร์ชันใหม่ไหม" },
            { "Check", "ตรวจ" },
            // tweaks page
            { "Each switch puts one setting in place or takes it back. A restore point is offered before the first change.", "สวิตช์แต่ละตัวตั้งค่าหนึ่งข้อ หรือเอาออก จะเสนอสร้างจุดกู้คืนก่อนเปลี่ยนครั้งแรก" },
            { "Refresh", "รีเฟรช" },
            { "Turn on all recommended", "เปิดทุกข้อที่แนะนำ" },
            { "Recommended: safe for everyone", "แนะนำ: ปลอดภัยสำหรับทุกคน" },
            { "Optional: you decide", "ตัวเลือก: คุณตัดสินใจเอง" },
            { "Power: for desktops", "พลังงาน: สำหรับเดสก์ท็อป" },
            { "On", "เปิด" }, { "Off", "ปิด" }, { "Changed by Windows", "Windows เปลี่ยนกลับ" },
            { "Game Bar recording off", "ปิดการอัดเบื้องหลังของ Game Bar" },
            { "Stops Xbox Game Bar from recording in the background (Game DVR). Game Mode stays on.", "หยุด Xbox Game Bar ไม่ให้อัดภาพเบื้องหลัง (Game DVR) โหมดเกมยังเปิดอยู่" },
            { "Power throttling off", "ปิด Power throttling" },
            { "Windows no longer slows down programs it thinks are in the background. A little more power use.", "Windows ไม่หน่วงโปรแกรมที่คิดว่าอยู่เบื้องหลังอีก ใช้ไฟเพิ่มเล็กน้อย" },
            { "Gaming priority", "ความสำคัญของเกม" },
            { "Gives games higher CPU, graphics and disk priority.", "ให้เกมได้ CPU การ์ดจอ และดิสก์ก่อน" },
            { "Foreground priority", "ความสำคัญของโปรแกรมหน้าจอ" },
            { "The program in front, such as your game, gets more CPU time than the ones behind it.", "โปรแกรมที่อยู่หน้าจอ เช่นเกมของคุณ ได้เวลา CPU มากกว่าโปรแกรมที่อยู่ข้างหลัง" },
            { "Telemetry off", "ปิด Telemetry" },
            { "Sends less diagnostic data to Microsoft.", "ส่งข้อมูลวินิจฉัยให้ Microsoft น้อยลง" },
            { "System responsiveness", "ความตอบสนองของระบบ" },
            { "Keeps menus and apps lively while a game is running.", "ให้เมนูและแอปยังลื่นขณะเล่นเกม" },
            { "Delivery Optimization off", "ปิด Delivery Optimization" },
            { "Windows Update no longer shares updates with other PCs.", "Windows Update ไม่แบ่งปันอัปเดตให้เครื่องอื่นอีก" },
            { "GPU scheduling on", "เปิด GPU scheduling" },
            { "Lets the graphics card schedule its own work. Needs a restart.", "ให้การ์ดจอจัดคิวงานเอง ต้องรีสตาร์ท" },
            { "Fullscreen exclusive", "Fullscreen exclusive" },
            { "Uses true fullscreen in games instead of borderless windows.", "ใช้โหมดเต็มจอจริงในเกม แทนหน้าต่างไร้ขอบ" },
            { "Mouse without acceleration", "เมาส์ไม่มี acceleration" },
            { "The pointer moves exactly as far as your hand does.", "ตัวชี้ขยับตามระยะมือของคุณพอดี" },
            { "Keyboard fast repeat", "คีย์บอร์ดกดซ้ำเร็ว" },
            { "Keys repeat sooner and faster.", "ปุ่มซ้ำเร็วขึ้นและถี่ขึ้น" },
            { "Network memory fix", "แก้หน่วยความจำของเครือข่าย" },
            { "Fixes a memory problem in a Windows network driver on some PCs.", "แก้ปัญหาหน่วยความจำของไดรเวอร์เครือข่ายของ Windows ในบางเครื่อง" },
            { "Memory Integrity off", "ปิด Memory Integrity" },
            { "Can raise FPS on some PCs but lowers protection against malware. Needs a restart.", "อาจเพิ่ม FPS ในบางเครื่อง แต่ลดการป้องกันมัลแวร์ ต้องรีสตาร์ท" },
            { "Finer timer", "ตัวจับเวลาละเอียดขึ้น" },
            { "A finer system timer for smoother frame pacing. More battery use on laptops.", "ตัวจับเวลาของระบบละเอียดขึ้น เฟรมลื่นขึ้น โน้ตบุ๊กกินแบตมากขึ้น" },
            { "Drivers only from you", "ไดรเวอร์เฉพาะที่คุณลงเอง" },
            { "Windows Update stops installing drivers by itself, so it cannot replace the graphics driver you chose. Update drivers yourself, for example with the Drivers tool.", "Windows Update จะไม่ลงไดรเวอร์เองอีก จึงไม่เขียนทับไดรเวอร์การ์ดจอที่คุณเลือก ต้องอัปเดตไดรเวอร์เอง เช่น ใช้เครื่องมือ Drivers" },
            { "Startup programs start at once", "โปรแกรมเริ่มต้นเปิดทันที" },
            { "Programs that start with Windows begin right away instead of after about ten seconds. Takes effect at the next sign-in.", "โปรแกรมที่เปิดพร้อม Windows จะเริ่มทันที ไม่ต้องรอประมาณสิบวินาที มีผลเมื่อลงชื่อเข้าใช้ครั้งถัดไป" },
            { "Quick menus", "เมนูตอบสนองไว" },
            { "Menus open at once and hover reactions come sooner. Changes only how the desktop feels, not game speed. Takes effect after you sign out and in.", "เมนูเปิดทันทีและการวางเมาส์ค้างตอบสนองไวขึ้น เปลี่ยนแค่ความรู้สึกของหน้าจอ ไม่ได้ทำให้เกมเร็วขึ้น มีผลหลังออกจากระบบแล้วเข้าใหม่" },
            { "Windowed-game optimization", "ปรับเกมแบบหน้าต่างให้ไวขึ้น" },
            { "Windows 11 shows DirectX 10 and 11 games in a window or borderless window with lower frame latency. Your other graphics settings are kept.", "Windows 11 แสดงเกม DirectX 10 และ 11 ในโหมดหน้าต่างหรือ borderless ด้วยความหน่วงของเฟรมที่ต่ำลง การตั้งค่ากราฟิกอื่นของคุณไม่เปลี่ยน" },
            { "Network adapters stay on", "การ์ดเน็ตไม่หลับ" },
            { "Windows no longer switches off your network adapters to save power, which can cause lag spikes in online games. A little more battery use on laptops.", "Windows จะไม่ปิดการ์ดเน็ตเพื่อประหยัดไฟอีก ซึ่งอาจทำให้เกมออนไลน์กระตุกเป็นพักๆ โน้ตบุ๊กกินแบตเพิ่มเล็กน้อย" },
            { "Game Mode on", "เปิด Game Mode" },
            { "Makes sure Windows Game Mode is on, so Windows favours the game in front.", "ให้แน่ใจว่า Game Mode ของ Windows เปิดอยู่ เพื่อให้ Windows ให้ความสำคัญกับเกมที่อยู่หน้าจอ" },
            { "End task in the taskbar", "End task ในแถบงาน" },
            { "Adds End task to the taskbar right-click menu, to close a frozen game quickly. Windows 11 23H2 or newer.", "เพิ่ม End task ในเมนูคลิกขวาของแถบงาน เพื่อปิดเกมที่ค้างได้เร็ว ใช้ได้กับ Windows 11 23H2 ขึ้นไป" },
            { "Background apps off", "ปิดแอปพื้นหลัง" },
            { "Store apps may not run in the background. Desktop programs such as Steam and Discord are not affected. The effect varies by Windows build.", "แอปจาก Store จะไม่ทำงานเบื้องหลัง โปรแกรมเดสก์ท็อปอย่าง Steam และ Discord ไม่ได้รับผลกระทบ ผลต่างกันไปตามรุ่น Windows" },
            { "Edge stays out of the background", "Edge ไม่ทำงานเบื้องหลัง" },
            { "Microsoft Edge does not start with Windows or keep running after you close it, which saves some memory. Edge then says it is managed by your organization.", "Microsoft Edge จะไม่เริ่มพร้อม Windows และไม่ค้างทำงานหลังปิดหน้าต่าง ช่วยประหยัดหน่วยความจำ Edge จะขึ้นข้อความว่าถูกจัดการโดยองค์กร" },
            { "Hibernation off", "ปิด Hibernate" },
            { "Frees the disk space of hiberfil.sys, often 6 to 12 GB. Sleep and Shut down are not affected. Not for laptops that you hibernate.", "คืนพื้นที่ดิสก์ของ hiberfil.sys ซึ่งมักใหญ่ 6 ถึง 12 GB ไม่กระทบ Sleep และ Shut down ไม่เหมาะกับโน้ตบุ๊กที่ใช้ Hibernate" },
            { "CPU boost", "CPU boost" },
            { "Keeps the processor boosting. The PC runs hotter and louder; not for laptops.", "ให้ซีพียูบูสต์ต่อเนื่อง เครื่องร้อนและเสียงดังขึ้น ไม่เหมาะกับโน้ตบุ๊ก" },
            { "CPU power options", "ตัวเลือกพลังงานของ CPU" },
            { "Unlocks hidden CPU power options and sets the plugged-in power plan. For desktops.", "ปลดล็อกตัวเลือกพลังงานของ CPU ที่ซ่อนอยู่ และตั้งแผนพลังงานตอนเสียบปลั๊ก สำหรับเดสก์ท็อป" },
            // tools page
            { "Look at your PC, check it, and keep it tidy. Most of these only read; none of them delete anything without asking.", "ดูเครื่อง ตรวจเครื่อง และดูแลให้เรียบร้อย ส่วนใหญ่อ่านอย่างเดียว ไม่มีอะไรลบโดยไม่ถามก่อน" },
            { "Check status", "ตรวจสถานะ" },
            { "See which settings Windows changed back, and fix them.", "ดูว่า Windows เปลี่ยนค่าอะไรกลับ และแก้ให้" },
            { "PC specs", "สเปกเครื่อง" },
            { "Your PC on one page, in plain words. Your name and serial numbers are left out.", "เครื่องของคุณในหน้าเดียว ภาษาเข้าใจง่าย ไม่ใส่ชื่อและซีเรียลนัมเบอร์" },
            { "PC health", "สุขภาพเครื่อง" },
            { "Crashes, drive health, screen refresh rate, memory speed and cable speed.", "อาการแครช สุขภาพไดรฟ์ รีเฟรชเรตจอ ความเร็วแรม และความเร็วสายแลน" },
            { "System report", "รายงานระบบ" },
            { "What uses your processor and memory, and what starts with Windows.", "อะไรใช้ซีพียูและแรม และอะไรเริ่มพร้อม Windows" },
            { "Network test", "ทดสอบเครือข่าย" },
            { "Ping, jitter, packet loss and DNS speed. You choose what to test.", "ping, jitter, packet loss และความเร็ว DNS คุณเลือกว่าจะทดสอบอะไร" },
            { "Drivers", "ไดรเวอร์" },
            { "Find missing or old drivers. Installs only what you choose.", "หาไดรเวอร์ที่ขาดหรือเก่า ติดตั้งเฉพาะที่คุณเลือก" },
            { "Clean up", "ล้างไฟล์เก่า" },
            { "Old reports and backups. You choose what goes.", "รายงานและไฟล์สำรองเก่า คุณเลือกว่าจะลบอะไร" },
            { "Support bundle", "ชุดไฟล์สนับสนุน" },
            { "One file that you can attach to a problem report. Private details are replaced.", "ไฟล์เดียวสำหรับแนบรายงานปัญหา ข้อมูลส่วนตัวถูกแทนที่" },
            { "Classic menu", "เมนูแบบเดิม" },
            { "The original text menu with every option.", "เมนูข้อความแบบเดิมที่มีทุกตัวเลือก" },
            { "Run here", "รันที่นี่" }, { "Open", "เปิด" },
            { "Shows the result below", "แสดงผลด้านล่าง" }, { "Opens a window", "เปิดหน้าต่างใหม่" },
            // undo page
            { "Everything this tool does can be taken back. Pick the smallest step that fixes your problem.", "ทุกอย่างที่เครื่องมือนี้ทำ ย้อนกลับได้ เลือกขั้นที่เล็กที่สุดที่แก้ปัญหาได้" },
            { "One tweak", "ทีละข้อ" },
            { "Mouse feels odd? Turn that one switch off on the Tweaks page. The Windows default comes back at once.", "เมาส์รู้สึกแปลก? ปิดสวิตช์ข้อนั้นในหน้าการปรับแต่ง ค่าเริ่มต้นของ Windows จะกลับมาทันที" },
            { "Open Tweaks", "เปิดหน้าการปรับแต่ง" },
            { "The whole PC", "ทั้งเครื่อง" },
            { "Goes back to the restore point named Before_PC_Optimizer with Windows System Restore. Programs you installed after that point are removed, your files stay. The PC restarts.", "ย้อนกลับไปที่จุดกู้คืนชื่อ Before_PC_Optimizer ด้วย System Restore ของ Windows โปรแกรมที่ติดตั้งหลังจุดนั้นจะถูกถอด ไฟล์ของคุณอยู่ครบ เครื่องจะรีสตาร์ท" },
            { "Roll back the PC", "ย้อนทั้งเครื่อง" },
            { "Backups and reports", "ไฟล์สำรองและรายงาน" },
            { "Before a setting is changed, its old value is saved in the Backup folder. Double-click a file there to restore that value by hand.", "ก่อนเปลี่ยนค่า ค่าเดิมจะถูกเก็บไว้ในโฟลเดอร์ Backup ดับเบิลคลิกไฟล์ในนั้นเพื่อคืนค่าเองได้" },
            { "Open Backup folder", "เปิดโฟลเดอร์ Backup" }, { "Open Logs folder", "เปิดโฟลเดอร์ Logs" },
            // about page
            { "Windows 11 Optimizer, version", "Windows 11 Optimizer เวอร์ชัน" },
            { "Open source, free, no installer", "โอเพนซอร์ส ฟรี ไม่ต้องติดตั้ง" },
            { "This window only starts the tool's own scripts, which are plain text files in the folders next to it. Nothing is sent anywhere except the update check to github.com and the driver search to Microsoft. MIT licence.", "หน้าต่างนี้แค่สั่งสคริปต์ของเครื่องมือเอง ซึ่งเป็นไฟล์ข้อความธรรมดาในโฟลเดอร์ข้างๆ ไม่มีอะไรถูกส่งออก ยกเว้นการตรวจอัปเดตไปที่ github.com และการค้นหาไดรเวอร์ไปที่ Microsoft ลิขสิทธิ์ MIT" },
            { "Manual (English)", "คู่มือ (ภาษาอังกฤษ)" },
            { "Check for updates", "ตรวจหาอัปเดต" },
            { "Use at your own risk", "ใช้ด้วยความเสี่ยงของคุณเอง" },
            { "The tweaks change Windows settings. A restore point is offered first and every change has an undo. Built for desktops with Windows 11; on a laptop the heat and battery tweaks are left out of Easy Setup. Gains are small and depend on the game.", "การปรับแต่งเปลี่ยนค่าของ Windows โปรแกรมจะเสนอสร้างจุดกู้คืนก่อน และทุกการเปลี่ยนแปลงมีทางย้อนกลับ ออกแบบมาสำหรับเดสก์ท็อป Windows 11 ถ้าเป็นโน้ตบุ๊ก Easy Setup จะข้ามค่าที่ทำให้ร้อนและกินแบต ผลที่ได้เล็กน้อยและขึ้นกับเกม" },
            // dialogs and messages
            { "Roll back the whole PC?", "ย้อนทั้งเครื่องไหม?" },
            { "This opens Windows System Restore and restarts the PC. Save your work first.", "จะเปิด System Restore ของ Windows และรีสตาร์ทเครื่อง บันทึกงานของคุณก่อน" },
            { "Continue", "ทำต่อ" }, { "Cancel", "ยกเลิก" }, { "OK", "ตกลง" },
            { "Check for a new version?", "ตรวจหาเวอร์ชันใหม่ไหม?" },
            { "This window closes so that the update can replace it. If there is a newer version you are asked before anything is installed. Open this window again afterwards.", "หน้าต่างนี้จะปิด เพื่อให้การอัปเดตแทนที่ตัวเองได้ ถ้ามีเวอร์ชันใหม่ จะถามก่อนติดตั้ง หลังอัปเดตให้เปิดหน้าต่างนี้ใหม่" },
            { "Making the restore point (1 to 5 minutes)", "กำลังสร้างจุดกู้คืน (1 ถึง 5 นาที)" },
            { "[OK] Restore point made: Before_PC_Optimizer", "[OK] สร้างจุดกู้คืนแล้ว: Before_PC_Optimizer" },
            { "[!] The restore point could not be made. Turn on System Protection for drive C: in Windows if you want one.", "[!] สร้างจุดกู้คืนไม่สำเร็จ เปิด System Protection ของไดรฟ์ C: ใน Windows ถ้าต้องการจุดกู้คืน" },
            { "Make a restore point first?", "สร้างจุดกู้คืนก่อนไหม?" },
            { "A restore point lets you go back with one click. It takes a minute or two.", "จุดกู้คืนช่วยให้ย้อนกลับได้ในคลิกเดียว ใช้เวลาหนึ่งถึงสองนาที" },
            { "A restore point lets you go back with one click if you do not like a change. It takes a minute or two.", "จุดกู้คืนช่วยให้ย้อนกลับได้ในคลิกเดียว ถ้าไม่ชอบการเปลี่ยนแปลง ใช้เวลาหนึ่งถึงสองนาที" },
            { "Create restore point", "สร้างจุดกู้คืน" }, { "Skip", "ข้าม" },
            { "Turning on the recommended tweaks", "กำลังเปิดการปรับแต่งที่แนะนำ" },
            { "Please wait", "กรุณารอ" },
            { "Another task is still running. Try again when it is finished.", "ยังมีงานอื่นทำอยู่ ลองใหม่เมื่อเสร็จ" },
            { "Another task is still running.", "ยังมีงานอื่นทำอยู่" },
            { "Turn off Memory Integrity?", "ปิด Memory Integrity ไหม?" },
            { "Only do this on a PC you trust.", "ทำกับเครื่องที่คุณไว้ใจเท่านั้น" },
            { "Turn it off", "ปิดเลย" },
            { "Turning on", "กำลังเปิด" }, { "Turning off", "กำลังปิด" },
            // easy setup dialog
            { "How do you use this PC?", "คุณใช้เครื่องนี้แบบไหน?" },
            { "This only decides which tweaks are added. You can change any of them later.", "ข้อนี้กำหนดแค่ว่าจะเพิ่มการปรับแต่งใดบ้าง เปลี่ยนทีหลังได้ทุกข้อ" },
            { "Everyday", "ใช้งานทั่วไป" },
            { "The safe settings only. Good for every PC.", "เฉพาะค่าที่ปลอดภัย เหมาะกับทุกเครื่อง" },
            { "Gaming", "เล่นเกม" },
            { "Adds mouse, keyboard, timer and CPU boost.", "เพิ่มเมาส์ คีย์บอร์ด ตัวจับเวลา และ CPU boost" },
            { "Gaming, maximum", "เล่นเกม แบบสูงสุด" },
            { "Every optional tweak at once. The effect on FPS is small and depends on the game.", "ทุกการปรับแต่งที่เป็นตัวเลือกพร้อมกัน ผลต่อ FPS เล็กน้อยและขึ้นกับเกม" },
            { "Also turn off Memory Integrity (lowers protection)", "ปิด Memory Integrity ด้วย (ลดการป้องกัน)" },
            { "Type YES to confirm", "พิมพ์ YES เพื่อยืนยัน" },
            { "Start", "เริ่ม" },
            { "Type YES", "พิมพ์ YES" },
            { "To turn off Memory Integrity, type YES in the box.", "การปิด Memory Integrity ต้องพิมพ์ YES ในช่อง" },
            { "Easy Setup is running in its own window. Answer its questions there. This window updates when it finishes.", "Easy Setup กำลังทำงานในหน้าต่างของมันเอง ตอบคำถามที่นั่น หน้าต่างนี้จะอัปเดตเมื่อเสร็จ" },
            // activity panel
            { "Close", "ปิด" }, { "Copy", "คัดลอก" },
            { "Finished:", "เสร็จแล้ว:" },
            { "Stopped with a problem (code {0}):", "หยุดเพราะมีปัญหา (รหัส {0}):" },
            { "Could not start:", "เริ่มไม่ได้:" }
        };
    }
}
