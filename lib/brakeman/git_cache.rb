module Brakeman
  class GitCache
    def self.client
      @client ||= Dalli::Client.new(nil, {namespace: "worker", compress: true})
    end

    def self.get(key, &block)
      client.fetch(key, &block)
    end
  end
end
