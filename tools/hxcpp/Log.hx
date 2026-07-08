import haxe.io.Bytes;
import sys.io.Process;

#if haxe4
import sys.thread.Mutex;
#elseif neko
import neko.vm.Mutex;
#else
import cpp.vm.Mutex;
#end

#if neko
import neko.Lib;
#else
import cpp.Lib;
#end

class Log
{
   public static var mute:Bool= false;
   public static var quiet:Bool = false;
   public static var verbose:Bool = false;
   public static var showSetup:Bool = false;
   // Echo the full compiler/linker command line for every file. This is what -v
   // used to do and it drowns everything else, so it now needs -vv (or the
   // HXCPP_LOG_COMMANDS define). A failing command still prints in full.
   public static var showCommands:Bool = false;

   public  static var colorSupported:Null<Bool> = null;
   // Whether the console can render the box-drawing/tick glyphs. Independent of
   // colour: a cp866/cp1251 PowerShell renders ANSI colour fine but turns "━"
   // into mojibake. Forced with HXCPP_UNICODE / HXCPP_NO_UNICODE.
   public  static var unicodeSupported:Null<Bool> = null;
   private static var sentWarnings = new Map<String,Bool>();

   public static var printMutex:Mutex;

   public static inline var RED = "\x1b[31m";
   public static inline var YELLOW = "\x1b[33m";
   public static inline var WHITE = "\x1b[37m";
   public static inline var NORMAL = "\x1b[0m";
   public static inline var BOLD = "\x1b[1m";
   public static inline var ITALIC = "\x1b[3m";

   // 256-colour palette used by the compact build view. Deliberately 256-colour
   // (not 24-bit truecolor) because classic Windows conhost renders these
   // reliably while choking on truecolor.
   public static inline var BAR   = "\x1b[38;5;208m"; // progress bar fill (orange)
   public static inline var GREEN = "\x1b[38;5;114m"; // stage marker ">" / done
   public static inline var GRAY  = "\x1b[38;5;7m";   // current line / info
   public static inline var DIM   = "\x1b[38;5;8m";   // previous line / bar track

   /** Green stage marker: "›" on a UTF-8 console, ASCII ">" otherwise. **/
   public static function mark():String
      return GREEN + (ensureUnicode() ? "›" : ">") + NORMAL;

   // ── live status block (bar + previous/current action) ───────────────────
   // Drawn at the "bottom"; any real log output calls clearStatus() first so
   // messages scroll above it instead of colliding with it.
   static var statusLines = 0;
   static var vtChecked = false;

   public static function initMultiThreaded()
   {
     if (printMutex==null)
        printMutex = new Mutex();
   }

   public static function e(message:String):Void
   {
      error(message);
   }
   public static function error(message:String, verboseMessage:String = "", e:Dynamic = null, terminate:Bool = true):Void
   {
      // ✗ glyph on a UTF-8 console, ASCII 'x' otherwise
      var glyph = ensureUnicode() ? "✗ " : "x ";
      var body = (verbose && verboseMessage != "") ? verboseMessage : message;
      var output;
      if (body == "")
         output = RED + BOLD + glyph + "error" + NORMAL + "\n";
      else
         // red glyph, error body left in the default colour so it stays legible
         output = RED + BOLD + glyph + NORMAL + body + "\n";
      if (printMutex!=null)
         printMutex.acquire();
      clearStatus();
      Sys.stderr().write(Bytes.ofString(stripColor(output)));
      if (printMutex!=null)
         printMutex.release();

      if ((verbose || !terminate) && e != null)
         Lib.rethrow(e);

      if (terminate)
         Tools.exit(1);
   }

   public static function info(message:String, verboseMessage:String = ""):Void
   {
      if (!mute)
      {
         if (printMutex!=null)
            printMutex.acquire();
         if (verbose && verboseMessage != "")
         {
            println(verboseMessage);
         }
         else if (message != "")
         {
            println(message);
         }
         if (printMutex!=null)
            printMutex.release();
      }
   }
   inline public static function v(verboseMessage:String):Void
   {
      Log.info("",verboseMessage);
   }

   inline public static function setup(verboseMessage:String):Void
   {
      Log.info(showSetup ? verboseMessage : "",verboseMessage);
   }


   public static function lock():Void
   {
      if (printMutex!=null)
        printMutex.acquire();
   }

   public static function unlock():Void
   {
      if (printMutex!=null)
        printMutex.release();
   }


   public static function print(message:String):Void
   {
      if (printMutex!=null)
        printMutex.acquire();
      clearStatus();
      Sys.print(stripColor(message));
         if (printMutex!=null)
            printMutex.release();
   }

   public static function println(message:String):Void
   {
      if (printMutex!=null)
        printMutex.acquire();
      clearStatus();
      Sys.println(stripColor(message));
      if (printMutex!=null)
         printMutex.release();
   }

   // Colour is on by default now; only turned off by the NO_COLOR convention
   // (or the explicit -nocolor / HXCPP_NO_COLOR opt-outs handled in BuildTool).
   public static function ensureColor():Bool
   {
      probeConsole();
      return colorSupported == true;
   }

