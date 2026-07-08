package;

class Progress {
	public var current:Int;
	public var total:Int;

	// the two lines shown under the bar: the step before, and the step now
	var prevAction:String = "";
	var curAction:String = "";

	static inline var WIDTH = 18;

	public function new(inCurrent:Int, inTotal:Int) {
		current = inCurrent;
		total = inTotal;
	}

	public function progress(inCurrent:Int) {
		current += inCurrent;
	}

	/**
		Enlarge the denominator as each file group reveals how much work it has.
		A group's `to_be_compiled` is only known once its dependency check has run,
		so one bar spanning every group has to grow rather than be sized up front.
	**/
	public function addTotal(inFiles:Int) {
		total += inFiles;
	}

	/**
		Advance the count by one and redraw the live block for `fileName`. The
		current action becomes `compiling <file>`; the one it replaces slides up
		to the "previous" line. Caller holds the print lock.
	**/
	public function step(fileName:String, ?tags:String) {
		current++;
		var action = "compiling " + baseName(fileName);
		if (tags != null && tags != "")
			action += "  " + Log.DIM + tags + Log.NORMAL;
		if (action != curAction) {
			prevAction = curAction;
			curAction = action;
		}
		Log.drawStatus(bar(), prevAction, curAction);
	}

	/**
		Account for a file served from the compile cache. It is one of `total`, so it
		advances and redraws the bar just like a real compile - otherwise a build that
		opens with a long run of cache hits would leave the bar hidden and then have
		it appear, disconcertingly, at 20%.
	**/
	public function skip(fileName:String) {
		current++;
		var action = "cached " + baseName(fileName);
		if (action != curAction) {
			prevAction = curAction;
			curAction = action;
		}
		Log.drawStatus(bar(), prevAction, curAction);
	}

	/** Erase the block once the phase is done. **/
	public function finish() {
		Log.clearStatus();
	}

	function bar():String {
		var frac = total > 0 ? current / total : 0.0;
		if (frac < 0) frac = 0;
		if (frac > 1) frac = 1;
		var filled = Math.round(frac * WIDTH);
		// box-drawing on a UTF-8 console; on cp866/cp1251 it would be mojibake, so
		// fall back to ASCII with a distinct fill/track so it still reads as a bar
		var unicode = Log.ensureUnicode();
		var fill = unicode ? "━" : "=";
		var track = unicode ? "━" : "-";
		var pct = Std.int(frac * 100);
		return Log.BAR + rep(fill, filled) + Log.DIM + rep(track, WIDTH - filled) + Log.NORMAL
			+ "  " + Log.GRAY + pct + "%" + Log.NORMAL;
	}

	static function baseName(path:String):String {
		var s = StringTools.replace(path, "\\", "/");
		var i = s.lastIndexOf("/");
		return i == -1 ? s : s.substr(i + 1);
	}

	static function rep(s:String, n:Int):String {
		var buf = new StringBuf();
		var i = 0;
		while (i++ < n)
			buf.add(s);
		return buf.toString();
	}

	public function getProgress() {
		var percent = current / total;
		var pct = Std.int(percent * 1000) / 10;
		var str = Std.string(pct);
		if (Std.int(pct) == pct) {
			str += ".0";
		}
		while (str.length < 4)
			str = " " + str;
		return "[" + str + "%]";
	}
}
