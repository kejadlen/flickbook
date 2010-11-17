# encoding: UTF-8

require 'cgi'
require 'cobravsmongoose'
require 'digest/md5'
require 'net/http'
require 'net/https'

class Facebook
  ApiKey = '76f0e8ed0eba10f3c3fe749185c07b89'
  Secret = '4a87ff67dc5ce80671077a1e8a755d10'
  RestUrl = 'http://api.facebook.com/restserver.php'
  LoginUrl = "http://www.facebook.com/login.php?api_key=#{ApiKey}&v=1.0&hide_checkbox=1"
  Boundary = 'zfLad5QPM0UOMd2NR6vHHA'

  class << self
    def base_request(method, params={}, secret=Secret)
      params = params.inject({}) do |n,(k,v)|
        n[k] = CGI.escape(v)
        n
      end

      params[:method] = "facebook.#{method}"
      params[:api_key] = ApiKey
      params[:v] = '1.0'

      url = "#{RestUrl}?"
      url << params.map {|k,v| "#{k}=#{v}" }.join('&')
      url << "&sig=#{signature(params, secret)}"

      response = Net::HTTP.get(URI.parse(url))
      response_key = "#{method.sub('.', '_')}_response"

      CobraVsMongoose.xml_to_hash(response)[response_key]
    end

    def signature(params, secret=Secret)
      Digest::MD5.hexdigest(params.map {|k,v| "#{k}=#{CGI.unescape(v)}" }.sort.join + secret)
    end
  end

  def initialize
    @auth_token = Facebook.base_request("auth.createToken")["$"]
    @session_key = nil
  end

  def login_url
    LoginUrl << "&auth_token=" << @auth_token
  end

  def get_session
    response = Facebook.base_request('auth.getSession', :auth_token => @auth_token)
    @session_key = response['session_key']['$']
    @secret = response['secret']['$']
  end

  def logged_in?
    !!@session_key
  end

  def request(method, params)
    params[:call_id] = Time.now.to_f.to_s
    params[:session_key] = @session_key

    Facebook::base_request(method, params, @secret)
  end

  def upload_photo(filename, raw_data, params)
    params[:method] = "facebook.photos.upload"
    params[:api_key] = ApiKey
    params[:v] = '1.0'
    params[:call_id] = Time.now.to_f.to_s
    params[:session_key] = @session_key
    params[:sig] = Facebook::signature(params, @secret)

    headers = { 'Content-Type' => "multipart/form-data; boundary=#{Boundary}" }

    message = "MIME-version: 1.0\r\n\r\n--#{Boundary}\r\n"

    params.each do |k,v|
      message << "Content-Disposition: form-data; name=\"#{k}\"\r\n\r\n"
      message << "#{v}\r\n"
      message << "--#{Boundary}\r\n"
    end

    message << "Content-Disposition: form-data; filename=\"#{filename}.jpg\"\r\n"
    message << "Content-Type: image/jpg\r\n\r\n"
    message << raw_data << "\r\n"
    message << "--#{Boundary}\r\n"

    http = Net::HTTP.new(URI.parse(RestUrl).host)
    response = http.post(URI.parse(RestUrl).path, message, headers)
  end
end
