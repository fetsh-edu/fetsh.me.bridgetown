# frozen_string_literal: true
require "strscan"
require "erb" # ERB::Util.h

module ObsidianMediaBlocks
  module_function

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
        elsif scanner.match?(SIMPLE_WIKILINK_LINE_RE)
          out << process_simple_wikilink(scanner.scan(SIMPLE_WIKILINK_LINE_RE), logger: log)
        else
          out << scanner.getch
        end
      end

      out
    rescue => e
      log&.error("ObsidianMediaBlocks", "Transform failed: #{e.message}")
      log&.debug("ObsidianMediaBlocks") { Array(e.backtrace).first(5).join("\n") }
      text
    end
  end

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
    (?<path>[^\|\]]+?)
    (?:\|(?<caption>[^\]]*?))?
    \]\]
  /mx.freeze

  SIMPLE_WIKILINK_LINE_RE = /
    ^[ \t]*
    \!\[\[ (?<path>[^\|\]]+?) (?:\|(?<caption>[^\]]*?))? \]\]
    [ \t]* (?:\r?\n|\z)
  /imx.freeze

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

  def process_figure_match(matched_text, logger: nil)
    data = extract_media_data(matched_text, CALLOUT_FIGURE_RE, logger)
    return matched_text unless data
    begin
      picture_arg_string, figure_attr_string, caption_md =
        build_figure_components(data[:header], data[:media], data[:additional_content])

      erb_picture = %Q{<%= picture '#{escape_ruby_single_quoted(picture_arg_string)}' %>}
      build_figure_erb_template(erb_picture, caption_md, figure_attr_string)
    rescue => e
      logger&.error("ObsidianMediaBlocks", "Figure block processing failed: #{e.message}")
      logger&.debug("ObsidianMediaBlocks") { Array(e.backtrace).first(5).join("\n") }
      matched_text
    end
  end

  def process_simple_wikilink(matched_text, logger: nil)
    md = matched_text.match(SIMPLE_WIKILINK_LINE_RE)
    return matched_text unless md

    media = { path: md[:path].to_s.strip, caption: md[:caption].to_s.strip }
    begin
      arg_string = build_picture_arg_string("", media, is_figure: false)
      erb = %Q{<%= picture '#{escape_ruby_single_quoted(arg_string)}' %>}
      "\n\n#{erb}\n\n"
    rescue => e
      logger&.error("ObsidianMediaBlocks", "Simple wikilink processing failed: #{e.message}")
      logger&.debug("ObsidianMediaBlocks") { Array(e.backtrace).first(5).join("\n") }
      matched_text
    end
  end

  def extract_media_data(matched_text, regex, logger)
    md = matched_text.match(regex)
    return nil unless md

    header = md[:header].to_s.strip
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

  def build_picture_arg_string(header, media, is_figure:)
    preset, options_str = split_header(header)

    base = []
    base << preset if preset
    base << media[:path].to_s

    alt_raw = media[:caption].to_s
    alt_raw = generate_alt_from_filename(media[:path]) if alt_raw.empty?
    base << "--alt" << ERB::Util.h(alt_raw)

    if options_str && !options_str.empty?
      pic_opts, _wrap = split_options_preserving_quotes(options_str, for_figure: is_figure)
      unless pic_opts.empty?
        return ([*base].join(" ") + " " + pic_opts).strip
      end
    end

    base.join(" ")
  end
  module_function :build_picture_arg_string

  def build_figure_components(header, media, additional_content)
    preset, options_str = split_header(header)

    base = []
    base << preset if preset
    base << media[:path].to_s

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

    caption_parts = [media[:caption].to_s.strip, additional_content.to_s.strip].reject(&:empty?)
    caption_md    = caption_parts.join("\n\n")

    [picture_arg_string, figure_attr_string, caption_md]
  end

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

  def split_options_preserving_quotes(options_str, for_figure:)
    s   = options_str.to_s
    len = s.length
    i   = 0

    picture_segments = []
    wrap_segments    = []
    loop do
      i += 1 while i < len && s[i] =~ /\s/
      break if i >= len

      if s[i, 6] == "--wrap" && (i + 6 == len || s[i + 6] =~ /\s/)
        i += 6
        i += 1 while i < len && s[i] =~ /\s/

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
          segment = ["--parent", attrs].join(" ").strip
          picture_segments << segment unless segment.empty?
        end
      else
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

  SAFE_ATTR_NAME = /\A(?:class|id|style|title|role|aria-[\w:-]+|data-[\w:-]+)\z/.freeze

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

  def generate_alt_from_filename(path)
    File.basename(path.to_s)
        .sub(/\.[^.]+\z/, "")
        .tr("_-", " ")
        .strip
  end
  module_function :generate_alt_from_filename

  # --- figure template (markdownify via double-quoted literal) ---
  def build_figure_erb_template(erb_picture, caption_md, figure_attr_string)
    figure_open = figure_attr_string.to_s.strip.empty? ? "<figure>" : %(<figure #{figure_attr_string}>)

    figcaption =
      if caption_md.to_s.strip.empty?
        ""
      else
        %(\n <figcaption class="figure-caption"><%= markdownify "#{escape_ruby_double_quoted(caption_md)}" %></figcaption>)
      end

    <<~ERB.chomp


      #{figure_open}
       #{erb_picture}#{figcaption}
      </figure>


    ERB
  end
  module_function :build_figure_erb_template

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
  module_function :tokenize_attrs_preserving_quotes

  def escape_ruby_single_quoted(s)
    s.to_s.gsub("\\", "\\\\").gsub("'", "\\'")
  end
  module_function :escape_ruby_single_quoted

  def escape_ruby_double_quoted(s)
    s.to_s
      .gsub("\\", "\\\\")
      .gsub('"', '\"')
      .gsub('#{', '\#{')
  end
  module_function :escape_ruby_double_quoted
end
