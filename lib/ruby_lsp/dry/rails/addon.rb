require 'ruby_lsp/addon'

require_relative 'completion'
require_relative 'definition'
require_relative 'indexing_enhancement_mod'
require_relative 'runner_client'
require_relative 'server'
require_relative 'support/definition_resolver'
require_relative 'support/location_builder'

module RubyLsp
  module Dry
    module Rails
      class Addon < ::RubyLsp::Addon
        def initialize
          super

          @rails_runner_client = NullClient.new
          @global_state = nil
          @outgoing_queue = nil
          @indexing_enhancement = nil
          @addon_mutex = Mutex.new
          @client_mutex = Mutex.new
          @client_mutex.lock

          Thread.new do
            @addon_mutex.synchronize do
              @client_mutex.synchronize { @rails_runner_client = RunnerClient.create_client(@outgoing_queue) }
            end
          end
        end

        def rails_runner_client
          @addon_mutex.synchronize { @rails_runner_client }
        end

        def activate(global_state, outgoing_queue)
          @global_state = global_state
          @outgoing_queue = outgoing_queue
          @outgoing_queue << Notification.window_log_message('Activating Ruby LSP Dry::Rails add-on')

          # register_additional_file_watchers(global_state:, outgoing_queue:)

          mod = IndexingEnhancementMod.new(self)
          @indexing_enhancement = Class.new(RubyIndexer::Enhancement) do
            include mod
          end

          # Start booting the real client in a background thread. Until this completes, the client will be a NullClient
          @client_mutex.unlock
        end

        def deactivate
          @rails_runner_client.shutdown
        end

        def name
          'Ruby LSP Dry::Rails'
        end

        def version
          '0.1.0'
        end

        def create_definition_listener(response_builder, _uri, node_context, dispatcher)
          index = @global_state.index
          Definition.new(@rails_runner_client, response_builder, node_context, index, dispatcher)
        end

        def create_completion_listener(response_builder, node_context, dispatcher, _uri)
          index = @global_state.index
          Completion.new(@rails_runner_client, response_builder, node_context, index, dispatcher)
        end

        def workspace_did_change_watched_files(changes)
          return unless changes.any? { |c| c[:uri].end_with?('db/schema.rb', 'structure.sql') }

          @rails_runner_client.trigger_reload

          # TODO: maybe: check the updated class again to update index (costly)
        end
      end
    end
  end
end
