namespace Submarine {
	
	private class XMLRPC {
		public static bool call(Soup.Session session, Soup.Message message, out HashTable<string,Value?>? vhash, out uint status_code = null) {
			vhash = null;
			status_code = session.send_message(message);
			
			if(status_code == 200) {
				try {
					Value v = Value (typeof (HashTable<string,Value?>));
					if(Soup.XMLRPC.parse_method_response ((string) message.response_body.flatten().data, -1, out v))
					{
						vhash =  (HashTable<string,Value?>)v;
						return true;
					}
				} catch (Error e) {}
			}
			
			return false;
		}
	}
	
}
