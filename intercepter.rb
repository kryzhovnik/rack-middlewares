# Rack::Intercepter middleware helps when you need to intercept a certain request and
# return specific status code for it.
# 
# This piece of code was written when the author needed to handle a couple of
# exceptional temporal cases, which was not suited the app business logic even as an exception.
# 
# Interception described in the rules table:
# 
#     [method, url, status, headers, body]
# 
# Example:
# 
#     config.middleware.use Rack::Intercepter, [
#       ['GET', 'https://abc.domain.com/path?param=value', 404]
#       ['GET', 'https://abc.domain.com/path?param=value', 302, { 'Location' => https://abc.domain.com/param/value }]
#       ['GET', 'https://abc.domain.com/path?param=value', 403, {}, "Forbidden"]
#     ]
# 
# This implementation has a specific feature: matching url ignoring second-level domain-name,
# i.e. the following lines will pass the matching:
# 
#     https://abc.domain.com/path и
#     https://abc.domain.local/path
# 
# It made this way to have single rules for all the environments: dev, staging, and production.

module Rack
  class Intercepter
    def initialize(app, rules)
      @app = app

      @rules = case rules
      when Array then items.map { |i| Item.new(*i) }
      when Item  then items
      else
        raise ArgumentError
      end
    end

    def call(env)
      request = Rack::Request.new(env)
      request_url = FuzzyURI.new(url)

      item = @items.find do |item|
        item.method == method && FuzzyURI.new(item.url) == request_url
      end

      if item
        [item.status, item.headers, [item.body]]
      else
        @app.call(env)
      end
    end

    def find_interception(method, url)

    end

    Item = Struct.new(:method, :url, :status, :headers, :body) do
      def headers
        @headers || {}
      end

      def body
        if body
          body
        else
          "STATUS #{status}"
        end
      end
    end

    class FuzzyURI
      SUBDOMAIN_REGEXP = /\A([\w\-]+)\.\w+\.\w+/

      attr_reader :url

      def initialize(url)
        @url = URI(url)
      end

      def ==(another_url)
        same_schema?(another_url) && \
        same_subdomain?(another_url) && \
        same_path?(another_url) && \
        same_query?(another_url)
      end

      protected
        def schema
          url.schema
        end

        def host
          url.host
        end

        def query
          String(url.query)
        end

        def path
          url.path
        end

        def same_schema?(another_url)
          schema == another_url.schema
        end

        def same_subdomain?(another_url)
          extract_subdomain(host) == extract_subdomain(another_url.host)
        end

        def same_path?(another_url)
          path == another_url.path
        end

        def same_query?(another_url)
          CGI.parse(query) == CGI.parse(another_url.query)
        end

        def extract_subdomain(host)
          matched = host.match(SUBDOMAIN_REGEXP)
          Array(matched)[1]
        end
    end
  end
end
