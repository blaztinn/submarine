private class SubmarineConsole : Object {
	private enum ExitValue {
		OK = 0,
		NO_EFFECT = 1,
		INVALID_INPUT = 2
	}
	
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] _filenames;
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] _languages;
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] _server_codes;
	
	const OptionEntry[] options = {
		{ "", 0, 0, OptionArg.FILENAME_ARRAY, out _filenames, "List of movie files", "FILE..." },
		{ "language", 'l', 0, OptionArg.STRING_ARRAY, out _languages, "Set languages to filter (use '-l help' to list all options)", "CODE" },
		{ "server", 's', 0, OptionArg.STRING_ARRAY, out _server_codes, "Set servers to use (use '-s help' to list all options)", "CODE" },
		{ "force", 'f', 0, OptionArg.NONE, out force, "Overwrite existing subtitles", null },
		{ "quiet", 'q', 0, OptionArg.NONE, out quiet, "Be quiet", null },
		{ "verbose", 'v', 0, OptionArg.NONE, out verbose, "Be verbose", null },
		{ "version", 'V', 0, OptionArg.NONE, out info, "Show program information", null },
		{ null }
	};
	
	private const string name = Config.PACKAGE_NAME;
	private const string version = Config.PACKAGE_VERSION;
	
	private static Gee.Set<string> filenames;
	private static Gee.Set<string> languages;
	private static Gee.Set<string> server_codes;
	private static bool force = false;
	private static bool quiet = false;
	private static bool verbose = false;
	private static bool info = false;
	
	private static Submarine.Session session;
	
	private static Gee.Set<string> string_array_to_set(string[] array) {
		var hash_set = new Gee.HashSet<string>();
		
		foreach(string el in array) {
			hash_set.add(el);
		}
		
		return hash_set;
	}
	
	private static void init(ref unowned string[] args) {
		var args_length = args.length;
		
		var opt_context = new OptionContext("- download subtitles");
		string description = "Powered by:\n";
		foreach(var server_code in Submarine.get_server_codes())
		{
			var server_info = Submarine.get_server_info(server_code);
			description += "  %s (%s)\n".printf(server_info.name, server_info.address);
		}
		description = description[0:-1];
		opt_context.set_description(description);
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);
		
		
		//parse args
		try {
			opt_context.parse(ref args);
		} catch(Error e) {
			Report.error(e.message, ExitValue.INVALID_INPUT);
		}
		
		//no args
		if(args_length == 1) {
			Report.message(opt_context.get_help(true, null), false);
			Process.exit(ExitValue.INVALID_INPUT);
		}
		
		filenames = string_array_to_set(_filenames);
		languages = string_array_to_set(_languages);
		server_codes = string_array_to_set(_server_codes);
		
		//program info
		if(info) {
			Report.message("%s %s".printf(name, version));
			Process.exit(ExitValue.OK);
		}
		
		//verbosity
		if(quiet) {
			Report.verbosity = Report.Verbosity.NONE;
		} else if(verbose) {
			Report.verbosity = Report.Verbosity.ALL;
		}
		
		//server codes
		foreach(var code in server_codes) {
			var all_server_codes = Submarine.get_server_codes();
			
			if(code == "help") {
				Report.message("Available servers:");
				foreach(var all_code in all_server_codes) {
					var server_info = Submarine.get_server_info(all_code);
					Report.message("  %s - %s (%s)".printf(server_info.code, server_info.name, server_info.address));
				}
				Process.exit(ExitValue.OK);
			} else if(!all_server_codes.contains(code)) {
				Report.error("Server '%s' does not exist!".printf(code), ExitValue.INVALID_INPUT);
			}
		}
		//languages
		foreach(var language in languages) {
			var all_language_codes = Submarine.get_language_codes();
			
			if(language == "help") {
				Report.message("Available languages:");
				foreach(var all_code in all_language_codes) {
					if(all_code.length == 3) {
						var language_info = Submarine.get_language_info(all_code);
						if(language_info.short_code == null) {
							Report.message("  %s    - %s".printf(language_info.long_code, language_info.name));
						} else {
							Report.message("  %s %s - %s".printf(language_info.long_code, language_info.short_code, language_info.name));
						}
					}
				}
				Process.exit(ExitValue.OK);
			} else if(!all_language_codes.contains(language)) {
				Report.error("Language '%s' does not exist!".printf(language), ExitValue.INVALID_INPUT);
			}
		}
		
		//filenames
		if(filenames.is_empty) {
			Report.error("No file selected!", ExitValue.INVALID_INPUT);
		}
		foreach(var filename in filenames) {
			if(!FileUtils.test(filename, FileTest.IS_REGULAR)) {
				Report.error("File '%s' does not exist!".printf(filename), ExitValue.INVALID_INPUT);
			}
		}
		
		//default values
		if(server_codes.is_empty) {
			server_codes.add_all(Submarine.get_server_codes());
			Report.warning("No server(s) selected, using all servers.", true, Report.Verbosity.ALL);
		}
		if(languages.is_empty) {
			languages.add("eng");
			languages.add("en");
			Report.warning("No language(s) selected, using ['eng', 'en'] languages.", true, Report.Verbosity.ALL);
		}
	}
	
	private static string? subtitle_save(string filename, Submarine.Subtitle subtitle, bool force = false) {
		string sub_filename = subtitle.get_filename(filename);
		File file = File.new_for_commandline_arg(sub_filename);
		
		if(subtitle.has_data) {
			if(!file.query_exists() ||
			   (file.query_exists() && force)) {
				try {
					FileUtils.set_contents(sub_filename, subtitle.data);
					return sub_filename;
				} catch(Error e) {
					Report.warning("Could not save '%s': %s".printf(sub_filename, e.message));
				}
			}
		}
		
		return null;
	}
	
	private static Gee.Map<string, string> subtitle_save_multiple(Gee.Map<string, Submarine.Subtitle> save_map, bool force = false) {
		var subtitles_saved = new Gee.HashMap<string, string>();
		
		foreach(var entry in save_map.entries) {
			var sub_filename = subtitle_save(entry.key, entry.value, force);
			if(sub_filename != null) {
				subtitles_saved.set(entry.key, sub_filename);
			}
		}
		
		return subtitles_saved;
	}
	
	private static int main(string[] args) {
		init(ref args);
		
		session = new Submarine.Session();
		
		//Connect to server(s)
		Report.message("Connecting to servers:");
		var connected_servers = session.server_connect_multiple(server_codes);
		//  Report success/failure
		foreach(var code in server_codes) {
			var server_info = Submarine.get_server_info(code);
			if(code in connected_servers) {
				Report.message("  (Success) %s (%s)".printf(server_info.name, server_info.address));
			} else {
				Report.message("  (Failure) %s (%s)".printf(server_info.name, server_info.address));
			}
		}
		
		if(!connected_servers.is_empty) {
			//Search for available subtitles
			Report.message("Searching for subtitles:");
			var subtitles_found_map = session.subtitle_search_multiple(filenames, languages);
			//  Report number of subtitles found per file
			foreach(var filename in filenames) {
				if(filename in subtitles_found_map) {
					Report.message("  (%d) %s".printf(subtitles_found_map[filename].size, filename));
				} else {
					Report.message("  (0) %s".printf(filename));
				}
			}
			
			//Select and download one subtitle per file
			if(subtitles_found_map.size > 0) {
				Report.message("Downloading subtitles:");
			}
			var subtitles_download_map = new Gee.HashMap<string, Submarine.Subtitle>();
			//  Select subtitles with best rating per each file
			foreach(var key in subtitles_found_map.get_keys()) {
				foreach(var subtitle in subtitles_found_map[key]) {
					if(!subtitles_download_map.has_key(key)) {
						subtitles_download_map.set(key, subtitle);
					} else {
						if(subtitle.rating > subtitles_download_map[key].rating) {
							subtitles_download_map[key] = subtitle;
						}
					}
				}
			}
			//  Download selected subtitles
			var subtitles_downloaded = session.subtitle_download_multiple(subtitles_download_map.values);
			//  Report downloaded subtitles rating or error
			foreach(var entry in subtitles_download_map.entries) {
				if(entry.value in subtitles_downloaded) {
					Report.message("  (%.1f) %s".printf(entry.value.rating, entry.value.get_filename(entry.key)));
				} else {
					Report.message("  (Could not download) %s".printf(entry.value.get_filename(entry.key)));
				}
			}
			
			//Save downloaded subtitles
			var subtitles_saved_map = subtitle_save_multiple(subtitles_download_map, force);
			
			//Report success/failure for each file
			Report.message("Summary:");
			foreach(var filename in filenames) {
				if(filename in subtitles_saved_map.keys) {
					//  Subtitle successfully saved
					Report.message("  (Saved) %s".printf(subtitles_saved_map[filename]));
				} else if(subtitles_download_map.has_key(filename)) {
					//  Could not save subtitle
					var sub_filename = subtitles_download_map[filename].get_filename(filename);
					if(FileUtils.test(sub_filename, FileTest.EXISTS)){
						Report.message("  (File already exists) %s".printf(sub_filename));
					} else {
						Report.message("  (Could not save) %s".printf(sub_filename));
					}
				} else if(filename in subtitles_found_map && subtitles_found_map[filename].size > 0) {
					//  Could not download subtitle
					var sub_filename = subtitles_found_map[filename].iterator().get().get_filename(filename);
					Report.message("  (Could not download) %s".printf(sub_filename));
				} else {
					//  Could not find subtitle
					Report.message("  (Not found) %s".printf(filename));
				}
			}
			
			//Return >0 if nothing was saved or overwritten
			if(subtitles_saved_map.is_empty) {
				return ExitValue.NO_EFFECT;
			}
		} else {
			Report.message("Summary:");
			Report.message("  Could not connect to any Server!");
			return ExitValue.NO_EFFECT;
		}
		
		return ExitValue.OK;
	}
}
