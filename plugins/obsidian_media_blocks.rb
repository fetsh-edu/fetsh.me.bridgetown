# frozen_string_literal: true
require "strscan"
require "erb" # ERB::Util.h

##
# ObsidianMediaBlocks transforms Obsidian callout blocks with embedded media
# into ERB templates for picture and figure elements.
#
# == Usage
#
#   content = ObsidianMediaBlocks.transform(markdown_text, site: site)
#
# == Supported Formats
#
# Picture blocks:
#   > [!picture] jpt-webp | --parent class="wide"
#   > ![[path/to/image.png|Caption]]
#
# Figure blocks:
#   > [!figure] jpt-webp | --wrap class="wide hero" style="margin: 20px" data-id="main"
#   > ![[path/to/image.jpg|Title/caption]]
#   > Additional text content for figure caption
#
# Header format:
# - [preset] | [other options] - preset before |, options after |
# - [preset] - if no |, entire header is preset
# - | [other options] - if starts with |, no preset, just options
#
# Special flags:
# - --wrap attr="value" in [!figure] applies ALL attributes to <figure> element, removed from picture tag
# - --wrap attr="value" in [!picture] becomes --parent attr="value" in picture tag (quotes preserved)
#
module ObsidianMediaBlocks
  module_function

  # --------------------------------------------------------------------------
  # Public API
  # --------------------------------------------------------------------------

  # Transform Obsidian callout blocks into ERB picture/figure templates
  #
  # @param text [String] the markdown text to transform
  # @param site [Object] Bridgetown site object for logging (deprecated, use logger param)
  # @param logger [Object] Logger object (optional, defaults to site.logger or Bridgetown.logger)
  # @return [String] transformed text with ERB templates
  # @raise [ArgumentError] if text is not a string
  def transform(text, site: nil, logger: nil)
    return text if text.nil? || text.empty?
    raise ArgumentError, "Text must be a string" unless text.is_a?(String)

    log = logger || (defined?(Bridgetown) ? Bridgetown.logger : site&.logger)

    begin
      scanner = StringScanner.new(text)
      out = +''

      until scanner.eos?
        if scanner.match?(CALLOUT_PICTURE_RE)
          out << process_picture_match(scanner.scan(CALLOUT_PICTURE_RE), logger: log)
        elsif scanner.match?(CALLOUT_FIGURE_RE)
          out << process_figure_match(scanner.scan(CALLOUT_FIGURE_RE), logger: log)
        else
          out << scanner.getch
        end
      end

      out
    rescue => e
      log&.error("ObsidianMediaBlocks", "Transform failed: #{e.message}")
      log&.debug("ObsidianMediaBlocks") { Array(e.backtrace).first(5).join("\n") }
      text # Return original text on error
    end
  end

  # --------------------------------------------------------------------------
  # Regexes
  # --------------------------------------------------------------------------

  CALLOUT_PICTURE_RE = /
    ^[ \t]*>+[ \t]*\[\!picture\][ \t]*(?<header>[^\r\n]*)\r?\n
    (?<body>(?:^[ \t]*>[^\r\n]*\r?\n)+)
  /imx.freeze

  CALLOUT_FIGURE_RE = /
    ^[ \t]*>+[ \t]*\[\!figure\][ \t]*(?<header>[^\r\n]*)\r?\n
    (?<body>(?:^[ \t]*>[^\r\n]*\r?\n)+)
  /imx.freeze

  WIKILINK_IMAGE_RE = /
    \!\[\[
    (?<path>[^\|\]]+?)               # file path
    (?:\|(?<caption>[^\]]*?))?       # optional caption
    \]\]
  /mx.freeze

  # --------------------------------------------------------------------------
  # Processing
  # --------------------------------------------------------------------------

  # Process matched picture block
  #
  # @param matched_text [String] the full matched text
  # @param logger [Object] Logger object (optional)
  # @return [String] processed ERB template or original text
  def process_picture_match(matched_text, logger: nil)
    data = extract_media_data(matched_text, CALLOUT_PICTURE_RE, logger)
    return matched_text unless data

    begin
      arg_string = build_picture_arg_string(data[:header], data[:media], is_figure: false)
      erb = %Q{<%= picture '#{escape_ruby_single_quoted(arg_string)}' %>}
      "\n\n#{erb}\n\n"
    rescue => e
      logger&.error("ObsidianMediaBlocks", "Picture block processing failed: #{e.message}")
      logger&.debug("ObsidianMediaBlocks") { Array(e.backtrace).first(5).join("\n") }
      matched_text
    end
  end

  # Process matched figure block
  #
  # @param matched_text [String] the full matched text
  # @param logger [Object] Logger object (optional)
  # @return [String] processed ERB template or original text
  def process_figure_match(matched_text, logger: nil)
    data = extract_media_data(matched_text, CALLOUT_FIGURE_RE, logger)
    return matched_text unless data

    begin
      picture_arg_string, figure_attr_string, html_caption =
        build_figure_components(data[:header], data[:media], data[:additional_content])

      erb_picture = %Q{<%= picture '#{escape_ruby_single_quoted(picture_arg_string)}' %>}
      build_figure_erb_template(erb_picture, html_caption, figure_attr_string)
    rescue => e
      logger&.error("ObsidianMediaBlocks", "Figure block processing failed: #{e.message}")
      logger&.debug("ObsidianMediaBlocks") { Array(e.backtrace).first(5).join("\n") }
      matched_text
    end
  end

  # --------------------------------------------------------------------------
  # Extraction
  # --------------------------------------------------------------------------

  # Extract media data from matched text
  #
  # @param matched_text [String] the full matched text
  # @param regex [Regexp] the regex pattern to match
  # @param logger [Object] Logger object (optional)
  # @return [Hash, nil] extracted data or nil if invalid
  def extract_media_data(matched_text, regex, logger)
    md = matched_text.match(regex)
    return nil unless md

    header = md[:header].to_s.strip
    # drop leading `>` and an optional space on each quoted line
    clean_body = md[:body].gsub(/^[ \t]*>[ \t]?/, "")

    link = clean_body.match(WIKILINK_IMAGE_RE)
    unless link
      logger&.warn("ObsidianMediaBlocks",
                   regex == CALLOUT_PICTURE_RE ? "Picture block without wikilink" :
                                                 "No valid wikilink found in figure block")
      return nil
    end

    media = {
      path:    link[:path].to_s.strip,
      caption: link[:caption].to_s.strip,
    }

    additional = clean_body.gsub(WIKILINK_IMAGE_RE, "").strip

    { header: header, media: media, additional_content: additional }
  end

  # --------------------------------------------------------------------------
  # Picture args & figure components
  # --------------------------------------------------------------------------

  # Build the single argument string for the picture helper.
  # Quotes in options are preserved verbatim; `--wrap` is transformed to `--parent` for pictures.
  def build_picture_arg_string(header, media, is_figure:)
    preset, options_str = split_header(header)

    base = []
    base << preset if preset
    base << media[:path].to_s

    # ALT: caption or filename, then HTML-escape for safe HTML attribute embedding
    alt_raw = media[:caption].to_s
    alt_raw = generate_alt_from_filename(media[:path]) if alt_raw.empty?
    alt_for_picture = ERB::Util.h(alt_raw)
    base << "--alt" << alt_for_picture

    if options_str && !options_str.empty?
      pic_opts, _wrap = split_options_preserving_quotes(options_str, for_figure: is_figure)
      unless pic_opts.empty?
        return ([*base].join(" ") + " " + pic_opts).strip
      end
    end

    base.join(" ")
  end
  module_function :build_picture_arg_string

  # For figures we also produce sanitized <figure ...> attributes and HTML-escaped caption.
  def build_figure_components(header, media, additional_content)
    preset, options_str = split_header(header)

    base = []
    base << preset if preset
    base << media[:path].to_s

    # ALT: HTML-escape for picture arg; figcaption uses independently escaped text below
    alt_raw = media[:caption].to_s
    alt_raw = generate_alt_from_filename(media[:path]) if alt_raw.empty?
    base << "--alt" << ERB::Util.h(alt_raw)

    picture_options = ""
    figure_attr_string = ""

    if options_str && !options_str.empty?
      pic_opts, wrap_str = split_options_preserving_quotes(options_str, for_figure: true)
      picture_options = pic_opts
      figure_attr_string = sanitize_wrap_attributes(wrap_str)
    end

    picture_arg_string =
      if picture_options.empty?
        base.join(" ")
      else
        ([*base].join(" ") + " " + picture_options).strip
      end

    # Figcaption remains escaped as text, using <br> joiner
    caption_parts = [media[:caption].to_s.strip, additional_content.to_s.strip].reject(&:empty?)
    html_caption  = caption_parts.map { |s| ERB::Util.h(s) }.join("<br>")

    [picture_arg_string, figure_attr_string, html_caption]
  end

  # Split header into [preset, options] according to the "preset | options" convention.
  def split_header(header)
    return [nil, nil] if header.nil? || header.empty?
    if header.include?("|")
      preset, options = header.split("|", 2).map { |s| s.strip }
      preset = nil if preset.nil? || preset.empty?
      [preset, options&.strip]
    else
      [header.strip, nil]
    end
  end

  # --------------------------------------------------------------------------
  # Quote-preserving option handling
  # --------------------------------------------------------------------------

  # Quote-aware splitter that preserves original quotes in non-wrap options and extracts wrap payloads.
  # Returns [picture_segments_string, wrap_segments_string]
  def split_options_preserving_quotes(options_str, for_figure:)
    s   = options_str.to_s
    len = s.length
    i   = 0

    picture_segments = []
    wrap_segments    = []

    loop do
      # skip whitespace
      i += 1 while i < len && s[i] =~ /\s/
      break if i >= len

      # detect --wrap at a token boundary
      if s[i, 6] == "--wrap" && (i + 6 == len || s[i + 6] =~ /\s/)
        i += 6
        i += 1 while i < len && s[i] =~ /\s/

        # collect attrs until next boundary "--" not inside quotes
        attr_start = i
        in_s = in_d = false
        while i < len
          ch = s[i]
          if ch == "'" && !in_d
            in_s = !in_s
          elsif ch == '"' && !in_s
            in_d = !in_d
          elsif ch == '-' && !in_s && !in_d && s[i, 2] == "--" &&
                (i == attr_start || s[i - 1] =~ /\s/)
            break
          end
          i += 1
        end
        attrs = s[attr_start...i].to_s.strip
        wrap_segments << attrs unless attrs.empty?

        unless for_figure
          # keep quotes intact when moving to picture args
          segment = ["--parent", attrs].join(" ").strip
          picture_segments << segment unless segment.empty?
        end
      else
        # collect non-wrap segment until next --wrap at boundary, preserving quotes
        seg_start = i
        in_s = in_d = false
        while i < len
          ch = s[i]
          if ch == "'" && !in_d
            in_s = !in_s
          elsif ch == '"' && !in_s
            in_d = !in_d
          elsif ch == '-' && !in_s && !in_d && s[i, 6] == "--wrap" &&
                (i + 6 == len || s[i + 6] =~ /\s/) &&
                (i == seg_start || s[i - 1] =~ /\s/)
            break
          end
          i += 1
        end
        seg = s[seg_start...i].to_s.strip
        picture_segments << seg unless seg.empty?
      end
    end

    [picture_segments.join(" "), wrap_segments.join(" ")]
  end

  # Tokenize a space-separated attribute string while preserving quoted groups.
  def tokenize_attrs_preserving_quotes(s)
    str = s.to_s
    len = str.length
    i   = 0
    toks = []
    in_s = in_d = false
    tok_start = nil

    while i < len
      ch = str[i]
      if tok_start.nil?
        if ch =~ /\s/
          i += 1
          next
        else
          tok_start = i
        end
      end

      if ch == "'" && !in_d
        in_s = !in_s
      elsif ch == '"' && !in_s
        in_d = !in_d
      elsif ch =~ /\s/ && !in_s && !in_d
        toks << str[tok_start...i]
        tok_start = nil
      end
      i += 1
    end
    toks << str[tok_start...i] if tok_start
    toks
  end

  # --------------------------------------------------------------------------
  # Sanitization for <figure ...> attributes
  # --------------------------------------------------------------------------

  SAFE_ATTR_NAME = /\A(?:class|id|style|title|role|aria-[\w:-]+|data-[\w:-]+)\z/.freeze

  # Accepts a string (preferred) or array of tokens with possible quotes.
  # Produces a sanitized attribute string for HTML: key="escaped" key2="escaped" boolean
  def sanitize_wrap_attributes(tokens_or_string)
    tokens = tokens_or_string.is_a?(String) ? tokenize_attrs_preserving_quotes(tokens_or_string) : Array(tokens_or_string)
    return "" if tokens.empty?

    attrs = []

    tokens.each do |t|
      if t.include?("=")
        key, val = t.split("=", 2)
        key = key.to_s.strip
        next unless key.match?(SAFE_ATTR_NAME)

        v = val.to_s
        # strip outer quotes if present; rebuild with double quotes and HTML-escape
        if (v.start_with?('"') && v.end_with?('"')) || (v.start_with?("'") && v.end_with?("'"))
          v = v[1..-2]
        end
        attrs << %(#{key}="#{ERB::Util.h(v)}")
      else
        key = t.to_s.strip
        next unless key.match?(SAFE_ATTR_NAME)
        attrs << ERB::Util.h(key)
      end
    end

    attrs.join(" ")
  end

  # --------------------------------------------------------------------------
  # Utilities
  # --------------------------------------------------------------------------

  # Generate alt text from filename
  def generate_alt_from_filename(path)
    File.basename(path.to_s)
        .sub(/\.[^.]+\z/, "")
        .tr("_-", " ")
        .strip
  end
  module_function :generate_alt_from_filename

  # Build figure ERB template
  def build_figure_erb_template(erb_picture, html_caption, figure_attr_string)
    figure_open = figure_attr_string.to_s.strip.empty? ? "<figure>" : %(<figure #{figure_attr_string}>)
    figcaption  = html_caption.to_s.empty? ? "" : %(\n <figcaption class="figure-caption">#{html_caption}</figcaption>)

    <<~ERB.chomp


      #{figure_open}
       #{erb_picture}#{figcaption}
      </figure>


    ERB
  end
  module_function :build_figure_erb_template

  # Escape for a Ruby *single-quoted* string literal embedded in ERB.
  # Prevents interpolation and keeps the helper call safe.
  def escape_ruby_single_quoted(s)
    s.to_s.gsub("\\", "\\\\").gsub("'", "\\'")
  end
  module_function :escape_ruby_single_quoted
end
