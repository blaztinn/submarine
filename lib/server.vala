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
		public abstract Gee.Set<Subtitle> search(File file, Gee.Collection<string> languages);
		public abstract Subtitle? download(Subtitle subtitle);
		
		public virtual Gee.MultiMap<File, Subtitle> search_multiple(Gee.Collection<File> files, Gee.Collection<string> languages) {
			var subtitles_found_map = new Gee.HashMultiMap<File, Subtitle>();
			
			foreach(var file in files) {
				foreach(var subtitle in this.search(file, languages)) {
					subtitles_found_map.set(file, subtitle);
				}
			}
			
			return subtitles_found_map;
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
	}
	
	private Gee.List<string> all_server_codes = null;
	private Gee.Map<string, ServerInfo?> server_infos = null;
	
	private Gee.Set<SubtitleServer> get_servers() {
		var all_servers = new Gee.HashSet<SubtitleServer>();
		
		all_servers.add(new OpenSubtitlesServer());
		
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
