namespace Report {
	
	private enum Verbosity {
		NONE = 0,
		DEFAULT = 1,
		ALL = 2
	}
	
	private static Verbosity verbosity = Verbosity.DEFAULT;
	
	private static void message(string message, bool newline = true, Verbosity message_verbosity = Verbosity.DEFAULT) {
		if(verbosity > Verbosity.NONE && message_verbosity <= verbosity) {
			if(newline) {
				stdout.printf("%s\n", message);
			} else {
				stdout.printf("%s", message);
			}
		}
	}
	
	private static void warning(string message, bool newline = true, Verbosity message_verbosity = Verbosity.DEFAULT) {
		if(verbosity > Verbosity.NONE && message_verbosity <= verbosity) {
			if(newline) {
				stdout.printf("WARNING: %s\n", message);
			} else {
				stdout.printf("WARNING: %s", message);
			}
		}
	}
	
	private static void error(string message, int ret_value, bool newline = true) {
		if(newline) {
			stderr.printf("ERROR: %s\n", message);
		} else {
			stderr.printf("ERROR: %s", message);
		}
		
		Process.exit(ret_value);
	}
	
}
