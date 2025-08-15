# frozen_string_literal: true

require "nokogiri"
require "nokogiri/html5"
require "text/hyphen"
require "standalone_typograf"

module SoftHyphenizer
  HYPH_RU = Text::Hyphen.new(language: "ru",    left: 2, right: 2)
  HYPH_EN = Text::Hyphen.new(language: "en_us", left: 2, right: 2)

  BLOCK_EXCLUDE = %w[code pre kbd samp var a img figure figcaption svg math picture source].freeze
  WORD_RE       = /\p{L}{7,}/
  HEBREW_RE     = /\p{Hebrew}/

  module_function

  def hyphenate_word(word)
    return word if word.include?("&shy;") || word.match?(HEBREW_RE)
    (word.match?(/\p{Cyrillic}/) ? HYPH_RU : HYPH_EN).visualize(word, "&shy;")
  end

  def skip_node?(node)
    node.ancestors.any? { |a| BLOCK_EXCLUDE.include?(a.name) }
  end

  def typografize_text(text)
    StandaloneTypograf::Typograf.new(text, mode: :html).prepare
  end

  def extra_rules(text)
    text
      .gsub(/(\s|^)(г|гг)\./i, '\1\2.&nbsp;')
      .gsub(/(\s|^)№\s*(\d+)/, '№&nbsp;\2')
      .gsub(/(\d+)\s*(°\s?[CF])/, '\1&nbsp;\2')
      .gsub(/(\d+)\s*(₽|₪|\$|€)/, '\1&nbsp;\2')
      .gsub(/(\b[А-ЯЁ])\.\s?([А-ЯЁ])\./, '\1.&nbsp;\2.')
      .gsub(/(\d+)\s*x\s*(\d+)/i, '\1×\2')
  end

  def process_text_node!(text_node)
    processed = typografize_text(text_node.text)
    processed = extra_rules(processed)
    processed = processed.gsub(WORD_RE) { |w| hyphenate_word(w) }
    text_node.replace(processed)
  end

  def process_paragraph!(p)
    lang = p["lang"].to_s.downcase
    return if lang.start_with?("he") || p["dir"].to_s.downcase == "rtl"

    p.children.each do |node|
      next unless node.text?
      next if skip_node?(node)
      process_text_node!(node)
    end
  end

  def each_target_paragraph(scope)
    # Основной путь — CSS (быстро и читаемо)
    return scope.css("article p, .prose p")
  # rescue Nokogiri::XML::XPath::SyntaxError
  #   # Фолбэк на XPath без неймспейсов
  #   return scope.xpath(
  #     "//*[local-name()='article']//p | " \
  #     "//*[contains(concat(' ', normalize-space(@class), ' '), ' prose ')]//p"
  #   )
  end

  def process_html(html)
    return html unless html&.include?("<article") || html&.include?('class="prose"')

    if html.lstrip.start_with?('<!doctype', '<html', '<HTML')
      doc = Nokogiri::HTML5.parse(html)
    else
      doc = Nokogiri::HTML5.fragment(html)
    end

    # КРИТИЧЕСКОЕ: убрать любые неймспейсы, если внезапно появились
    doc.remove_namespaces! if doc.respond_to?(:remove_namespaces!)

    each_target_paragraph(doc).each { |p| process_paragraph!(p) }

    doc.to_html
  end
end

module TypographPlus
  module_function
  def process_html(html) = SoftHyphenizer.process_html(html)
end
Bridgetown::Hooks.register [:documents, :pages, :posts], :post_render do |doc|
  next unless doc.output_ext == ".html"

  doc.output = TypographPlus.process_html(doc.output.to_s)
end
