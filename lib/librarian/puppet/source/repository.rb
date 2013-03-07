require 'librarian/source/git/repository'

module Librarian
  module Puppet
    module Source
      class Repository < ::Librarian::Source::Git::Repository

        def initialize(environment, path, module_path)
          @module_path = module_path.to_s
          super environment, path
        end

        def hash_from(remote, reference)
          branch_names = remote_branch_names[remote]
          if branch_names.include?(reference)
            reference = "#{remote}/#{reference}"
          end

          command = %W(rev-parse #{reference}^{commit} --quiet)
          run!(command, :chdir => true).strip
        end

        # Naming this method 'version' causes an exception to be raised.
        def module_version
          return '0.0.1' unless modulefile?

          metadata  = ::Puppet::ModuleTool::Metadata.new
          ::Puppet::ModuleTool::ModulefileReader.evaluate(metadata, modulefile)

          metadata.version
        end

        def dependencies
          return {} unless modulefile?

          metadata = ::Puppet::ModuleTool::Metadata.new

          ::Puppet::ModuleTool::ModulefileReader.evaluate(metadata, modulefile)

          metadata.dependencies.inject({}) do |h, dependency|
            name = dependency.instance_variable_get(:@full_module_name)
            version = dependency.instance_variable_get(:@version_requirement)
            h.update(name => version)
          end
        end

        def modulefile
          File.join(path, @module_path, 'Modulefile')
        end

        def modulefile?
          File.exists?(modulefile)
        end
      end
    end
  end
end
