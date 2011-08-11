private class SubmarineConsole : Object {
	private enum ExitValue {
		OK = 0,
		PROGRAM_ERROR = 1,
		INPUT_ERROR = 2
	}
	
	private const string[] SUBTITLE_EXTENSIONS = {
		"aqt", "jss", "sub", "ttxt",
		"pjs", "psb", "rt", "smi",
		"ssf", "srt", "gsub", "ssa",
		"ass", "usf", "txt"
	};
	
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] _filenames;
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] _languages;
	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] _server_codes;
	
	const OptionEntry[] options = {
		{ "", 0, 0, OptionArg.FILENAME_ARRAY, out _filenames, "List of movie files", "FILE..." },
		{ "language", 'l', 0, OptionArg.STRING_ARRAY, out _languages, "Set languages to filter (use '-l help' to list available options)", "CODE" },
		{ "server", 's', 0, OptionArg.STRING_ARRAY, out _server_codes, "Set servers to use (use '-s help' to list available options)", "CODE" },
		{ "force", 'f', 0, OptionArg.NONE, out force, "Replace existing subtitles", null },
		{ "quiet", 'q', 0, OptionArg.NONE, out quiet, "Be quiet", null },
		{ "verbose", 'v', 0, OptionArg.NONE, out verbose, "Be verbose", null },
		{ "version", 'V', 0, OptionArg.NONE, out info, "Show program information", null },
		{ null }
	};
	
	private const string name = Config.PACKAGE_NAME;
	private const string version = Config.PACKAGE_VERSION;
	
	private static Gee.Set<string> filenames;
	private static Gee.MultiMap<string, string> existing_subtitles;
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
			Report.error(e.message, ExitValue.INPUT_ERROR);
		}
		
		//no args
		if(args_length == 1) {
			Report.message(opt_context.get_help(true, null), false);
			Process.exit(ExitValue.INPUT_ERROR);
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
				Report.error("Server '%s' does not exist! Use '-s help' to list available options.".printf(code), ExitValue.INPUT_ERROR);
			}
		}
		//languages
		foreach(var language in languages) {
			var all_language_codes = Submarine.get_language_codes();
			
			if(language == "help") {
				Report.message("Available languages:");
				foreach(var all_code in all_language_codes) {
					var language_info = Submarine.get_language_info(all_code);
					if(language_info.long_code == all_code) {
						Report.message("  %s %s %s - %s".printf(
								language_info.long_code,
								language_info.long_code_alt ?? "   ",
								language_info.short_code ?? "  ",
								language_info.name));
					}
				}
				Process.exit(ExitValue.OK);
			} else if(!all_language_codes.contains(language)) {
				Report.error("Language '%s' does not exist! Use '-l help' to list available options.".printf(language), ExitValue.INPUT_ERROR);
			}
		}
		
		//filenames
		if(filenames.is_empty) {
			Report.error("No file selected!", ExitValue.INPUT_ERROR);
		}
		
		existing_subtitles = new Gee.HashMultiMap<string, string>();
		foreach(var filename in filenames) {
			if(!FileUtils.test(filename, FileTest.IS_REGULAR)) {
				Report.error("File '%s' does not exist!".printf(filename), ExitValue.INPUT_ERROR);
			}
			
			foreach(var sub_extension in SUBTITLE_EXTENSIONS) {
				string sub_filename = filename;
				sub_filename = sub_filename.slice(0, sub_filename.last_index_of(".")+1) + sub_extension;
				
				if(FileUtils.test(sub_filename, FileTest.EXISTS)) {
					existing_subtitles.set(filename, sub_filename);
					
					if(!force) {
						Report.warning("File '%s' already has a subtitle! Use '--force' to replace.".printf(filename), true, Report.Verbosity.ALL);
						break; //we only need to find one subtitle per file if we don't use force
					} else {
						Report.warning("Replacing '%s' subtitle.".printf(sub_filename), true, Report.Verbosity.ALL);
					}
				}
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
			Gee.Set<string> search_filenames;
			
			if(!force) {
				search_filenames = new Gee.HashSet<string>();
				search_filenames.add_all(filenames);
				search_filenames.remove_all(existing_subtitles.get_keys());
			} else {
				search_filenames = filenames;
			}
			
			//Search for available subtitles
			if(!search_filenames.is_empty) {
				Report.message("Searching for subtitles:");
			}
			var subtitles_found_map = session.subtitle_search_multiple(search_filenames, languages);
			//  Report number of subtitles found per file
			foreach(var filename in search_filenames) {
				if(filename in subtitles_found_map) {
					Report.message("  (%d) %s".printf(subtitles_found_map[filename].size, filename));
				} else {
					Report.message("  (0) %s".printf(filename));
				}
			}
			
			//Select and download one subtitle per file
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
			if(subtitles_found_map.size > 0) {
				Report.message("Downloading subtitles:");
			}
			var subtitles_downloaded = session.subtitle_download_multiple(subtitles_download_map.values);
			//  Report downloaded subtitles rating or error
			var subtitles_save_map = new Gee.HashMap<string, Submarine.Subtitle>();
			foreach(var entry in subtitles_download_map.entries) {
				if(entry.value in subtitles_downloaded) {
					Report.message("  (%.1f) %s".printf(entry.value.rating, entry.value.get_filename(entry.key)));
					subtitles_save_map.set(entry.key, entry.value);
				} else {
					Report.message("  (Could not download) %s".printf(entry.value.get_filename(entry.key)));
				}
			}
			
			//Save downloaded subtitles
			//  Delete existing subtitles if we use force
			if(force) {
				foreach(var filename in subtitles_save_map.keys) {
					foreach(var sub_filename in existing_subtitles[filename]) {
						FileUtils.remove(sub_filename);
					}
				}
			}
			//  Save new ones
			var subtitles_saved_map = subtitle_save_multiple(subtitles_save_map, force);
			
			//Report success/failure for each file
			var error = false;
			Report.message("Summary:");
			foreach(var filename in filenames) {
				if(filename in subtitles_saved_map.keys) {
					//  Subtitle successfully saved
					if(!(filename in existing_subtitles.get_keys())) {
						Report.message("  (Saved) %s".printf(subtitles_saved_map[filename]));
					} else {
						Report.message("  (Replaced) %s".printf(subtitles_saved_map[filename]));
					}
				} else if(subtitles_save_map.has_key(filename)) {
					//  Could not save subtitle
					var sub_filename = subtitles_download_map[filename].get_filename(filename);
					Report.message("  (Could not save) %s".printf(sub_filename));
					error = true;
				} else if(filename in subtitles_download_map.keys) {
					//  Could not download subtitle
					var it = subtitles_found_map[filename].iterator();
					it.next();
					var sub_filename = it.get().get_filename(filename);
					Report.message("  (Could not download) %s".printf(sub_filename));
					error = true;
				} else if(!force && filename in existing_subtitles.get_keys()) {
					//  Subtitle already exists
					var it = existing_subtitles[filename].iterator();
					it.next();
					var sub_filename = it.get();
					Report.message("  (Already exists) %s".printf(sub_filename));
				} else {
					//  Could not find subtitle
					Report.message("  (Not found) %s".printf(filename));
					error = true;
				}
			}
			
			if(error) {
				return ExitValue.PROGRAM_ERROR;
			}
		} else {
			Report.message("Summary:");
			Report.message("  Could not connect to any Server!");
			return ExitValue.PROGRAM_ERROR;
		}
		
		return ExitValue.OK;
	}
}
