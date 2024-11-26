require 'json'
require 'open3'

require_relative 'support/definition_resolver'
require_relative 'support/dependency_accessor_resolver'

module RubyLsp
  module Dry
    module Rails
      module Common
        def send_message(message)
          json_message = message.to_json
          @stdout.write("Content-Length: #{json_message.bytesize}\r\n\r\n#{json_message}")
        end

        def log_message(message)
          $stderr.puts(message)
          send_message({ result: nil })
        end
      end

      class Server
        include Common

        MAX_COMPLETION_KEYS = 5

        def initialize(stdout: $stdout, override_default_output_device: true)
          @stdin = $stdin
          @stdout = stdout
          @stderr = $stderr
          @stdin.sync = true
          @stdout.sync = true
          @stderr.sync = true
          @stdin.binmode
          @stdout.binmode
          @stderr.binmode

          $> = $stderr if override_default_output_device

          @running = true
        end

        def start
          routes_reloader = ::Rails.application.routes_reloader
          routes_reloader.execute_unless_loaded if routes_reloader&.respond_to?(:execute_unless_loaded)

          send_message({ result: { message: 'ok', root: ::Rails.root.to_s } })
          send_message({ result: { name: app_container.name } })
          send_message({ result: { name: injection_name } })

          while @running
            headers = @stdin.gets("\r\n\r\n")
            json = @stdin.read(headers[/Content-Length: (\d+)/i, 1].to_i)

            request = JSON.parse(json, symbolize_names: true)
            execute(request.fetch(:method), request[:params])
          end
        end

        def execute(request, params)
          request_name = request

          case request
          when 'container_name'
            send_message({ result: container_name })
          when 'injection_name'
            send_message({ result: injection_name })
          when 'shutdown'
            @running = false
          when 'reload'
            ::Rails.application.reloader.reload!
          when 'dependency_location'
            send_message(resolve_dependency_location(params))
          when 'dependency_accessors'
            send_message(collect_dependency_accessors(params))
          when 'matching_dependency_keys'
            send_message(collect_dependency_keys_from_prefix(params))
          end
        rescue ActiveRecord::ConnectionNotEstablished
          log_message("Request #{request_name} failed because database connection was not established.")
        rescue ActiveRecord::NoDatabaseError
          log_message("Request #{request_name} failed because the database does not exist.")
        rescue StandardError => e
          log_message("Request #{request_name} failed:\n" + e.full_message(highlight: false))
        end

        def app_container
          ::Dry::Rails::Railtie.container
        end

        private

        def container_name
          app_container.name
        end

        def injection_name
          "#{::Dry::Rails::Railtie.app_namespace}::#{app_container.auto_inject_constant}"
        end

        def resolve_dependency_location(params)
          # No location if no component registered with the key
          return { result: nil } unless app_container.key?(params[:key])

          result = Support::DefinitionResolver.new(app_container).call(params[:key])
          if result
            { result: { location: result } }
          else
            { result: nil }
          end
        end

        def collect_dependency_accessors(params)
          name = params[:name].to_s
          # TODO: use inflector of the container
          klass = ActiveSupport::Inflector.constantize(name)
          return { result: nil } unless klass

          mods = klass.ancestors.select { |anc| anc.is_a?(::Dry::AutoInject::Strategies::Constructor) }
          return { result: nil } if mods.empty?

          resolver = Support::DependencyAccessorResolver.new(app_container)
          dep_map = mods.map { |mod| mod.dependency_map.to_h }.inject({}) do |h, deps|
            h.merge(deps) { |_, val, _| val }
          end
          result = dep_map.transform_values do |key|
            resolver.call(key)
          end

          { result: }
        end

        def collect_dependency_keys_from_prefix(params)
          prefix = params[:key].to_s
          return { result: nil } if prefix.empty?

          all_keys = app_container.keys.sort # TODO: cache this
          start = all_keys.bsearch_index { |key| key > prefix || key.start_with?(prefix) }
          return { result: nil } unless start

          keys = all_keys[start..start + MAX_COMPLETION_KEYS].select { |key| key.start_with?(prefix) }

          { result: { keys: } }
        end
      end
    end
  end
end

RubyLsp::Dry::Rails::Server.new.start if ARGV.first == 'start'
