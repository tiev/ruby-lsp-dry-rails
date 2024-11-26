module RubyLsp
  module Dry
    module Rails
      class IndexingEnhancementMod < Module
        attr_reader :addon

        def initialize(addon)
          super()

          @addon = addon
          define_method(:_injection_name) do
            addon.rails_runner_client.injection_name
          end
        end

        def included(klass)
          klass.include Requests::Support::Common
          klass.include InstanceMethods
        end

        module InstanceMethods
          def on_call_node_enter(node)
            owner = @listener.current_owner
            return unless owner
            return unless node.name == :include && self_receiver?(node)

            dep_nodes = dependency_nodes(node)
            return if dep_nodes.nil? || dep_nodes.empty?

            dep_nodes.each do |dep_node|
              collect_dependency_accessors(owner, dep_node)
            end
            # TODO: more index:
            # - contructor signature of the class
          end

          def dependency_nodes(node)
            node.arguments&.arguments&.select do |arg|
              arg.is_a?(Prism::CallNode) &&
                arg.name == :[] &&
                arg.receiver.is_a?(Prism::ConstantPathNode) &&
                arg.receiver.full_name == _injection_name
            end
          end

          def collect_dependency_accessors(owner, node)
            @index = @listener.instance_variable_get(:@index)
            @file_path = @listener.instance_variable_get(:@file_path)
            @code_units_cache = @listener.instance_variable_get(:@code_units_cache)

            node.arguments&.arguments&.each do |arg|
              case arg
              when Prism::StringNode
                add_if_new(owner, arg.content.split('.').last, arg.content_loc, arg.content)
              when Prism::SymbolNode
                add_if_new(owner, arg.value.split('.').last, arg.value_loc, arg.value)
              when Prism::KeywordHashNode
                arg.elements.each do |assoc|
                  name = case assoc.key
                         when Prism::SymbolNode
                           assoc.key.value
                         when Prism::StringNode
                           assoc.key.content
                         end
                  loc = case assoc.value
                        when Prism::StringNode
                          assoc.value.content_loc
                        when Prism::SymbolNode
                          assoc.value.value_loc
                        end
                  add_if_new(owner, name, loc, "#{name}: #{assoc.value.unescaped}")
                end
              end
            end
          end

          def add_if_new(owner, name, location, comments)
            loc = RubyIndexer::Location.from_prism_location(location, @code_units_cache)
            existings = @index.resolve_method(name, owner.name)
            return unless existings.nil? || existings.none? do |entry|
              entry.name == name &&
              entry.location.start_line == loc.start_line &&
              entry.location.end_line == loc.end_line &&
              entry.location.start_column == loc.start_column &&
              entry.location.end_column == loc.end_column
            end

            @index.add(RubyIndexer::Entry::Accessor.new(
                         name, @file_path, loc,
                         comments, RubyIndexer::Entry::Visibility::PUBLIC, owner
                       ))
          end
        end
      end
    end
  end
end
