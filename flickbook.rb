#!/usr/bin/env ruby

require 'net/http'
require 'rbconfig'
require 'tempfile'

require File.join(File.dirname(__FILE__), 'flickr')
require File.join(File.dirname(__FILE__), 'facebook')

firefox = (Config::CONFIG['host_os'] =~ /darwin/) ? 'open' : "C:\\Program Files (x86)\\Mozilla Firefox 3.5 Beta 4\\firefox.exe"

flickr = Flickr.new
facebook = Facebook.new

puts "Authorizing Flickr..."
`"#{firefox}" "#{flickr.login_url}"`
STDIN.gets

puts "Authorizing Facebook..."
`"#{firefox}" "#{facebook.login_url}"`
STDIN.gets

flickr.get_auth_token
facebook.get_session

puts "Getting photosets..."

photosets = Flickr.request('photosets.getList', :user_id => flickr.nsid)['photosets']['photoset']
ARGV.each do |arg|
  photosets = photosets.select {|photoset| photoset['title']['$'] =~ /#{arg}/i }
end

if photosets.empty?
  puts "No photosets found,"
  exit
end

if photosets.size > 1
  puts "Too many photosets; narrow your input."
  photosets.each {|photoset| puts "\t#{photoset['title']['$']}" }
  exit
end

photoset_id = photosets[0]['@id']

response = flickr.request('photosets.getInfo', :photoset_id => photoset_id)
title = response['photoset']['title']['$']
description = response['photoset']['description']['$'] || ''
description << "\n\n" unless description.empty?
description << <<DESCRIPTION
Original set available on Flickr: http://flickr.com/photos/#{flickr.username || flickr.nsid}/sets/#{photoset_id}/
DESCRIPTION

puts "Creating Facebook album..."

response = facebook.request('photos.createAlbum', :name => title, :description => description)
album_id = response['aid']['$']
album_link = response['link']['$']

puts "Getting photos..."

response = flickr.request('photosets.getPhotos', :photoset_id => photoset_id, :media => 'photos')
photos = response['photoset']['photo']

photos.each do |photo|
  photo_id = photo['@id']
  filename = "#{photo_id}_#{photo['@secret']}_z.jpg"

  response = flickr.request('photos.getInfo', :photo_id => photo_id)
  title = response['photo']['title']['$']
  description = response['photo']['description']['$'] || ''
  description << "\n\n" unless description.empty?
  description << "High-resolution available on Flickr: http://flickr.com/photos/#{flickr.username || flickr.nsid}/#{photo_id}/lightbox\n\n"
  description << "This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License: http://creativecommons.org/licenses/by-nc-sa/3.0/"

  puts "\nDownloading #{title} from Flickr..."

  response = Net::HTTP.get("farm#{photo['@farm']}.static.flickr.com", "/#{photo['@server']}/#{filename}")

  puts "Uploading to Facebook..."

  facebook.upload_photo(filename, response, :aid => album_id, :caption => description)
end

puts "Opening album in Firefox..."

`"#{firefox}" "#{album_link}"`
