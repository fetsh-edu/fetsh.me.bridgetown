# frozen_string_literal: true

# Ensure the core is loaded first (robust even if loader order changes)
require_relative "../obsidian_media_blocks"

module ObsidianMediaBlocks
  module Hooks
    @registered = false
    class << self
      def register!
        return if @registered
        return if ENV["OMB_DISABLE_HOOKS"] == "1" # disable for tests

        Bridgetown::Hooks.register [:documents, :pages, :posts], :pre_render do |doc, _payload|
          next unless doc.respond_to?(:content) && doc.content
          next unless %w[.md .markdown .erb .md.erb .markdown.erb].any? { |ext| doc.relative_path.to_s.end_with?(ext) }
          doc.content = ObsidianMediaBlocks.transform(doc.content, site: doc.site)
        end

        @registered = true
      end
    end
  end
end

# Eagerly register in normal runtime
ObsidianMediaBlocks::Hooks.register!
