module RubyLsp
  module Dry
    module Rails
      module Support
        class DependencyAccessorResolver
          def initialize(app_container)
            super()
            @app_container = app_container
            @container = app_container._container
          end

          def call(key)
            item_key = key.to_s
            component = @app_container.send(:find_component, item_key)

            case component
            when ::Dry::System::Component # item in component_dirs
              const_name = component.inflector.camelize(component.const_path)
              component.inflector.constantize(const_name)
              source_location = Object.const_source_location(const_name)

              "#{source_location.first}:#{source_location.second}"
            when ::Dry::System::IndirectComponent
              item = @container.fetch(item_key)
              return unless item

              instance = @app_container[item_key]
              source_location = Object.const_source_location(instance.class.name)
              "#{source_location.first}:#{source_location.second}"
            end
          end
        end
      end
    end
  end
end
