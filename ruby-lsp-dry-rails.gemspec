# frozen_string_literal: true

require_relative 'lib/ruby_lsp_dry_rails/version'

Gem::Specification.new do |spec|
  spec.name        = 'ruby-lsp-dry-rails'
  spec.version     = RubyLsp::Dry::Rails::VERSION
  spec.authors     = ['tiev']
  spec.email       = ['tievtp@gmail.com']
  spec.summary     = 'An opinionated Ruby LSP for Dry::Rails'
  spec.description = 'A Ruby LSP addon for dry-rails, '\
    ' adding extra editor functionality for Rails applications that use the gem'
  spec.license     = 'MIT'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['lib/**/*', 'LICENSE.txt', 'Rakefile', 'README.md']
  end

  spec.add_dependency('ruby-lsp', '>= 0.22.0', '< 0.23.0')
end
