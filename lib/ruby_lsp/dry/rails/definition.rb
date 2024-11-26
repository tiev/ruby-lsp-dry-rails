module RubyLsp
  module Dry
    module Rails
      class Definition
        include Requests::Support::Common

        def initialize(client, response_builder, node_context, index, dispatcher)
          @client = client
          @response_builder = response_builder
          @node_context = node_context
          @index = index

          dispatcher.register(self, :on_symbol_node_enter, :on_string_node_enter)
        end

        def on_string_node_enter(node)
          handle_possible_dependency(node)
        end

        def on_symbol_node_enter(node)
          handle_possible_dependency(node)
        end

        def handle_possible_dependency(node)
          return unless @node_context.call_node &&
                        @node_context.call_node.receiver.is_a?(Prism::ConstantPathNode) &&
                        @node_context.call_node.receiver.full_name == @client.injection_name &&
                        @node_context.call_node.name == :[]

          result = @client.dependency_location(node.unescaped)
          return unless result

          @response_builder << Support::LocationBuilder.line_location_from_s(result.fetch(:location))
        end
      end
    end
  end
end
