namespace Submarine {
	
	private class OpenSubtitlesServer : SubtitleServer {
		private Soup.SessionSync session;
		private string session_token;
		
		construct {
			this.info = ServerInfo("OpenSubtitles",
					"http://www.opensubtitles.org",
					"os");
		}
		
		private string language_codes_string(Gee.Collection<string> languages) {
			var languages_set = new Gee.HashSet<string>();
			
			foreach(var language in languages) {
				var language_info = get_language_info(language);
				
				languages_set.add(language_info.long_code);
				if(language_info.long_code_alt != null) {
					languages_set.add(language_info.long_code_alt);
				}
				if(language_info.short_code != null) {
					languages_set.add(language_info.short_code);
				}
			}
			
			var languages_array = languages_set.to_array();
			var languages_array_copy = languages_array;
			
			return string.joinv(",", languages_array_copy);
		}
		
		private uint64 file_size(File file) throws Error {
			var file_info = file.query_info("*", FileQueryInfoFlags.NONE);
			return file_info.get_size();
		}
		
		private uint64 file_hash(File file) throws Error,IOError {
			uint64 hash, size;
			
			//get filesize and add it to hash
			size = this.file_size(file);
			hash = size;
			
			//add first 64kB of file to hash
			var dis = new DataInputStream(file.read());
			dis.set_byte_order(DataStreamByteOrder.LITTLE_ENDIAN);
			for(int i=0; i<65536/sizeof(uint64); i++) {
				hash += dis.read_uint64();
			}
			//add last 64kB of file to hash
			dis = new DataInputStream(file.read());
			dis.set_byte_order(DataStreamByteOrder.LITTLE_ENDIAN);
			dis.skip((size_t)(size - 65536));
			for(int i=0; i<65536/sizeof(uint64); i++) {
				hash += dis.read_uint64();
			}
			
			return hash;
		}
		
		private string deflate_subtitle(uint8[] data) throws IOError{
			var src_stream = new MemoryInputStream.from_data(data, null);
			var dst_stream = new MemoryOutputStream(null, GLib.realloc, GLib.free);
			var conv_stream = new ConverterOutputStream (dst_stream, new ZlibDecompressor(ZlibCompressorFormat.GZIP));
			
			conv_stream.splice(src_stream, 0);
			
			return (string)dst_stream.get_data();
		}
		
		public override bool connect() {
			this.session = new Soup.SessionSync();
			
			var message = Soup.XMLRPC.request_new ("http://api.opensubtitles.org/xml-rpc",
					"LogIn",
					typeof(string), "",
					typeof(string), "", 
					typeof(string), "",
					typeof(string), "OS Test User Agent");
			
			if(this.session.send_message(message) == 200) {
				try {
					Value v = Value (typeof (HashTable<string,Value?>));
					Soup.XMLRPC.parse_method_response ((string) message.response_body.flatten().data, -1, v);
					HashTable<string,Value?> vh = (HashTable<string,Value?>)v;
					
					if((string)(vh.lookup("status")) == "200 OK") {
						this.session_token = (string)(vh.lookup("token"));
						return true;
					}
				} catch (Error e) {}
			}
			
			return false;
		}
		
		public override void disconnect() {
			Soup.XMLRPC.request_new ("http://api.opensubtitles.org/xml-rpc",
					"LogOut",
					typeof(string), this.session_token);
		}
		
		public override Gee.Set<Subtitle> search(string filename, Gee.Collection<string> languages) {
			
			var subtitles_found = new Gee.HashSet<Subtitle>();
			var requests = new ValueArray(0);
			
			try {
				var file = File.new_for_path(filename);
				string codes = language_codes_string(languages);
				string hash = "%016llx".printf(this.file_hash(file));
				double size = this.file_size(file);
				HashTable<string, Value?> request = new HashTable<string, Value?>(str_hash, str_equal);
				
				request.insert("sublanguageid", codes);
				request.insert("moviehash", hash);
				request.insert("moviebytesize", size);
				
				requests.append(request);
				
				var message = Soup.XMLRPC.request_new ("http://api.opensubtitles.org/xml-rpc",
						"SearchSubtitles",
						typeof(string), this.session_token,
						typeof(ValueArray), requests);
				
				if(this.session.send_message(message) == 200) {
					Value v = Value (typeof (HashTable<string,Value?>));
					Soup.XMLRPC.parse_method_response ((string) message.response_body.flatten().data, -1, v);
					HashTable<string,Value?> vh = (HashTable<string,Value?>)v;
					
					if((string)(vh.lookup("status")) == "200 OK" && vh.lookup("data").type() != typeof(bool)) {
						foreach(Value vresult in (ValueArray)vh.lookup("data")) {
							HashTable<string,Value?> result = (HashTable<string,Value?>)vresult;
							
							Subtitle subtitle = new Subtitle(this.info, result);
							subtitle.format = (string)result.lookup("SubFormat");
							subtitle.language = (string)result.lookup("ISO639");
							subtitle.rating = double.parse((string)result.lookup("SubRating"));
							
							subtitles_found.add(subtitle);
						}
					}
				}
			} catch(Error e) {}
			
			return subtitles_found;
		}
		
