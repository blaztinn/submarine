namespace Submarine {
	
	private class OpenSubtitlesServer : SubtitleServer {
		private Soup.SessionSync session;
		private string session_token;
		
		private const string XMLRPC_URI = "http://api.opensubtitles.org/xml-rpc";
		
		private Gee.HashSet<string> supported_languages;
		
		construct {
			this.info = ServerInfo("OpenSubtitles",
					"http://www.opensubtitles.org",
					"os");
		}
		
		private bool get_supported_languages() {
			HashTable<string,Value?> vh;
			
			this.supported_languages = new Gee.HashSet<string>();
			
			var message = Soup.XMLRPC.request_new (XMLRPC_URI,
				"GetSubLanguages",
				typeof(string), this.session_token);
			
			if(XMLRPC.call(this.session, message, out vh)) {
				unowned ValueArray va = (ValueArray) vh.lookup("data");
			
				foreach(Value vresult in va) {
					HashTable<string,Value?> result = (HashTable<string,Value?>)vresult;
					
					this.supported_languages.add((string)result.lookup("SubLanguageID"));
				}
				
				return true;
			}
			
			return false;
		}
		
		private string language_codes_string(Gee.Collection<string> languages) {
			var languages_set = new Gee.HashSet<string>();
			
			if(this.supported_languages == null) {
				this.get_supported_languages();
			}
			
			foreach(var language in languages) {
				var language_info = get_language_info(language);
				
				//opensubtitles.net supports only long codes
				if(language_info.long_code in supported_languages) {
					languages_set.add(language_info.long_code);
				}
				if(language_info.long_code_alt != null && language_info.long_code_alt in supported_languages) {
					languages_set.add(language_info.long_code_alt);
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
		
		private string inflate_subtitle(uint8[] data) throws IOError{
			var src_stream = new MemoryInputStream.from_data(data, null);
			var dst_stream = new MemoryOutputStream(null, GLib.realloc, GLib.free);
			var conv_stream = new ConverterOutputStream (dst_stream, new ZlibDecompressor(ZlibCompressorFormat.GZIP));
			
			conv_stream.splice(src_stream, 0);
			
			return (string)dst_stream.get_data();
		}
		
		public override bool connect() {
			const string username = "";
			const string password = "";
			HashTable<string, Value?> vh;
			this.session = new Soup.SessionSync();
			
			var message = Soup.XMLRPC.request_new (XMLRPC_URI,
					"LogIn",
					typeof(string), username,
					typeof(string), password, 
					typeof(string), "",
					typeof(string), "OS Test User Agent");
			
			if(XMLRPC.call(this.session, message, out vh) && (string)(vh.lookup("status")) == "200 OK") {
				this.session_token = (string)(vh.lookup("token"));
				return true;
			}
			
			return false;
		}
		
		public override void disconnect() {
			Soup.XMLRPC.request_new (XMLRPC_URI,
					"LogOut",
					typeof(string), this.session_token);
		}
		
		//Note: search() not implemented, because there is minimal improvement over search_multiple()
		
		public override Gee.MultiMap<File, Subtitle> search_multiple(Gee.Collection<File> files, Gee.Collection<string> languages) {
			var subtitles_found_map = new Gee.HashMultiMap<File, Subtitle>();
			var requests = new Gee.ArrayList<Value?>();
			var hash_file = new Gee.HashMap<string, File>();
			
			//maximum response results is 500
			const int MAX = 500;
			//assume 5 hits per subtitle
			const int HITS = 5;
			
			string codes = language_codes_string(languages);
			foreach (var file in files) {
				try {
					string hash = "%016llx".printf(this.file_hash(file));
					double size = this.file_size(file);
					HashTable<string, Value?> request = new HashTable<string, Value?>(str_hash, str_equal);
					
					request.insert("sublanguageid", codes);
					request.insert("moviehash", hash);
					request.insert("moviebytesize", size);
					
					requests.add(request);
					
					hash_file.set(hash, file);
				} catch(Error e) {}
			}
			
			SubtitleServer.BatchRequestMethod request_method = (request_batch) => {
				var values = new ValueArray(request_batch.size);
				
				foreach(var request in request_batch) {
					values.append(request);
				}
				
				
				var message = Soup.XMLRPC.request_new (XMLRPC_URI,
						"SearchSubtitles",
						typeof(string), this.session_token,
						typeof(ValueArray), values);
				
				Value v;
				if(XMLRPC.call(this.session, message, out v) && (string)((HashTable<string,Value?>)v).lookup("status") == "200 OK") {
					return v;
				}
				
				return null;
			};
			
			SubtitleServer.BatchResponseMethod response_method = (response) => {
				HashTable<string,Value?> vh = (HashTable<string,Value?>)response;
				int results = 0;
				
				if(vh.lookup("data").type() != typeof(bool)) {
					unowned ValueArray va = (ValueArray)((HashTable<string,Value?>)response).lookup("data");
						
					foreach(Value vresult in va) {
						HashTable<string,Value?> result = (HashTable<string,Value?>)vresult;
						
						Subtitle subtitle = new Subtitle(this.info, result);
						subtitle.format = (string)result.lookup("SubFormat");
						subtitle.language = (string)result.lookup("ISO639");
						subtitle.rating = double.parse((string)result.lookup("SubRating"));
						
						subtitles_found_map.set(hash_file[(string)result.lookup("MovieHash")], subtitle);
						
						results++;
					}
				}
				
				return results;
			};
			
			this.batch_process(requests, request_method, response_method, MAX/HITS, MAX);
			
			return subtitles_found_map;
		}
		
		//Note: download() not implemented, because there is minimal improvement over download_multiple()
		
		public override Gee.Set<Subtitle> download_multiple(Gee.Collection<Subtitle> subtitles) {
			var subtitles_downloaded = new Gee.HashSet<Subtitle>();
			var requests = new Gee.ArrayList<Value?>();
			var id_map = new Gee.HashMap<string, Subtitle>();
			
			foreach(Subtitle subtitle in subtitles) {
				HashTable<string,Value?> server_data = (HashTable<string,Value?>)subtitle.server_data;
				var id = server_data.lookup("IDSubtitleFile");
				
				requests.add(id);
				
				id_map.set((string)id, subtitle);
			}
			
			//maximum response results is 500
			const int MAX = 500;
			
			SubtitleServer.BatchRequestMethod request_method = (request_batch) => {
				var values = new ValueArray(request_batch.size);
				
				foreach(var request in request_batch) {
					values.append(request);
				}
				
				
				var message = Soup.XMLRPC.request_new (XMLRPC_URI,
						"DownloadSubtitles",
						typeof(string), this.session_token,
						typeof(ValueArray), values);
				
				Value v;
				if(XMLRPC.call(this.session, message, out v) && (string)((HashTable<string,Value?>)v).lookup("status") == "200 OK") {
					return v;
				}
				
				return null;
			};
			
			SubtitleServer.BatchResponseMethod response_method = (response) => {
				HashTable<string,Value?> vh = (HashTable<string,Value?>)response;
				int results = 0;
				
				if(vh.lookup("data").type() != typeof(bool)) {
					unowned ValueArray va = (ValueArray)((HashTable<string,Value?>)response).lookup("data");
						
					foreach(Value vresult in va) {
						HashTable<string,Value?> result = (HashTable<string,Value?>)vresult;
						
						try {
							var data = Base64.decode((string)result.lookup("data"));
							Subtitle subtitle = id_map[(string)result.lookup("idsubtitlefile")];
							subtitle.data = inflate_subtitle(data);
							
							subtitles_downloaded.add(subtitle);
						} catch (Error e) {}
						
						results++;
					}
				}
				
				return results;
			};
			
			this.batch_process(requests, request_method, response_method, MAX);
			
			return subtitles_downloaded;
		}
	}
	
}
