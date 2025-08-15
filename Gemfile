source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

####
# Welcome to your project's Gemfile, used by Rubygems & Bundler.
#
# To install a plugin, run:
#
#   bundle add new-plugin-name
#
# and add a relevant init comment to your config/initializers.rb file.
#
# When you run Bridgetown commands, we recommend using a binstub like so:
#
#   bin/bridgetown start (or console, etc.)
#
# This will help ensure the proper Bridgetown version is running.
####

# If you need to upgrade/switch Bridgetown versions, change the line below
# and then run `bundle update bridgetown`
gem 'bridgetown', '~> 2.0.0.beta6'

# Uncomment to add file-based dynamic routing to your project:
# gem "bridgetown-routes", "~> 2.0.0.beta6"

# Puma is the Rack-compatible web server used by Bridgetown
# (you can optionally limit this to the "development" group)
gem 'puma', '< 7'

# Uncomment to use the Inspectors API to manipulate the output
# of your HTML or XML resources:


# Or for faster parsing of HTML-only resources via Inspectors, use Nokolexbor:
# gem "nokolexbor", "~> 0.5"

gem "standalone_typograf", path: "vendor/gems/standalone_typograf"
gem 'text-hyphen', '~> 1.5'

group :bridgetown_plugins do
  gem "bridgetown_picture_tag", git: "https://github.com/seroperson/bridgetown_picture_tag.git"
end

gem "nokogiri", "~> 1.18"