		public override Subtitle? download(Subtitle subtitle) {
			var requests = new ValueArray(0);
			
			var message = Soup.XMLRPC.request_new ("http://api.opensubtitles.org/xml-rpc",
					"DownloadSubtitles",
					typeof(string), this.session_token,
					typeof(ValueArray), requests);
			
			if(this.session.send_message(message) == 200) {
				try {
					Value v = Value (typeof (HashTable<string,Value?>));
					Soup.XMLRPC.parse_method_response ((string) message.response_body.flatten().data, -1, v);
					HashTable<string,Value?> vh = (HashTable<string,Value?>)v;
					
					if((string)(vh.lookup("status")) == "200 OK" && vh.lookup("data").type() != typeof(bool)) {
						HashTable<string,Value?> result = (HashTable<string,Value?>)((ValueArray)vh.lookup("data")).get_nth(0);
						
						try {
							var data = Base64.decode((string)result.lookup("data"));
							subtitle.data = deflate_subtitle(data);
							
							return subtitle;
						} catch (Error e) {}
					}
				} catch (Error e) {}
			}
			
			return null;
		}
		
		public override Gee.MultiMap<string, Subtitle> search_multiple(Gee.Collection<string> filenames, Gee.Collection<string> languages) {
			var subtitles_found_map = new Gee.HashMultiMap<string, Subtitle>();
			var requests = new ValueArray(0);
			var hash_filename = new Gee.HashMap<string, string>();
			
			foreach (string filename in filenames) {
				try {
					var file = File.new_for_path(filename);
					string codes = language_codes_string(languages);
					string hash = "%016llx".printf(this.file_hash(file));
					double size = this.file_size(file);
					HashTable<string, Value?> request = new HashTable<string, Value?>(str_hash, str_equal);
					
					request.insert("sublanguageid", codes);
					request.insert("moviehash", hash);
					request.insert("moviebytesize", size);
					
					requests.append(request);
					
					hash_filename.set(hash, filename);
				} catch(Error e) {}
			}
			
			var message = Soup.XMLRPC.request_new ("http://api.opensubtitles.org/xml-rpc",
					"SearchSubtitles",
					typeof(string), this.session_token,
					typeof(ValueArray), requests);
		
			if(this.session.send_message(message) == 200) {
				try {
					Value v = Value (typeof (HashTable<string,Value?>));
					Soup.XMLRPC.parse_method_response ((string) message.response_body.flatten().data, -1, v);
					HashTable<string,Value?> vh = (HashTable<string,Value?>)v;
					
					if((string)(vh.lookup("status")) == "200 OK" && vh.lookup("data").type() != typeof(bool)) {
						foreach(Value vresult in (ValueArray)vh.lookup("data")) {
							HashTable<string,Value?> result = (HashTable<string,Value?>)vresult;
							
							Subtitle subtitle = new Subtitle(this.info, result);
							subtitle.format = (string)result.lookup("SubFormat");
							subtitle.language = (string)result.lookup("ISO639");
							subtitle.rating = double.parse((string)result.lookup("SubRating"));
							
							subtitles_found_map.set(hash_filename[(string)result.lookup("MovieHash")], subtitle);
						}
					}
				} catch(Error e) {}
			}
			
			return subtitles_found_map;
		}
		
		public override Gee.Set<Subtitle> download_multiple(Gee.Collection<Subtitle> subtitles) {
			var requests = new ValueArray(0);
			var subtitles_downloaded = new Gee.HashSet<Subtitle>();
			var id_map = new Gee.HashMap<string, Subtitle>();
			
			foreach(Subtitle subtitle in subtitles) {
				HashTable<string,Value?> server_data = (HashTable<string,Value?>)subtitle.server_data;
				var id = server_data.lookup("IDSubtitleFile");
				
				requests.append(id);
				
				id_map.set((string)id, subtitle);
			}
			
			var message = Soup.XMLRPC.request_new ("http://api.opensubtitles.org/xml-rpc",
					"DownloadSubtitles",
					typeof(string), this.session_token,
					typeof(ValueArray), requests);
			
			if(this.session.send_message(message) == 200) {
				try {
					Value v = Value (typeof (HashTable<string,Value?>));
					Soup.XMLRPC.parse_method_response ((string) message.response_body.flatten().data, -1, v);
					HashTable<string,Value?> vh = (HashTable<string,Value?>)v;
					
					if((string)(vh.lookup("status")) == "200 OK" && vh.lookup("data").type() != typeof(bool)) {
						foreach(Value vresult in (ValueArray)vh.lookup("data")) {
							HashTable<string,Value?> result = (HashTable<string,Value?>)vresult;
							
							try {
								var data = Base64.decode((string)result.lookup("data"));
								Subtitle subtitle = id_map[(string)result.lookup("idsubtitlefile")];
								subtitle.data = deflate_subtitle(data);
								
								subtitles_downloaded.add(subtitle);
							} catch (Error e) {}
						}
					}
				} catch (Error e) {}
			}
			
			return subtitles_downloaded;
		}
	}
	
}
