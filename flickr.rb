require "cgi"
require "cobravsmongoose"
require "digest/md5"
require "net/http"

class Flickr
  ApiKey = '01c23ff3e672e264811ab9f40d8cad47'
  Secret = 'd32d10fb9a128089'
  RestUrl = 'http://api.flickr.com/services/rest/'

  attr_reader :nsid, :username

  class << self
    def request(method, params)
      params[:api_key] = ApiKey
      params[:method] = "flickr.#{method}"

      url = "#{RestUrl}?#{params.map {|k,v| "#{k}=#{v}" }.join('&')}"
      response = Net::HTTP.get(URI.parse(url))
      CobraVsMongoose.xml_to_hash(response)['rsp']
    end

    def signed_request(method, params={})
      params[:api_sig] = signature(params.merge({:api_key => ApiKey, :method => "flickr.#{method}"}))

      request(method, params)
    end

    def signature(params)
      Digest::MD5.hexdigest(Secret + params.map {|k,v| "#{k}#{CGI.unescape(v)}" }.sort.join)
    end
  end

  def initialize
    @frob = Flickr.signed_request("auth.getFrob")["frob"]["$"]
    @auth_token = nil
  end

  def login_url
    params = { :api_key => ApiKey, :perms => 'read', :frob => @frob }

    url = "http://flickr.com/services/auth/?"
    url << params.map {|k,v| "#{k}=#{v}" }.join('&')
    url << "&api_sig=#{Flickr.signature(params)}"

    url
  end

  def get_auth_token
    response = Flickr.signed_request('auth.getToken', :frob => @frob)['auth']

    @auth_token = response['token']['$']
    @nsid = response['user']['@nsid']
    @username = response['user']['@username']
  end

  def logged_in?
    !!@auth_token
  end

  def request(method, params)
    Flickr.signed_request(method, params.merge(:auth_token => @auth_token))
  end
end
