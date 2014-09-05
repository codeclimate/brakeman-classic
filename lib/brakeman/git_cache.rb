module Brakeman
  class GitCache
    require "dalli"

    def self.client
      @client ||= Dalli::Client.new(nil, {namespace: "worker", compress: true})
    end

    def self.get(key, &block)
      client.get(key) || block.call
    end
  end
end
