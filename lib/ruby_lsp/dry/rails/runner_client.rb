require 'json'
require 'open3'

module RubyLsp
  module Dry
    module Rails
      class RunnerClient
        class << self
          def create_client(outgoing_queue)
            if File.exist?('bin/rails')
              new(outgoing_queue)
            else
              unless outgoing_queue.closed?
                outgoing_queue << RubyLsp::Notification.window_log_message(
                  <<~MESSAGE.chomp,
                    Ruby LSP Dry::Rails failed to locate bin/rails in the current directory: #{Dir.pwd}
                    Server dependent features will not be available
                  MESSAGE
                  type: RubyLsp::Constant::MessageType::WARNING
                )
              end

              NullClient.new
            end
          rescue Errno::ENOENT, StandardError => e # rubocop:disable Lint/ShadowedException
            unless outgoing_queue.closed?
              outgoing_queue << RubyLsp::Notification.window_log_message(
                <<~MESSAGE.chomp,
                  Ruby LSP Dry::Rails failed to initialize server: #{e.full_message}
                  Server dependent features will not be available
                MESSAGE
                type: RubyLsp::Constant::MessageType::ERROR
              )
            end

            NullClient.new
          end
        end

        class InitializationError < StandardError; end
        class MessageError < StandardError; end
        class IncompleteMessageError < MessageError; end
        class EmptyMessageError < MessageError; end

        attr_reader :rails_root, :container_name, :injection_name

        def initialize(outgoing_queue)
          @outgoing_queue = outgoing_queue
          @mutex = Mutex.new

          begin
            Process.setpgrp
            Process.setsid
          rescue Errno::EPERM
            # If we can't set the session ID, continue
          rescue NotImplementedError
            # setpgrp() may be unimplemented on some platform
          end

          log_message('Ruby LSP Dry::Rails booting server')

          stdin, stdout, stderr, wait_thread = Bundler.with_original_env do
            Open3.popen3('bundle', 'exec', 'rails', 'runner', "#{__dir__}/server.rb", 'start')
          end

          @stdin = stdin
          @stdout = stdout
          @stderr = stderr
          @stdin.sync = true
          @stdout.sync = true
          @stderr.sync = true
          @wait_thread = wait_thread

          # We set binmode for Windows compatibility
          @stdin.binmode
          @stdout.binmode
          @stderr.binmode

          initialize_response = read_response
          @rails_root = initialize_response[:root]
          container_response = read_response
          @container_name = container_response[:name]
          injection_response = read_response
          @injection_name = injection_response[:name]
          log_message('Finished booting Ruby LSP Dry::Rails server')

          unless ENV['RAILS_ENV'] == 'test'
            at_exit do
              if @wait_thread.alive?
                sleep(0.5) # give the server a bit of time if we already issued a shutdown notification
                force_kill
              end
            end
          end

          @logger_thread =
            Thread.new do
              while (content = @stderr.gets("\n"))
                log_message(content, type: RubyLsp::Constant::MessageType::LOG)
              end
            end
        rescue Errno::EPIPE, IncompleteMessageError
          raise InitializationError, @stderr.read
        end

        def dependency_location(key)
          make_request('dependency_location', key:)
        rescue MessageError
          log_message(
            'Ruby LSP Dry::Rails failed to get dependency location',
            type: RubyLsp::Constant::MessageType::ERROR
          )
          nil
        end

        def dependency_accessors(name)
          make_request('dependency_accessors', name:)
        rescue MessageError
          log_message(
            'Ruby LSP Dry::Rails failed to get dependencies of class',
            type: RubyLsp::Constant::MessageType::ERROR
          )
          nil
        end

        def matching_dependency_keys(key)
          make_request('matching_dependency_keys', key:)
        rescue MessageError
          log_message(
            'Ruby LSP Dry::Rails failed to get dependency keys from prefix',
            type: RubyLsp::Constant::MessageType::ERROR
          )
          nil
        end

        def trigger_reload
          log_message('Reloading Dry::Rails application')
          send_notification('reload')
        rescue MessageError
          log_message(
            'Ruby LSP Dry::Rails failed to trigger reload',
            type: RubyLsp::Constant::MessageType::ERROR
          )
          nil
        end

        def shutdown
          log_message('Ruby LSP Dry::Rails shutting down server')
          send_message('shutdown')
          sleep(0.5) # give the server a bit of time to shutdown
          [@stdin, @stdout, @stderr].each(&:close)
        rescue IOError
          # The server connection may have died
          force_kill
        end

        def make_request(request, **params)
          send_message(request, **params)
          read_response
        end

        def send_notification(request, **params) = send_message(request, **params)

        private

        def send_message(request, **params)
          message = { method: request }
          message[:params] = params
          json = message.to_json

          @mutex.synchronize do
            @stdin.write("Content-Length: #{json.length}\r\n\r\n", json)
          end
        rescue Errno::EPIPE
          # The server connection died
        end

        def read_response
          raw_response = @mutex.synchronize do
            content_length = read_content_length
            content_length ||= read_content_length
            content_length ||= read_content_length
            content_length ||= read_content_length
            raise EmptyMessageError unless content_length

            @stdout.read(content_length)
          end

          response = JSON.parse(raw_response, symbolize_names: true)

          if response[:error]
            log_message(
              "Ruby LSP Dry::Rails error: #{response[:error]}",
              type: RubyLsp::Constant::MessageType::ERROR
            )
            return
          end

          response.fetch(:result)
        rescue Errno::EPIPE
          # The server connection died
          nil
        end

        def force_kill
          # Windows does not support the `TERM` signal, so we're forced to use `KILL` here
          Process.kill(Signal.list['KILL'], @wait_thread.pid)
        end

        def log_message(message, type: RubyLsp::Constant::MessageType::LOG)
          return if @outgoing_queue.closed?

          @outgoing_queue << RubyLsp::Notification.window_log_message(message, type:)
        end

        def read_content_length
          headers = @stdout.gets("\r\n\r\n")
          return unless headers

          length = headers[/Content-Length: (\d+)/i, 1]
          return unless length

          length.to_i
        end
      end

      class NullClient < RunnerClient
        def initialize # rubocop:disable Lint/MissingSuper
        end

        def shutdown
          # no-op
        end

        def stopped?
          true
        end

        def rails_root
          Dir.pwd
        end

        private

        def log_message(message, type: RubyLsp::Constant::MessageType::LOG)
          # no-op
        end

        def send_message(request, **params)
          # no-op
        end

        def read_response
          # no-op
        end
      end
    end
  end
end
