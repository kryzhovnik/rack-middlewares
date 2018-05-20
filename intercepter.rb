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
      when Array then rules.map { |i| Rule.new(*i) }
      when Rule  then rules
      else
        raise ArgumentError
      end
    end

    def call(env)
      request = Rack::Request.new(env)
      request_url = FuzzyURI.new(request.url)
      method = request.request_method

      rule = @rules.find do |rule|
        rule.method == method && FuzzyURI.new(rule.url) == request_url
      end

      if rule
        [rule.status, rule.headers, [rule.body]]
      else
        @app.call(env)
      end
    end

    Rule = Struct.new(:method, :url, :status, :headers, :body) do
      def headers
        self[:headers] || {}
      end

      def body
        self[:body] || "STATUS #{status}"
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
        def scheme
          url.scheme
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
          scheme == another_url.scheme
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
