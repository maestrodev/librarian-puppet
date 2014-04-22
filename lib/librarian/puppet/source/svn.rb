require 'pathname'
require 'digest'
require 'librarian/error'
require 'librarian/posix'
require 'librarian/source/basic_api'
require 'librarian/source/local'
require 'librarian/puppet/source/local'

module Librarian
  module Source
    class Svn
      class Checkout
        class << self
          def bin
            @bin ||= Posix.which!("svn")
          end

          def svn_version
            command = %W[#{bin} --version]
            Posix.run!(command).split(/\n/).strip =~ / ([.\d]+) / && $1
          end
        end

        attr_accessor :environment, :path
        private :environment=, :path=

        def initialize(environment, path)
          self.environment = environment
          self.path = Pathname.new(path)
        end

        def svn?
          path.join('.svn').exist?
        end

        def checkout!(repository_url, options = {})
          command = %W(checkout #{repository_url} #{path})
          run!(command, :chdir => false)
        end

        def checked_out?(rev)
          current_checkout_revision == rev
        end

        def revision_from(uri, ref)
          command = %W(log -l1 #{uri}@#{ref})
          run!(command, :chdir => false).lines.select { |line| line.match /^r\d+ / }[0] =~ /^r(\d+) / && $1
        end

        def current_checkout_revision
          command = %W(info)
          run!(command, :chdir => true).lines.select { |line| line.match /^Last Changed Rev:/ }[0].strip =~ /: (\d+)$/ && $1
        end

        def module_version
          return '0.0.1' unless modulefile?

          metadata = ::Puppet::ModuleTool::Metadata.new
          ::Puppet::ModuleTool::ModulefileReader.evaluate(metadata, modulefile)

          metadata.version
        end

        def dependencies
          return {} unless modulefile? or puppetfile?
          
          if modulefile?
            metadata = ::Puppet::ModuleTool::Metadata.new

            ::Puppet::ModuleTool::ModulefileReader.evaluate(metadata, modulefile)

            metadata.dependencies.map do |dependency|
              name = dependency.instance_variable_get(:@full_module_name)
              version = dependency.instance_variable_get(:@version_requirement) || ">=0"
              v = Librarian::Puppet::Requirement.new(version).gem_requirement
              Dependency.new(name, v, forge_source)
            end
          elsif puppetfile?
            Librarian::Puppet::Environment.new(:project_path => path).specfile.read.dependencies
          end
        end

        def modulefile
          File.join(path, 'Modulefile')
        end

        def modulefile?
          File.exists?(modulefile)
        end

      private

        def bin
          self.class.bin
        end

        def run!(args, options = {})
          chdir = options.delete(:chdir)
          chdir = path.to_s if chdir == true

          silent = options.delete(:silent)
          pwd = chdir || Dir.pwd
          checkout_dir = path if path

          command = [bin]
          command.concat(args)

          logging_command(command, :silent => silent, :pwd => pwd) do
            Posix.run!(command, :chdir => chdir)
          end
        end

        def logging_command(command, options)
          silent = options.delete(:silent)

          pwd = Dir.pwd

          out = yield

          unless silent
            if out.size > 0
              out.lines.each do |line|
                debug { "    --> #{line}" }
              end
            else
              debug { "    --> No output" }
            end
          end
          out
        end

        def debug(*args, &block)
          environment.logger.debug(*args, &block)
        end

      end # Librarian::Source::Svn::Checkout

      include BasicApi
      include Local

      lock_name 'SVN'
      spec_options [ :ref ]

      DEFAULTS = {
        :ref => 'HEAD'
      }

      attr_accessor :environment
      private :environment=

      attr_accessor :uri, :ref, :rev, :path
      private :uri=, :ref=, :rev=, :path=

      def initialize(environment, uri, options)
        self.environment = environment
        self.uri = uri
        self.ref = options[:ref] || DEFAULTS[:ref]
        self.rev = options[:rev]
        self.path = options[:path]

        @checkout = nil
        @checkout_cache_path = nil
      end

      def to_s
        path ? "#{uri}@#{ref}(#{path})" : "#{uri}@#{ref}"
      end

      def ==(other)
        other &&
        self.class  == other.class  &&
        self.uri    == other.uri    &&
        self.ref    == other.ref    &&
        self.path   == other.path
      end

      def to_spec_args
        options = {}
        options.merge!(:ref => ref) if ref != DEFAULTS[:ref]
        options.merge!(:path => path) if path
        [uri, options]
      end

      def to_lock_options
        options = {:remote => uri, :ref => ref, :rev => rev}
        options.merge!(:path => path) if path
        options
      end

      def pinned?
        !!rev
      end

      def unpin!
        @rev = nil
      end
      
      def cache!
        checkout_cached? and return or checkout_cached!

        self.rev = checkout.revision_from(uri, ref) unless self.rev
        unless checkout.svn? and checkout.checked_out?(rev)
          checkout.path.rmtree if checkout.path.exist?
          checkout.path.mkpath
          checkout.checkout!("#{uri}@#{rev}")
        end
      end

    private

      attr_accessor :checkout_cached
      alias checkout_cached? checkout_cached

      def checkout_cached!
        self.checkout_cached = true
      end

      def checkout_cache_path
        @checkout_cache_path ||= begin
          environment.cache_path.join("source/svn/#{cache_key}")
        end
      end

      def checkout
        @checkout ||= begin
          Checkout.new(environment, checkout_cache_path)
        end
      end

      def filesystem_path
        @filesystem_path ||= path ? checkout.path.join(path) : checkout.path
      end

      def cache_key
        @cache_key ||= begin
          uri_part = uri
          path_part = "/#{path}" if path
          ref_part = "##{ref}"
          key_source = [uri_part, path_part, ref_part].join
          Digest::MD5.hexdigest(key_source)[0..15]
        end
      end

    end # Librarian::Source::Svn
  end

  module Puppet
    module Source
      class Svn < Librarian::Source::Svn
        include Local

        def fetch_version(name, extra)
          cache!
          found_path(name)
          v = checkout.module_version
          v = v.gsub("-", ".") # fix for some invalid versions like 1.0.0-rc1

          # if still not valid, use some default version
          unless Gem::Version::correct? v
            debug { "Ignoring invalid version '#{v}' for module #{name}, using 0.0.1" }
            v = '0.0.1'
          end
          v
        end

      end
    end
  end
end
