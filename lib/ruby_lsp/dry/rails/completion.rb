module RubyLsp
  module Dry
    module Rails
      class Completion
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
          return unless @node_context.call_node.receiver.is_a?(Prism::ConstantPathNode) &&
                        @node_context.call_node.receiver.full_name == @client.injection_name &&
                        @node_context.call_node.name == :[]

          result = @client.matching_dependency_keys(node.unescaped)
          return unless result

          keys = result.fetch(:keys) { [] }
          keys.each do |key|
            item = RubyLsp::Interface::CompletionItem.new(
              label: key,
              kind: RubyLsp::Constant::CompletionItemKind::VALUE,
              text_edit: RubyLsp::Interface::TextEdit.new(
                range: range_from_node(node),
                new_text: "\'#{key}\'"
              )
            )
            @response_builder << item
          end
        end
      end
    end
  end
end
