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
    class FlickrException : Exception
    {
        public FlickrException(string code, string message) :
            base(String.Format("Error code {0} - {1}", code, message))
        {
        }
    }

    public class Flickr
    {
        const string ApiKey = "01c23ff3e672e264811ab9f40d8cad47";
        const string Secret = "d32d10fb9a128089";
        const string RestUrl = "http://api.flickr.com/services/rest/";

        private string frob = null;
        private string auth_token = null;
        private string nsid = null;

        /// <summary>
        /// def request(method, params)
        ///   params[:api_key] = ApiKey
        ///   params[:method] = "flickr.#{method}"
        /// 
        ///   url = "#{RestUrl}?#{params.map {|k,v| "#{k}=#{v}" }.join('&')}"
        ///   response = Net::HTTP.get(URI.parse(url))
        ///   CobraVsMongoose.xml_to_hash(response)['rsp']
        /// end
        /// </summary>
        static XmlNode BaseRequest(string method, Dictionary<string, string> parameters)
        {
            parameters["api_key"] = ApiKey;
            parameters["method"] = String.Format("flickr.{0}", method);

            var urlParams = parameters.Select(kv => String.Format("{0}={1}", kv.Key, Uri.EscapeDataString(kv.Value))).Join("&");
            var url = String.Format("{0}?{1}", RestUrl, urlParams);

            var request = WebRequest.Create(url);

            var response = request.GetResponse();
            var responseStream = response.GetResponseStream();

            var xmlDoc = new XmlDocument();
            xmlDoc.Load(responseStream);

            var rsp = xmlDoc.SelectSingleNode("/rsp");
            var err = rsp.SelectSingleNode("err");

            if (err != null)
            {
                var code = err.Attributes.GetNamedItem("code").Value;
                var message = err.Attributes.GetNamedItem("msg").Value;
                throw new FlickrException(code, message);
            }

            return rsp;
        }

        ///<summary>
        /// def signed_request(method, params={})
        ///   params[:api_sig] = signature(params.merge({:api_key => ApiKey, :method => "flickr.#{method}"}))
        /// 
        ///   request(method, params)
        /// end
        /// </summary>
        static XmlNode SignedRequest(string method, Dictionary<string, string> parameters)
        {
            parameters["api_key"] = ApiKey;
            parameters["method"] = "flickr." + method;
            parameters["api_sig"] = Signature(parameters);

            return BaseRequest(method, parameters);
        }

        /// <summary>
        /// def signature(params)
        ///   Digest::MD5.hexdigest(Secret + params.map {|k,v| "#{k}#{CGI.unescape(v)}" }.sort.join)
        /// end
        /// </summary>
        private static string Signature(Dictionary<string, string> parameters)
        {
            var sigString = Secret + parameters.Select(kv => kv.Key + kv.Value).
                                                OrderBy(kv => kv).
                                                Join("");

            // Maybe should store instance of MD5 to avoid re-instantiating it all the time?
            return MD5.Create().Hexdigest(sigString);
        }

        /// <summary>
        /// def request(method, params)
        ///   Flickr.signed_request(method, params.merge(:auth_token => @auth_token))
        /// end
        /// </summary>
        public XmlNode Request(string method, Dictionary<string, string> parameters)
        {
            parameters["auth_token"] = auth_token;

            return SignedRequest(method, parameters);
        }

        /// <summary>
        /// def login_url
        ///   params = { :api_key => ApiKey, :perms => 'read', :frob => @frob }
        /// 
        ///   url = "http://flickr.com/services/auth/?"
        ///   url << params.map {|k,v| "#{k}=#{v}" }.join('&')
        ///   url << "&api_sig=#{Flickr.signature(params)}"
        /// 
        ///   url
        /// end
        /// </summary>
        public Uri LoginUrl
        {
            get
            {
                var rsp = SignedRequest("auth.getFrob", new Dictionary<string, string>());
                frob = rsp.SelectSingleNode("frob").InnerText;

                var parameters = new Dictionary<string, string>();
                parameters["api_key"] = ApiKey;
                parameters["perms"] = "read";
                parameters["frob"] = frob;

                var url = new StringBuilder("http://flickr.com/services/auth/?");
                url.Append(parameters.Select(kv => kv.Key + "=" + kv.Value).Join("&"));
                url.AppendFormat("&api_sig={0}", Flickr.Signature(parameters));

                return new Uri(url.ToString());
            }
        }

        /// <summary>
        /// def get_auth_token
        ///   response = Flickr.signed_request('auth.getToken', :frob => @frob)['auth']
        /// 
        ///   @auth_token = response['token']['$']
        ///   @nsid = response['user']['@nsid']
        /// end
        /// </summary>
        public void GetAuthToken()
        {
            var rsp = SignedRequest("auth.getToken", new Dictionary<string, string> { { "frob", frob } });
            var auth = rsp.SelectSingleNode("auth");

            auth_token = auth.SelectSingleNode("token").InnerText;
            nsid = auth.SelectSingleNode("user").Attributes.GetNamedItem("nsid").Value;
        }

        /// <summary>
        /// def logged_in?
        ///   !!@auth_token
        /// end
        /// </summary>
        public bool LoggedIn
        {
            get { return auth_token != null; }
        }

        public string Nsid
        {
            get { return nsid; }
        }

        public class PhotoSet
        {
            public string ID { get; set; }
            public string Title { get; set; }
            public string Description { get; set; }
        }
    }
}
