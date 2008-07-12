require 'base64'

module Camping
  module CookieSessions
    # this thingy wraps around the main thingy and puts sessions in like magic, ooooOOOOOooooh! Spooky!
    def service(*a)
      if @cookies.identity
        blob, secure_hash = @cookies.identity.to_s.split(':', 2)
        blob = Base64.decode64(blob)
        data = Marshal.restore(blob)
        data = {} unless secure_blob_hasher(blob).strip.downcase == secure_hash.strip.downcase
      else
        blob = ''
        data = {}
      end
      
      app = self.class.name.gsub(/^(\w+)::.+$/, '\1')
      @state = (data[app] ||= Camping::H[])
      hash_before = blob.hash
      return super(*a)
    ensure
      data[app] = @state
      blob = Marshal.dump(data)
      unless hash_before == blob.hash
        secure_hash = secure_blob_hasher(blob)
        @cookies.identity = Base64.encode64(blob).gsub("\n", '').strip + ':' + secure_hash
        # hack to make cookies update
        @headers['Set-Cookie'] = @cookies.map { |k,v| "#{k}=#{C.escape(v)}; path=#{self/"/"}" if v != @k[k] } - [nil]
      end
    end
    
    # You can override this with whatever hashing function you think is awesome enough, don't use MD5 though! It stinks!
    def secure_blob_hasher(data)
      require 'digest'
      require 'digest/sha2'
      Digest::SHA512::hexdigest(self.class.module_eval('@@state_secret') + data)
    end
  end
end
