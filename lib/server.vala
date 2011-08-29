namespace Submarine {
	
	public struct ServerInfo{
		public string name { get; private set; }
		public string address { get; private set; }
		public string code { get; private set; }
		
		public ServerInfo(string name, string address, string code) {
			this.name = name;
			this.address = address;
			this.code = code;
		}
	}
	
	private abstract class SubtitleServer : Object {
		
		public ServerInfo info { get; protected set; }
		
		public string name {
			get { return this.info.name; }
		}
		public string address {
			get { return this.info.address; }
		}
		public string code {
			get { return this.info.code; }
		}
		
		public abstract new bool connect();
		public abstract new void disconnect();
		
		//Note: Children of this class must override at least one of the next two functions!
		public virtual Gee.Set<Subtitle> search(File file, Gee.Collection<string> languages) {
			var subtitles_found = new Gee.HashSet<Subtitle>();
			
			var files = new Gee.HashSet<File>();
			files.add(file);
			
			var subtitles_found_map = this.search_multiple(files, languages);
			
			if(file in subtitles_found_map) {
				subtitles_found.add_all(subtitles_found_map[file]);
			}
			
			return subtitles_found;
		}
		
		public virtual Gee.MultiMap<File, Subtitle> search_multiple(Gee.Collection<File> files, Gee.Collection<string> languages) {
			var subtitles_found_map = new Gee.HashMultiMap<File, Subtitle>();
			
			foreach(var file in files) {
				foreach(var subtitle in this.search(file, languages)) {
					subtitles_found_map.set(file, subtitle);
				}
			}
			
			return subtitles_found_map;
		}
		
		//Note: Children of this class must override at least one of the next two functions!
		public virtual Subtitle? download(Subtitle subtitle) {
			var subtitles = new Gee.HashSet<Subtitle>();
			subtitles.add(subtitle);
			
			var subtitles_downloaded = this.download_multiple(subtitles);
			
			if(!subtitles_downloaded.is_empty) {
				var it = subtitles_downloaded.iterator();
				it.next();
				return it.get();
			}
			
			return null;
		}
		
		public virtual Gee.Set<Subtitle> download_multiple(Gee.Collection<Subtitle> subtitles) {
			var subtitles_downloaded = new Gee.HashSet<Subtitle>();
			
			foreach(Subtitle subtitle in subtitles) {
				var subtitle_downloaded = this.download(subtitle);
				if(subtitle_downloaded != null) {
					subtitles_downloaded.add(subtitle_downloaded);
				}
			}
			
			return subtitles_downloaded;
		}
		
		protected delegate Value? BatchRequestMethod(Gee.List<Value?> request_batch);
		protected delegate int BatchResponseMethod(Value response);
		protected Gee.ArrayList<Value?> batch_request(Gee.List<Value?> requests, BatchRequestMethod request_method, BatchResponseMethod response_method, int max_request_size, int max_response_size = 0)
			requires (max_request_size > 0)
			requires (max_response_size >= 0)
		{
			var batch_size = max_request_size;
			var responses = new Gee.ArrayList<Value?>();
			max_response_size = max_response_size > 0 ? max_response_size : max_request_size;
			
			var request_index = 0;
			while(request_index < requests.size) {
				batch_size = requests.size-request_index < batch_size ? requests.size-request_index : batch_size;
				var requests_batch = new Gee.ArrayList<Value?>();
				
				for(int i = request_index; i < request_index+batch_size; i++) {
					requests_batch.add(requests[i]);
				}
				
				Value? response = request_method(requests);
				
				bool advance = true;
				if(response != null) {
					int results = response_method(response);
					
					if(results < max_response_size || batch_size == 1) {
						responses.add(response);
					} else {
						batch_size /= 2;
						batch_size = batch_size > 0 ? batch_size : 1;
						advance = false;
					}
				}
				
				if(advance) {
					request_index += batch_size;
				}
			}
			
			return responses;
		}
	}
	
	private Gee.List<string> all_server_codes = null;
	private Gee.Map<string, ServerInfo?> server_infos = null;
	
	private Gee.Set<SubtitleServer> get_servers() {
		var all_servers = new Gee.HashSet<SubtitleServer>();
		
		all_servers.add(new OpenSubtitlesServer());
		all_servers.add(new PodnapisiServer());
		
		return all_servers.read_only_view;
	}
	
	public Gee.List<string> get_server_codes() {
		if(all_server_codes == null) {
			all_server_codes = new Gee.ArrayList<string>();
			foreach(var server in get_servers()) {
				all_server_codes.add(server.info.code);
			}
			all_server_codes.sort( (a, b) => {return ((string)a).ascii_casecmp((string)b);} );
		}
		
		return all_server_codes.read_only_view;
	}
	
	public ServerInfo? get_server_info(string server_code) {
		if(server_infos == null) {
			server_infos = new Gee.HashMap<string, ServerInfo?>();
			foreach(var server in get_servers()) {
				server_infos.set(server.info.code, server.info);
			}
		}
		
		if(server_code in server_infos.keys) {
			return server_infos[server_code];
		}
		
		return null;
	}
	
}
