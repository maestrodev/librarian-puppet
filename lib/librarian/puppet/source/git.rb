require 'librarian/source/git'
require 'librarian/puppet/source/local'
require 'librarian/puppet/source/repository'

module Librarian
  module Puppet
    module Source
      class Git < Librarian::Source::Git
        include Local

        def cache!
          return vendor_checkout! if vendor_cached?

          if environment.local?
            raise Error, "Could not find a local copy of #{uri} at #{sha}."
          end

          super

          cache_in_vendor(repository.path) if environment.vendor?
        end

        def vendor_tgz
          environment.vendor_source + "#{sha}.tar.gz"
        end

        def vendor_cached?
          vendor_tgz.exist?
        end

        def vendor_checkout!
          repository.path.rmtree if repository.path.exist?
          repository.path.mkpath

          Dir.chdir(repository.path.to_s) do
            %x{tar xzf #{vendor_tgz}}
          end

          repository_cached!
        end

        def cache_in_vendor(tmp_path)
          Dir.chdir(tmp_path.to_s) do
            %x{git archive #{sha} | gzip > #{vendor_tgz}}
          end
        end

        def fetch_version(name, extra)
          cache!
          found_path = found_path(name)
          repository.module_version
        end

        def fetch_dependencies(name, version, extra)
          repository.dependencies.map do |k, v|
            Dependency.new(k, v, forge_source)
          end
        end

        def forge_source
          Forge.from_lock_options(environment, :remote=>"http://forge.puppetlabs.com")
        end

        def repository
          @repository ||= begin
            Repository.new(environment, repository_cache_path, @path)
          end
        end

      end
    end
  end
end
