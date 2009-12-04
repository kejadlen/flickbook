using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Xml;

using Extensions;

namespace Flickbook
{
    class FacebookException : Exception
    {
        public FacebookException(string code, string message) :
            base(String.Format("Error code {0} - {1}", code, message))
        {
        }
    }

    public class Facebook
    {
        const string ApiKey = "76f0e8ed0eba10f3c3fe749185c07b89";
        const string Secret = "4a87ff67dc5ce80671077a1e8a755d10";
        const string RestUrl = "http://api.facebook.com/restserver.php";
        const string Boundary = "zfLad5QPM0UOMd2NR6vHHA";

        private string sessionSecret = null;
        private string sessionKey = null;

        private XmlNamespaceManager nsmgr = null;

        /// <summary>
        /// def base_request(method, params={}, secret=Secret)
        ///   params = params.inject({}) do |n,(k,v)|
        ///     n[k] = CGI.escape(v)
        ///     n
        ///   end
        /// 
        ///   params[:method] = "facebook.#{method}"
        ///   params[:api_key] = ApiKey
        ///   params[:v] = '1.0'
        /// 
        ///   url = "#{RestUrl}?"
        ///   url << params.map {|k,v| "#{k}=#{v}" }.join('&')
        ///   url << "&sig=#{signature(params, secret)}"
        /// 
        ///   response = Net::HTTP.get(URI.parse(url))
        ///   response_key = "#{method.sub('.', '_')}_response"
        /// 
        ///   CobraVsMongoose.xml_to_hash(response)[response_key]
        /// end
        /// </summary>
        public XmlNode BaseRequest(string method, Dictionary<string, string> parameters)
        {
            parameters["method"] = String.Format("facebook.{0}", method);
            parameters["api_key"] = ApiKey;
            parameters["v"] = "1.0";

            var url = new StringBuilder(RestUrl);
            url.Append("?");
            url.Append(parameters.Select(kv => String.Format("{0}={1}", kv.Key, Uri.EscapeDataString(kv.Value))).Join("&"));
            url.AppendFormat("&sig={0}", Signature(parameters));

            var request = WebRequest.Create(url.ToString());

            var response = request.GetResponse();
            var responseStream = response.GetResponseStream();

            var xmlDoc = new XmlDocument();
            xmlDoc.Load(responseStream);

            nsmgr = new XmlNamespaceManager(xmlDoc.NameTable);
            nsmgr.AddNamespace("fb", xmlDoc.DocumentElement.NamespaceURI);

            if (xmlDoc.SelectSingleNode("fb:error_response", nsmgr) != null)
            {
                var code = xmlDoc.SelectSingleNode("fb:error_code", nsmgr).InnerText;
                var message = xmlDoc.SelectSingleNode("fb:error_msg", nsmgr).InnerText;

                throw new FacebookException(code, message);
            }
            
            var responseKey = String.Format("fb:{0}_response", method.Replace('.', '_'));

            return xmlDoc.SelectSingleNode(responseKey, nsmgr);
        }

        /// <summary>
        /// def request(method, params)
        ///   params[:call_id] = Time.now.to_f.to_s
        ///   params[:session_key] = @session_key
        ///   
        ///   Facebook::base_request(method, params, @secret)
        /// end
        /// </summary>
        public XmlNode Request(string method, Dictionary<string, string> parameters)
        {
            parameters["call_id"] = DateTime.Now.Ticks.ToString();
            parameters["session_key"] = sessionKey;

            return BaseRequest(method, parameters);
        }

        /// <summary>
        /// def signature(params, secret=Secret)
        ///   Digest::MD5.hexdigest(params.map {|k,v| "#{k}=#{CGI.unescape(v)}" }.sort.join + secret)
        /// end
        /// </summary>
        string Signature(Dictionary<string, string> parameters)
        {
            var sigString = parameters.Select(kv => String.Format("{0}={1}", kv.Key, kv.Value)).
                                       OrderBy(kv => kv).
                                       Join("");
            sigString += sessionSecret ?? Secret;

            // Maybe should store instance of MD5 to avoid re-instantiating it all the time?
            return MD5.Create().Hexdigest(sigString);
        }

