# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gemspec

gem 'debug'
gem 'puma', '>= 5.0'
gem 'rails', '8.0.0'
gem 'rubocop-minitest'
gem 'rubocop-rake'
gem 'sqlite3', '>=2.1'

platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem 'tzinfo'
  gem 'tzinfo-data'
end
