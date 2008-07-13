#!/usr/bin/env ruby

require 'digest/md5'
require 'net/http'
require 'net/https'

require 'camping'
require 'cookie_sessions'
require 'cobravsmongoose'

Camping.goes :FlickBook

module Flickr
  ApiKey = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
  Secret = 'XXXXXXXXXXXXXXXX'
  RestUrl = 'http://api.flickr.com/services/rest/'

  class << self
    def request(method, params)
      params[:api_key] = ApiKey
      params[:method] = "flickr.#{method}"

      url = "#{RestUrl}?#{params.map {|k,v| "#{k}=#{v}" }.join('&')}"

      response = Net::HTTP.get(URI.parse(url))
      CobraVsMongoose.xml_to_hash(response)['rsp']
    end

    def signed_request(method, params)
      params[:api_sig] = signature(params.merge({ :api_key => ApiKey, :method => "flickr.#{method}"}))

      request(method, params)
    end

    def login_url
      params = { :api_key => ApiKey, :perms => 'read' }

      url = "http://flickr.com/services/auth/?"
      url << params.map {|k,v| "#{k}=#{v}" }.join('&')
      url << "&api_sig=#{signature(params)}"

      url
    end

    def signature(params)
      Digest::MD5.hexdigest(Secret + params.map {|k,v| "#{k}#{Camping.un(v)}" }.sort.join)
    end
  end
end

class Facebook
  ApiKey = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
  Secret = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
  RestUrl = 'http://api.facebook.com/restserver.php'
  LoginUrl = "http://www.facebook.com/login.php?api_key=#{ApiKey}&v=1.0&hide_checkbox=1"
  Boundary = 'zfLad5QPM0UOMd2NR6vHHA'

  class << self
    def get_session(auth_token)
      response = base_request('auth.getSession', :auth_token => auth_token)
      Facebook.new(response['session_key']['$'])
    end

    def base_request(method, params)
      params = params.inject({}) do |n,(k,v)|
        n[k] = Camping.escape(v)
        n
      end

      params[:method] = "facebook.#{method}"
      params[:api_key] = ApiKey
      params[:v] = '1.0'

      url = "#{RestUrl}?"
      url << params.map {|k,v| "#{k}=#{v}" }.join('&')
      url << "&sig=#{signature(params)}"

      response = Net::HTTP.get(URI.parse(url))
      response_key = "#{method.sub('.', '_')}_response"

      CobraVsMongoose.xml_to_hash(response)[response_key]
    end

    def signature(params)
      Digest::MD5.hexdigest(params.map {|k,v| "#{k}=#{Camping.un(v)}" }.sort.join + Secret)
    end
  end

  def initialize(session_key)
    @session_key = session_key
  end

  def request(method, params)
    params[:call_id] = Time.now.to_f.to_s
    params[:session_key] = @session_key

    Facebook::base_request(method, params)
  end

  def upload_photo(filename, raw_data, params)
    params[:method] = "facebook.photos.upload"
    params[:api_key] = ApiKey
    params[:v] = '1.0'
    params[:call_id] = Time.now.to_f.to_s
    params[:session_key] = @session_key
    params[:sig] = Facebook::signature(params)

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

module FlickBook
  include Camping::CookieSessions
  @@state_secret = 'ZkNZRyTxiZsOQe6VS+Tb5Q=='
end

module FlickBook::Controllers
  class Index < R '/'
    def get
      redirect Facebook::LoginUrl
    end
  end

  class FacebookLogin < R '/login/facebook'
    def get
      @state[:facebook] = Facebook::get_session(input.auth_token)

      redirect Flickr::login_url
      #render :flickr_login
    end
  end

  class FlickrLogin < R '/login/flickr'
    def get
      response = Flickr::signed_request('auth.getToken', :frob => input.frob)
      nsid = response['auth']['user']['@nsid']

      response = Flickr::request('photosets.getList', :user_id => nsid)
      @photosets = response['photosets']['photoset'][0..10]

      render :photosets
    end
  end

  class Upload < R '/upload/(\d+)'
    def get id
      response = Flickr::request('photosets.getInfo', :photoset_id => id)
      title = response['photoset']['title']['$']
      description = response['photoset']['description']['$']

      response = @state[:facebook].request('photos.createAlbum', :name => title, :description => description)
      album_id = response['aid']['$']
      album_link = response['link']['$']
      
      response = Flickr::request('photosets.getPhotos', :photoset_id => id)
      response['photoset']['photo'].each do |photo|
        filename = "#{photo['@id']}_#{photo['@secret']}.jpg"
        url = "http://farm#{photo['@farm']}.static.flickr.com/#{photo['@server']}/#{filename}"
        raw_data = Net::HTTP.get(URI.parse(url))

        info = Flickr::request('photos.getInfo', :photo_id => photo['@id'])['photo']
        description = info['description']['$']

        puts "Uploading #{filename}..."
        @state[:facebook].upload_photo(filename, raw_data, :aid => album_id, :caption => description)
      end

      redirect album_link
    end
  end
end

module FlickBook::Views
  def layout
    html do
      title { 'FlickBook' }
      body { self << yield }
    end
  end

  def flickr_login
    form :action => R(User), :method => 'post' do
      label 'Flickr username', :for => 'username'; br
      input :name => 'username', :type => 'text'; br
      input :type => 'submit', :value => 'Submit'
    end
  end

  def photosets
    h3 'Choose a photoset to upload to Facebook'

    ul do
      @photosets.each do |photoset|
        li do
          a photoset['title']['$'], :href => R(Upload, photoset['@id'])
        end
      end
    end
  end
end