        /// <summary>
        /// def upload_photo(filename, raw_data, params)
        ///   params[:method] = "facebook.photos.upload"
        ///   params[:api_key] = ApiKey
        ///   params[:v] = '1.0'
        ///   params[:call_id] = Time.now.to_f.to_s
        ///   params[:session_key] = @session_key
        ///   params[:sig] = Facebook::signature(params, @secret)
        /// 
        ///   headers = { 'Content-Type' => "multipart/form-data; boundary=#{Boundary}" }
        /// 
        ///   message = "MIME-version: 1.0\r\n\r\n--#{Boundary}\r\n"
        /// 
        ///   params.each do |k,v|
        ///     message << "Content-Disposition: form-data; name=\"#{k}\"\r\n\r\n"
        ///     message << "#{v}\r\n"
        ///     message << "--#{Boundary}\r\n"
        ///   end
        /// 
        ///   message << "Content-Disposition: form-data; filename=\"#{filename}.jpg\"\r\n"
        ///   message << "Content-Type: image/jpg\r\n\r\n"
        ///   message << raw_data << "\r\n"
        ///   message << "--#{Boundary}\r\n"
        /// 
        ///   http = Net::HTTP.new(URI.parse(RestUrl).host)
        ///   response = http.post(URI.parse(RestUrl).path, message, headers)
        /// end
        /// </summary>
        public void UploadPhoto(string filename, Stream stream, Dictionary<string, string> parameters)
        {
            parameters["method"] = "facebook.photos.upload";
            parameters["api_key"] = ApiKey;
            parameters["v"] = "1.0";
            parameters["call_id"] = DateTime.Now.Ticks.ToString();
            parameters["session_key"] = sessionKey;
            parameters["sig"] = Signature(parameters);

            var message = new StringBuilder("MIME-version: 1.0\r\n\r\n");
            message.AppendFormat("--{0}\r\n", Boundary);

            foreach (var kv in parameters)
            {
                message.AppendFormat("Content-Disposition: form-data; name=\"{0}\"\r\n\r\n", kv.Key);
                message.AppendFormat("{0}\r\n", kv.Value);
                message.AppendFormat("--{0}\r\n", Boundary);
            }

            message.AppendFormat("Content-Disposition: form-data; filename=\"{0}\"\r\n", filename);
            message.Append("Content-Type: image/jpg\r\n\r\n");
            message.Append((new StreamReader(stream)).ReadToEnd());
            message.Append("\r\n");
            message.AppendFormat("--{0}\r\n", Boundary);

            var request = WebRequest.Create(RestUrl);
            request.Method = "POST";
            request.ContentType = String.Format("multipart/form-data; boundary={0}", Boundary);
            // request.ContentLength = message.Length;

            var sw = request.GetRequestStream();
            sw.Write((new ASCIIEncoding()).GetBytes(message.ToString()), 0, message.Length);
            sw.Close();

            var rsp = request.GetResponse();

            var xmlDoc = new XmlDocument();
            xmlDoc.Load(rsp.GetResponseStream());
        }

        /// <summary>
        /// def login_url
        ///   LoginUrl << "&auth_token=" << @auth_token
        /// end
        /// </summary>
        public Uri LoginUrl
        {
            get
            {
                var url = new StringBuilder("http://www.facebook.com/login.php?");
                url.AppendFormat("api_key={0}", ApiKey);
                url.Append("&v=1.0");
                url.Append("&next=http://www.facebook.com/connect/login_success.html");
                url.Append("&cancel_url=http://www.facebook.com/connect/login_failure.html");
                url.Append("&fbconnect=true&return_session=true&session_key_only=true");
                url.Append("&req_perms=photo_upload");

                return new Uri(url.ToString()); ;
            }
        }

        /// <summary>
        /// def logged_in?
        ///   !!@session_key
        /// end
        /// </summary>
        public bool LoggedIn
        {
            get { return sessionKey != null; }
        }

        public string SessionKey
        {
            set { sessionKey = value; }
        }

        public string SessionSecret
        {
            set { sessionSecret = value; }
        }

        public XmlNamespaceManager NSMgr
        {
            get { return nsmgr; }
        }
    }
}
