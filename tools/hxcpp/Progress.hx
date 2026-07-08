package;

class Progress {
	public var current:Int;
	public var total:Int;

	// the two lines shown under the bar: the step before, and the step now
	var prevAction:String = "";
	var curAction:String = "";

	static inline var WIDTH = 28;

	public function new(inCurrent:Int, inTotal:Int) {
		current = inCurrent;
		total = inTotal;
	}

	public function progress(inCurrent:Int) {
		current += inCurrent;
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
		Account for a file served from the compile cache. It still advances the
		bar (it is one of `total`), but it only redraws when the block is already
		on screen - so a fully cached group stays silent instead of flashing a bar.
	**/
	public function skip() {
		current++;
		if (Log.statusVisible())
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
		var glyph = Log.ensureColor() ? "━" : "="; // ━ on a proper console, = otherwise
		var pct = Std.int(frac * 100);
		return Log.PINK + rep(glyph, filled) + Log.DIM + rep(glyph, WIDTH - filled) + Log.NORMAL
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
