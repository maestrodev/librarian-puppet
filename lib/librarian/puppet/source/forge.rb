require 'uri'
require 'net/http'
require 'json'

module Librarian
  module Puppet
    module Source
      class Forge
        class Repo

          attr_accessor :source, :name
          private :source=, :name=

          def initialize(source, name)
            self.source = source
            self.name = name
          end

          def versions
            data = api_call("#{name}.json")
            if data.nil?
              raise Error, "Unable to find module '#{name}' on #{source}"
            end

            versions = data['releases'].map { |r| r['version'] }.sort.reverse
            versions.select { |v| ! Gem::Version.correct? v }.each { |v| debug { "Ignoring invalid version '#{v}' for module #{name}" } }
            versions.select { |v| Gem::Version.correct? v }
          end

          def dependencies(version)
            data = api_call("api/v1/releases.json?module=#{name}&version=#{version}")
            data[name].first['dependencies']
          end

          def manifests
            versions.map do |version|
              Manifest.new(source, name, version)
            end
          end

          def install_version!(version, install_path)
            if environment.local? && !vendored?(name, version)
              raise Error, "Could not find a local copy of #{name} at #{version}."
            end

            if environment.vendor?
              vendor_cache(name, version) unless vendored?(name, version)
            end

            cache_version_unpacked! version

            if install_path.exist?
              install_path.rmtree
            end

            unpacked_path = version_unpacked_cache_path(version).join(name.split('/').last)

            unless unpacked_path.exist?
              raise Error, "#{unpacked_path} does not exist, something went wrong. Try removing it manually"
            else
              FileUtils.cp_r(unpacked_path, install_path)
            end

          end

          def environment
            source.environment
          end

          def cache_path
            @cache_path ||= source.cache_path.join(name)
          end

          def version_unpacked_cache_path(version)
            cache_path.join('version').join(hexdigest(version.to_s))
          end

          def hexdigest(value)
            Digest::MD5.hexdigest(value)
          end

          def cache_version_unpacked!(version)
            path = version_unpacked_cache_path(version)
            return if path.directory?

            # The puppet module command is only available from puppet versions >= 2.7.13
            #
            # Specifying the version in the gemspec would force people to upgrade puppet while it's still usable for git
            # So we do some more clever checking
            #
            # Executing older versions or via puppet-module tool gives an exit status = 0 .
            #
            check_puppet_module_options

            path.mkpath

            target = vendored?(name, version) ? vendored_path(name, version) : name


            command = "puppet module install --version #{version} --target-dir '#{path}' --modulepath '#{path}' --ignore-dependencies '#{target}'"
            output = `#{command}`

            # Check for bad exit code
            unless $? == 0
              # Rollback the directory if the puppet module had an error
              path.unlink
              raise Error, "Error executing puppet module install:\n#{command}\nError:\n#{output}"
            end
          end

          def check_puppet_module_options
            min_version    = Gem::Version.create('2.7.13')
            puppet_version = Gem::Version.create(`puppet --version`.split(' ').first.strip.gsub('-', '.'))

            if puppet_version < min_version
              raise Error, "To get modules from the forge, we use the puppet faces module command. For this you need at least puppet version 2.7.13 and you have #{puppet_version}"
            end
          end

          def vendored?(name, version)
            vendored_path(name, version).exist?
          end

          def vendored_path(name, version)
            environment.vendor_cache.join("#{name.sub("/", "-")}-#{version}.tar.gz")
          end

          def vendor_cache(name, version)
            File.open(vendored_path(name, version).to_s, 'w') do |f|
              download(name, version) do |data|
                f << data
              end
            end
          end

          def download(name, version, &block)
            data = api_call("api/v1/releases.json?module=#{name}&version=#{version}")

            info = data[name].detect {|h| h['version'] == version.to_s }

            stream(info['file'], &block)
          end

          def stream(file, &block)
            #Net::HTTP.get_response(URI.parse("#{source}#{file}")) do |res|
            http_get(URI.parse("#{source}#{file}")) do |res|
              res.code

              res.read_body(&block)
            end
          end

          def debug(*args, &block)
            environment.logger.debug(*args, &block)
          end

        private
        
          def http(uri)
            environment.net_http_class(uri.host).new(uri.host, uri.port)
          end
          
          def http_get(uri)
            max_redirects = 10
            redirects = []
    
            loop do
              
              debug { "Performing http-get for #{uri}" }
              debug { "  uri.path = #{uri.path}"}
              debug { "  uri.host = #{uri.host}"}
              debug { "  uri.port = #{uri.port}"}
              debug { "  uri.request_uri = #{uri.request_uri}"}
                
              http = http(uri)

              if http.proxy?()
                debug {"  proxy_address = #{http.proxy_address()}" }
                debug {"  proxy_port = #{http.proxy_port()}" }
              end
              
              request = Net::HTTP::Get.new(uri.request_uri)
              response = http.start{|http| http.request(request)}
    
              case response
              when Net::HTTPSuccess
                debug { "Responded with success" }
                return response
              when Net::HTTPRedirection
                location = response["Location"]
                debug { "Responded with redirect to #{uri}" }
                redirects.size > max_redirects and raise Error,
                  "Could not get #{uri} because too many redirects!"
                redirects.include?(location) and raise Error,
                  "Could not get #{uri} because redirect cycle!"
                redirects << location
                uri = URI.parse(location)
                # continue the loop
              else
                raise Error, "Could not get #{uri} because #{response.code} #{response.message}!"
              end
            end
          end
      
          def api_call(path)
            base_url = source.uri
            #resp = Net::HTTP.get_response(URI.parse("#{base_url}/#{path}"))
            resp = http_get(URI.parse("#{base_url}/#{path}"))
            if resp.code.to_i != 200
              nil
            else
              data = resp.body
              JSON.parse(data)
            end
          end
        end

        class << self
          LOCK_NAME = 'FORGE'

          def lock_name
            LOCK_NAME
          end

          def from_lock_options(environment, options)
            new(environment, options[:remote], options.reject { |k, v| k == :remote })
          end

          def from_spec_args(environment, uri, options)
            recognised_options = []
            unrecognised_options = options.keys - recognised_options
            unless unrecognised_options.empty?
              raise Error, "unrecognised options: #{unrecognised_options.join(", ")}"
            end

            new(environment, uri, options)
          end
        end

        attr_accessor :environment
        private :environment=
        attr_reader :uri

        def initialize(environment, uri, options = {})
          self.environment = environment
          @uri = uri
          @cache_path = nil
        end

        def to_s
          uri
        end

        def ==(other)
          other &&
          self.class == other.class &&
          self.uri == other.uri
        end
        alias eql? ==

        def hash
          self.uri.hash
        end

        alias :eql? :==

        def hash
          self.to_s.hash
        end

        def to_spec_args
          [uri, {}]
        end

        def to_lock_options
          {:remote => uri}
        end

        def pinned?
          false
        end

        def unpin!
        end

        def install!(manifest)
          manifest.source == self or raise ArgumentError

          name = manifest.name
          version = manifest.version
          install_path = install_path(name)
          repo = repo(name)

          repo.install_version! version, install_path
        end

        def manifest(name, version, dependencies)
          manifest = Manifest.new(self, name)
          manifest.version = version
          manifest.dependencies = dependencies
          manifest
        end

        def cache_path
          @cache_path ||= begin
            dir = Digest::MD5.hexdigest(uri)
            environment.cache_path.join("source/puppet/forge/#{dir}")
          end
        end

        def install_path(name)
          environment.install_path.join(name.split('/').last)
        end

        def fetch_version(name, version_uri)
          versions = repo(name).versions
          if versions.include? version_uri
            version_uri
          else
            versions.first
          end
        end

        def fetch_dependencies(name, version, version_uri)
          environment.logger.debug { "      Fetching dependencies for #{name} #{version}" }
          repo(name).dependencies(version).map do |k, v|
            begin
              Dependency.new(k, v, nil)
            rescue ArgumentError => e
              raise Error, "Error fetching dependency for #{name} [#{version}]: #{k} [#{v}]: #{e}"
            end
          end
        end

        def manifests(name)
          repo(name).manifests
        end

      private

        def repo(name)
          @repo ||= {}
          @repo[name] ||= Repo.new(self, name)
        end
      end
    end
  end
end
