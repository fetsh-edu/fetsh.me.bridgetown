# frozen_string_literal: true

# == Bridgetown Obsidian Wikilinks
#
# Replaces Obsidian-style wikilinks in post/page content with Markdown links.
#
# Examples:
#   [[2023-08-22-barefoot|я пытался бегать босиком]]
#   [[_posts/2023-08-22-barefoot|label]]
#   [[2023-08-22-barefoot#part-1|label]]
#
# Placement:
#   plugins/obsidian_wikilinks.rb
#
module BridgetownObsidian
  class ObsidianWikilinks
    REGEX_WIKILINK = /
      (?<!!)\[\[                    # opening [[ not preceded by !
        (?<target>[^\]\|#]+         # target (no '|' or ']' or '#')
           (?:\#[^\]\|]+)?          # optional '#anchor'
        )
        (?:\|(?<label>[^\]]+))?     # optional |label
      \]\]
    /x.freeze

    # Crude code fence / inline code segmentation
    FENCE_REGEX = /
      (?<fence>^```.*?$.*?^```$)    # fenced code block
      | (?<inline>`[^`]*`)          # inline code
    /mx.freeze

    # Crude code fence / inline code segmentation
    FENCE_REGEX = /
      (?<fence>^```.*?$.*?^```$)    # fenced code block
      | (?<inline>`[^`]*`)          # inline code
    /mx.freeze

    def initialize(site)
      @site = site
      @cache = build_slug_index
    end

    def rewrite(doc)
      return unless doc.content

      doc.content = rewrite_outside_code(doc.content) do |text|
        text.gsub(REGEX_WIKILINK) do
          target_raw = Regexp.last_match[:target]
          label_raw  = Regexp.last_match[:label]

          target, anchor = target_raw.split("#", 2)
          label = label_raw || target

          url = resolve_url_for(target.strip, anchor, doc)
          url ? "[#{label}](#{url})" : Regexp.last_match[0]
        end
      end
    end

    private

    def build_slug_index
      index = {}
      posts = @site.collections.posts.resources

      posts.each do |p|
        base = File.basename(p.relative_path.to_s, File.extname(p.relative_path.to_s))
        slug_only = base.sub(/^\d{4}-\d{2}-\d{2}-/, "")

        index[base] = p
        index[slug_only] ||= p

        rel_no_ext = p.relative_path.to_s.sub(File.extname(p.relative_path.to_s), "")
        index[rel_no_ext] ||= p
      end

      index
    end

    def rewrite_outside_code(content)
      parts = content.split(FENCE_REGEX)
      return content unless parts && !parts.empty?

      rebuilt = +""
      parts.each_with_index do |segment, idx|
        if idx.odd?
          # inside code, keep unchanged
          rebuilt << segment
        else
          rebuilt << yield(segment)
        end
      end
      rebuilt
    end

    def resolve_url_for(target, anchor, doc)
      res = lookup_resource(target)
      return nil unless res

      base_url =
        if res.respond_to?(:url) && res.url
          res.url
        else
          helpers_for(doc).url_for(res.relative_path.to_s)
        end

      anchor ? "#{base_url}##{anchor}" : base_url
    end

    def lookup_resource(target)
      key = target.sub(/\.md$/i, "")
      key = key.sub(%r{\A_posts/}, "")
      @cache[key] || @cache[target] || @cache[target.sub(/\.md$/i, "")]
    end

    def helpers_for(resource)
      Bridgetown::RubyTemplateView::Helpers.new(resource, @site)
    end
  end
end

# Register hook across posts, pages, and documents
Bridgetown::Hooks.register [:documents, :pages, :posts], :pre_render do |doc, site|
  @wikilinks ||= BridgetownObsidian::ObsidianWikilinks.new(doc.site)
  @wikilinks.rewrite(doc)
end
