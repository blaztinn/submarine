namespace Submarine {
	
	public class Subtitle{
		public string format { get; set; default = ""; }
		public string language { get; set; default = ""; }
		public double rating { get; set; default = 0.0; }
		public string data { get; set; default = ""; }
		
		public ServerInfo server_info {get; private set;}
		public Value server_data {get; private set;}
		
		public Subtitle(ServerInfo server_info, Value server_data) {
			this.server_info = server_info;
			this.server_data = server_data;
		}
		
		public string get_filename(string movie_filename) {
			string sub_filename = movie_filename;
			sub_filename = sub_filename.slice(0, sub_filename.last_index_of(".")+1) + this.format;
			
			return sub_filename;
		}
		
		public bool has_data {
			get {return data.length > 0;}
		}
	}
	
}
