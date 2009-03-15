require 'flickr'
require 'facebook'

class Flickbook < Shoes
  url '/', :main
  url '/flickr/login', :flickr_login
  url '/facebook/login', :facebook_login
  url '/flickr/sets', :flickr_sets
  url '/upload/(\d+)', :upload

  @@flickr = Flickr.new
  @@facebook = Facebook.new

  def main
    visit '/flickr/login'
  end

  def flickr_login
    stack(:margin => 10) do
      subtitle strong('Flickr Authorization')
      para link('Click to Authorize', :click => @@flickr.login_url)
      button('Complete Authorization') do
        begin
          @@flickr.get_auth_token
          visit '/facebook/login'
        rescue
          alert('Fail!')
        end
      end
    end
  end

  def facebook_login
    stack(:margin => 10) do
      subtitle strong('Facebook Authorization')
      para link('Click to Authorize', :click => @@facebook.login_url)
      button('Complete Authorization') do
        begin
          @@facebook.get_session
          visit '/flickr/sets'
        rescue
          alert('Fail!')
        end
      end
    end
  end

  def flickr_sets
    photosets = Flickr.request('photosets.getList', :user_id => @@flickr.nsid)['photosets']['photoset']

    stack(:margin => 10) do
      photosets.each do |photoset|
        para link(photoset['title']['$'], :click => "/upload/#{photoset['@id']}")
      end
    end
  end

  def upload(id)
    stack(:margin => 10) do
      @log =
        stack(:margin => 10) do
          para "Uploading photos..."
        end
    end

    response = @@flickr.request('photosets.getInfo', :photoset_id => id)
    title = response['photoset']['title']['$']
    description = response['photoset']['description']['$'] || ''
    description << "\n\nOriginal set available on Flickr: http://flickr.com/photos/#{@@flickr.nsid}/sets/#{id}/"

    response = @@facebook.request('photos.createAlbum', :name => title, :description => description)
    album_id = response['aid']['$']
    album_link = response['link']['$']

    response = @@flickr.request('photosets.getPhotos', :photoset_id => id)
    response['photoset']['photo'].each do |photo|
      filename = "#{photo['@id']}_#{photo['@secret']}.jpg"
      url = "http://farm#{photo['@farm']}.static.flickr.com/#{photo['@server']}/#{filename}"
      raw_data = Net::HTTP.get(URI.parse(url))

      photo_info = @@flickr.request('photos.getInfo', :photo_id => photo['@id'])['photo']
      description = photo_info['description']['$']

      @log.clear do
        para "Uploading #{filename}..."
        image "http://farm#{photo['@farm']}.static.flickr.com/#{photo['@server']}/#{filename}".sub(/\.jpg$/, '_s.jpg')
      end

      @@facebook.upload_photo(filename, raw_data, :aid => album_id, :caption => description)
    end

    @log.clear do
      para link("#{title}", :click => album_link)
    end
  end
end

Shoes.app :title => 'Flickbook'
