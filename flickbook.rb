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

  def photoset_info(id)
    response = @@flickr.request('photosets.getInfo', :photoset_id => id)
    title = response['photoset']['title']['$']
    description = response['photoset']['description']['$'] || ''
    description << "\n\nOriginal set available on Flickr: http://flickr.com/photos/#{@@flickr.nsid}/sets/#{id}/"

    [title, description]
  end

  def create_album(title, description)
    response = @@facebook.request('photos.createAlbum', :name => title, :description => description)
    id = response['aid']['$']
    link = response['link']['$']

    [id, link]
  end

  def photoset_photos(id)
    response = @@flickr.request('photosets.getPhotos', :photoset_id => id)
    response['photoset']['photo']
  end

  def photo_info(id)
    response = @@flickr.request('photos.getInfo', :photo_id => id)
    title = response['photo']['title']['$']
    description = response['photo']['description']['$']

    [title, description]
  end

  def upload_finished!
    @@status.clear do
      para link("Click to go to Facebook album \"#{@@title}\"", :click => @@album_link)
    end
  end

  def upload_helper(photo)
    id = photo['@id']
    filename = "#{id}_#{photo['@secret']}.jpg"
    url = "http://farm#{photo['@farm']}.static.flickr.com/#{photo['@server']}/#{filename}"
    title, description = photo_info(id)

    @@status.clear do
      flow :margin => 10 do
        image url.sub(/\.jpg$/, '_s.jpg'), :margin => 0 
        stack :width => -115, :margin => 10 do
          para title, :margin => 0
          d = inscription 'Beginning transfer', :margin => 0
          p = progress :width => 1.0, :height => 14
          download url,
            :start => proc { d.text = 'Downloading'; p.show },
            :progress => proc {|dl| p.fraction = dl.percent * 0.1 },
            :finish => proc {|dl|
              d.text = 'Uploading to Facebook'

              p.hide
              @@facebook.upload_photo(filename, dl.response.body, :aid => @@album_id, :caption => description)
              if @@photos.empty?
                upload_finished!
              else
                upload_helper(@@photos.shift)
              end
            }
        end
      end
    end
  end

  def upload(id)
    @@status = stack(:margin => 10) {}

    @@title, description = photoset_info(id)
    @@album_id, @@album_link = create_album(@@title, description)

    @@photos = photoset_photos(id)
    upload_helper(@@photos.shift)
  end
end

Shoes.app :title => 'Flickbook', :height => 450, :width => 450
