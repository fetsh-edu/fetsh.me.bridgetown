# frozen_string_literal: true

# = ReadingTime
# Computes estimated reading time and stores it in document data.
# Supports language-aware labels driven by external i18n data files.
#
# == Data contract
# Writes:
# - "reading_time_minutes" (Integer)
# - "reading_time_seconds" (Integer)
# - "reading_time" (String) – localized label, e.g., "5 min read".
#
# == I18n
# Place YAML files under: src/_data/i18n/reading_time/<lang>.yml
# Example schema (fill with localized strings in data files ONLY):
# ---
# pattern: "%{m} %{unit}"           # optional; defaults to the same
# units:
#   one:   "<singular unit>"        # e.g., singular minute term
#   few:   "<paucal unit>"          # for languages with paucal (e.g., Russian)
#   many:  "<plural unit>"          # plural form
#   other: "<generic unit>"         # fallback unit
#
# For English you can omit the file; built-in default is "#{m} min read".
#
# == Language detection precedence
# 1) document front matter "lang"
# 2) site.metadata.lang
# 3) site.config["lang"]
# 4) "en"
#
module ReadingTime
  module_function


  # :nodoc:
  MD_IMAGE_RE = %r{!\[[^\]]*\]\([^)]*\)}.freeze
  MD_LINK_RE  = %r{\[[^\]]*\]\([^)]*\)}.freeze
  OBSIDIAN_IMAGE_RE = %r{
    !\[\[
      [^\]\|#]+\.(?:png|jpe?g|webp|gif|svg)   # file with image extension
      (?:\#[^\]\|]+)?                         # optional #fragment
      (?:\|\s*[^\]]+)?                        # optional |alt or |size
    \]\]
  }ix.freeze
  TAGS_REGEXES = [
    /```[\s\S]*?```/m,               # fenced code
    /<pre[\s\S]*?<\/pre>/i,          # HTML <pre>
    /<[^>]*>/,                       # HTML tags
    MD_IMAGE_RE,                     # Markdown images
    MD_LINK_RE,                      # Markdown links
    OBSIDIAN_IMAGE_RE,               # Obsidian wiki-image embeds
    /[#>*`~_\-]+/                    # Markdown markers
  ].freeze


  ##
  # Strip markup and code to approximate the readable text.
  #
  # @param input [String] raw HTML/Markdown content
  # @return [String] plain text
  #
  def strip_readable(input)
    s = input.to_s.dup
    TAGS_REGEXES.each { |re| s.gsub!(re, " ") }
    s
  end

  ##
  # Count words using a basic whitespace split.
  # Note: CJK tokenization is not implemented here.
  #
  # @param input [String]
  # @return [Integer]
  #
  def words_count(input)
    (strip_readable(input).scan(/\S+/) || []).size
  end

  ##
  # Estimate reading time.
  #
  # @param input [String] content
  # @param wpm [Integer] words per minute
  # @param image_count [Integer] number of images
  # @param code_lines [Integer] number of code lines
  # @return [Hash] keys: :words, :seconds, :minutes
  #
  def estimate(input, wpm: 220, image_count: 0, code_lines: 0)
    words   = words_count(input)
    seconds = (words.to_f / wpm * 60).ceil

    # Image time penalty: 12s, 11s, ..., min 3s
    image_penalty = (0...[image_count, 60].min).sum { |i| [12 - i, 3].max }
    seconds += image_penalty + (code_lines * 2)

    minutes = [1, (seconds / 60.0).ceil].max
    { words: words, seconds: seconds, minutes: minutes }
  end

  ##
  # Build a localized label for the given language.
  # Uses i18n data from site.data["i18n"]["reading_time"][lang].
  #
  # @param minutes [Integer]
  # @param lang [String] ISO 639-1 language code
  # @param site [Bridgetown::Site]
  # @return [String] human label, e.g., "5 min read"
  #
  def label_for(minutes, lang:, site:)
    m = minutes.to_i
    return "#{m} min read" if lang.to_s.downcase == "en"
    i18n = site.data.dig("i18n", "reading_time", lang.to_s.downcase) || {}
    pattern = i18n["pattern"] || "%{m} %{unit}"
    units   = i18n["units"] || {}

    unit =
      case lang.to_s.downcase
      when "ru"
        # Russian plural rules:
        #   many for 11..14
        #   one for mod10==1
        #   few for mod10 in 2..4
        #   many otherwise
        rem100 = m % 100
        rem10  = m % 10
        key =
          if (11..14).cover?(rem100) then "many"
          elsif rem10 == 1 then "one"
          elsif (2..4).cover?(rem10) then "few"
          else "many"
          end
        units[key] || units["other"] || "min read"
      when "he", "iw"
        key = (m == 1 ? "one" : "many")
        units[key] || units["other"] || "min read"
      else
        units["other"] || "min read"
      end

    pattern % { m: m, unit: unit }
  rescue KeyError
    # Safety net if pattern placeholders are missing.
    "#{m} min read"
  end
end

Bridgetown::Hooks.register [:documents, :pages, :posts], :pre_render do |doc|
  next unless doc.respond_to?(:content) && doc.content

  md_img_count  = doc.content.scan(ReadingTime::MD_IMAGE_RE).size
  obs_img_count = doc.content.scan(ReadingTime::OBSIDIAN_IMAGE_RE).size
  images        = md_img_count + obs_img_count
  code_lines = doc.content.scan(/```([\s\S]*?)```/).flatten.join("\n").lines.count

  est  = ReadingTime.estimate(doc.content, image_count: images, code_lines: code_lines)
  site = doc.site
  lang = doc.data["lang"] ||
         (site.respond_to?(:metadata) && site.metadata&.lang) ||
         site.config["lang"] ||
         "en"

  doc.data["reading_time_minutes"] = est[:minutes]
  doc.data["reading_time_seconds"] = est[:seconds]
  doc.data["reading_time"]         = ReadingTime.label_for(est[:minutes], lang: lang, site: site)
end
