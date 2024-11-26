module RubyLsp
  module Dry
    module Rails
      module Support
        class DefinitionResolver
          attr_reader :app_container

          def initialize(app_container)
            super()
            @app_container = app_container
            @container = app_container._container
          end

          def call(key)
            item_key = key.to_s
            component = app_container.send(:find_component, item_key)

            case component
            when ::Dry::System::Component # item in component_dirs
              const_name = component.inflector.camelize(component.const_path)
              component.inflector.constantize(const_name)
              source_location = Object.const_source_location(const_name)

              "#{source_location.first}:#{source_location.second}"
            when ::Dry::System::IndirectComponent
              item = @container.fetch(item_key)
              return unless item

              if project_proc?(item.item)
                source_location = item.item.source_location
                "#{source_location.first}:#{source_location.second}"
              elsif app_container.providers.key?(component.root_key) # providers
                path = app_container.providers.send(:find_provider_file, component.root_key)
                "#{path.to_path}:1" if path
                # TODO: detect the provider item if it's a Proc
              else
                instance = @app_container[item_key]
                source_location = Object.const_source_location(instance.class.name)
                "#{source_location.first}:#{source_location.second}"
              end
            end
          end

          private

          def project_proc?(item)
            item.is_a?(Proc) && item.source_location.first.include?(::Rails.root.to_s)
          end
        end
      end
    end
  end
end
