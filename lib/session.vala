namespace Submarine {
	
	public class Session : Object {
		private Gee.Map<string, SubtitleServer> sub_server_map = new Gee.HashMap<string, SubtitleServer>();
		private Gee.Set<string> connected_servers = new Gee.HashSet<string>();
		
		public Session() {
			var all_servers = new Gee.HashSet<SubtitleServer>();
			
			all_servers.add_all(get_servers());
			
			foreach(var sub_server in all_servers) {
				this.sub_server_map.set(sub_server.code, sub_server);
			}
		}
		
		~Session() {
			foreach(var sub_server in this.sub_server_map.values) {
				sub_server.disconnect();
			}
		}
		
		public bool server_connect(string server_code) {
			if(this.sub_server_map.has_key(server_code)) {
				if(this.connected_servers.contains(server_code)) {
					this.server_disconnect(server_code);
				}
				
				if(this.sub_server_map[server_code].connect()) {
					this.connected_servers.add(server_code);
					return true;
				}
			}
			
			return false;
		}
		
		public Gee.Set<string> server_connect_multiple(Gee.Collection<string> server_codes = new Gee.HashSet<string>()) {
			var servers_connected = new Gee.HashSet<string>();
			
			server_codes = server_codes.is_empty ? this.sub_server_map.keys : server_codes;
			foreach(var server_code in server_codes) {
				if(this.server_connect(server_code)) {
					servers_connected.add(server_code);
				}
			}
			
			return servers_connected;
		}
		
		public void server_disconnect(string server_code) {
			if(this.connected_servers.contains(server_code)) {
				this.sub_server_map[server_code].disconnect();
				this.connected_servers.remove(server_code);
			}
		}
		
		public void server_disconnect_multiple(Gee.Collection<string> server_codes = new Gee.HashSet<string>()) {
			server_codes = server_codes.is_empty ? this.connected_servers : server_codes;
			foreach(var server_code in server_codes) {
				this.server_disconnect(server_code);
			}
		}
		
		public Gee.Set<Subtitle> subtitle_search(string filename, Gee.Collection<string> languages) {
			var subtitles_found = new Gee.HashSet<Subtitle>();
			var file = File.new_for_path(filename);
			
			if(file.query_exists()) {
				foreach(var server_code in this.connected_servers) {
					subtitles_found.add_all(this.sub_server_map[server_code].search(file, languages));
				}
			}
			
			return subtitles_found;
		}
		
		public Gee.MultiMap<string, Subtitle> subtitle_search_multiple(Gee.Collection<string> filenames, Gee.Collection<string> languages) {
			var subtitles_found_map = new Gee.HashMultiMap<string, Subtitle>();
			var files = new Gee.HashSet<File>();
			var file_filename = new Gee.HashMap<File, string>();
			
			foreach(var filename in filenames) {
				var file = File.new_for_path(filename);
				
				if(file.query_exists()) {
					files.add(file);
					file_filename.set(file, filename);
				}
			}
			
			foreach(var server_code in this.connected_servers) {
				var file_subtitle_map = this.sub_server_map[server_code].search_multiple(files, languages);
				foreach(var key in file_subtitle_map.get_keys()) {
					foreach(var subtitle in file_subtitle_map[key]) {
						subtitles_found_map.set(file_filename[key], subtitle);
					}
				}
			}
			
			return subtitles_found_map;
		}
		
		public Subtitle? subtitle_download(Subtitle subtitle) {
			if(this.connected_servers.contains(subtitle.server_info.code)) {
				return this.sub_server_map[subtitle.server_info.code].download(subtitle);
			} else {
				return null;
			}
		}
		
		public Gee.Set<Subtitle> subtitle_download_multiple(Gee.Collection<Subtitle> subtitle_set) {
			var subtitles_downloaded = new Gee.HashSet<Subtitle>();
			var subtitle_map = new Gee.HashMultiMap<string, Subtitle>();
			
			foreach(var subtitle in subtitle_set) {
				if(this.connected_servers.contains(subtitle.server_info.code)) {
					subtitle_map.set(subtitle.server_info.code, subtitle);
				}
			}
			
			foreach(var key in subtitle_map.get_keys()) {
				subtitles_downloaded.add_all(this.sub_server_map[key].download_multiple(subtitle_map[key]));
			}
			
			return subtitles_downloaded;
		}
		
	}
	
}