   /** Whether "━" / "✗" are safe to print, or we must fall back to ASCII. **/
   public static function ensureUnicode():Bool
   {
      probeConsole();
      return unicodeSupported == true;
   }

   /**
      One-time console probe. On Windows a single PowerShell shim both flips
      ENABLE_VIRTUAL_TERMINAL_PROCESSING on the real console (CONOUT$), so ANSI
      escapes render instead of printing as raw `←[..m`, and reports the output
      code page - only 65001 (UTF-8) can render the box-drawing glyphs, so a
      cp866/cp1251 console falls back to ASCII.
   **/
   static function probeConsole():Void
   {
      if (vtChecked)
         return;
      vtChecked = true;

      if (colorSupported == null)
         colorSupported = Sys.getEnv("NO_COLOR") == null;

      if (Sys.getEnv("HXCPP_NO_UNICODE") != null)
         unicodeSupported = false;
      else if (Sys.getEnv("HXCPP_UNICODE") != null)
         unicodeSupported = true;

      // Deliberately not BuildTool.isWindows: that is assigned during setup and may
      // still be false the first time anything is logged, which would cache the
      // wrong answer here (probeConsole only ever runs once).
      if (Sys.systemName() != "Windows")
      {
         // unix terminals are UTF-8
         if (unicodeSupported == null)
            unicodeSupported = true;
         return;
      }

      var codePage:Null<Int> = null;
      try
      {
         var csharp =
            "[DllImport(\"kernel32.dll\",SetLastError=true)]public static extern System.IntPtr CreateFileW(string n,uint a,uint s,System.IntPtr se,uint d,uint f,System.IntPtr t);"
            + "[DllImport(\"kernel32.dll\")]public static extern bool GetConsoleMode(System.IntPtr h,out uint m);"
            + "[DllImport(\"kernel32.dll\")]public static extern bool SetConsoleMode(System.IntPtr h,uint m);";
         var vt = colorSupported
            ? "try{$k=Add-Type -MemberDefinition $s -Name Vt -Namespace HxVt -PassThru -ErrorAction Stop;"
              + "$h=$k::CreateFileW('CONOUT$',0x40000000,3,[System.IntPtr]::Zero,3,0,[System.IntPtr]::Zero);"
              + "$m=0;if($k::GetConsoleMode($h,[ref]$m)){[void]$k::SetConsoleMode($h,($m -bor 4))}}catch{};"
            : "";
         var ps = "$s='" + csharp + "';" + vt + "try{[Console]::OutputEncoding.CodePage}catch{'x'}";
         var p = new Process("powershell", ["-NoProfile", "-NonInteractive", "-Command", ps]);
         var out = StringTools.replace(p.stdout.readAll().toString(), "\r", "");
         p.exitCode();
         p.close();
         codePage = Std.parseInt(StringTools.trim(out));
      }
      catch (e:Dynamic) {}

      if (unicodeSupported == null)
         unicodeSupported = (codePage == 65001);
   }

   private static function stripColor(output:String):String
   {
      if (ensureColor())
         return output;
      var colorCodes:EReg = ~/\x1b\[[^m]+m/g;
      return colorCodes.replace(output, "");
   }

   /**
      Redraws the live status block in place: a progress `bar`, then the previous
      and current action lines. No-op when colour/VT is off (the cursor moves
      would otherwise garble a plain log). Callers already hold the print lock.
   **/
   public static function drawStatus(bar:String, prev:String, cur:String):Void
   {
      if (!ensureColor())
         return;
      var buf = new StringBuf();
      if (statusLines > 0)
         buf.add("\x1b[" + statusLines + "A"); // back up over the previous block
      inline function line(s:String) { buf.add("\r\x1b[K"); buf.add(s); buf.add("\n"); }
      line("   " + bar);
      line("   " + DIM + prev + NORMAL);
      line("   " + GRAY + cur + NORMAL);
      Sys.print(buf.toString());
      statusLines = 3;
   }

   /** Whether the status block is currently on screen. **/
   public static function statusVisible():Bool
   {
      return statusLines > 0;
   }

   /** Erases the status block, leaving the cursor where the block began. **/
   public static function clearStatus():Void
   {
      if (statusLines == 0)
         return;
      var n = statusLines;
      var buf = new StringBuf();
      buf.add("\x1b[" + n + "A");
      for (_ in 0...n)
         buf.add("\r\x1b[K\n");
      buf.add("\x1b[" + n + "A");
      Sys.print(buf.toString());
      statusLines = 0;
   }

   public static function warn(message:String, verboseMessage:String = "", allowRepeat:Bool = false):Void
   {
      if (!mute)
      {
         var output = "";
         if (verbose && verboseMessage != "")
         {
            output = "\x1b[33;1mWarning:\x1b[0m \x1b[1m" + verboseMessage + "\x1b[0m";
         }
         else if (message != "")
         {
            output = "\x1b[33;1mWarning:\x1b[0m \x1b[1m" + message + "\x1b[0m";
         }

         if (!allowRepeat && sentWarnings.exists (output))
         {
            return;
         }

         sentWarnings.set(output, true);

         if (printMutex!=null)
            printMutex.acquire();
         println(output);
         if (printMutex!=null)
            printMutex.release();
      }
   }
}
