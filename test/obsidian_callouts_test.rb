require "minitest/autorun"
require "nokogiri"

# Load the plugin file from project plugins dir
require_relative "../plugins/bridgetown_obsidian/callout_transformer"

class TestObsidianCallouts < Minitest::Test
  TRANSFORMER = BridgetownObsidian::CalloutTransformer

  def normalize_html(html)
    # Normalize for structural assertions—not whitespace-sensitive
    Nokogiri::HTML::DocumentFragment.parse(html).to_html
  end

  def fragment(css, html)
    Nokogiri::HTML::DocumentFragment.parse(html).css(css)
  end

  def test_info_with_title_single_paragraph
    input = <<~HTML
      <blockquote>
        <p>[!info] Кстати<br>У <em>Luna</em> тоже есть модель из покрышек:
        <a href="https://lunasandals.com/collections/luna-collection/products/origen-flaco">https://lunasandals.com/collections/luna-collection/products/origen-flaco</a></p>
      </blockquote>
    HTML

    out = normalize_html(TRANSFORMER.transform(input))

    # Wrapper
    callout = fragment("div.callout.info[data-callout='info']", out)
    refute_empty callout, "Callout wrapper not created"

    # Title shell + inner
    title_shell = fragment("div.callout.info > div.callout-title", out)
    refute_empty title_shell
    icon = fragment("div.callout.info > div.callout-title > div.callout-icon", out)
    refute_empty icon
    title_inner = fragment("div.callout.info > div.callout-title > div.callout-title-inner", out)
    refute_empty title_inner
    assert_includes title_inner.first.inner_html, "<p>Кстати", "Title text not preserved"

    # Content preserves paragraph and link
    content_p = fragment("div.callout.info > p", out)
    refute_empty content_p
    link = fragment("div.callout.info a[href='https://lunasandals.com/collections/luna-collection/products/origen-flaco']", out)
    refute_empty link
  end

  def test_warning_without_title_multiparagraph_and_soft_hyphens
    # Marker polluted by soft hyphens: &shy; entity and U+00AD char
    polluted_marker = "[!war\u00ADn&shy;ing]"

    input = <<~HTML
      <blockquote>
        <p>#{polluted_marker}</p>
        <p>Абзац 1.</p>
        <p>Абзац 2.</p>
      </blockquote>
    HTML

    out = normalize_html(TRANSFORMER.transform(input))

    wrapper = fragment("div.callout.warning[data-callout='warning']", out)
    refute_empty wrapper

    # Default title from type (capitalized)
    title_text = fragment("div.callout.warning > div.callout-title > div.callout-title-inner > p", out)
    refute_empty title_text
    assert_equal "Warning", title_text.first.text

    # Both paragraphs moved inside wrapper (as direct <p> siblings after title)
    ps = fragment("div.callout.warning > p", out)
    assert_equal 2, ps.size
    assert_equal "Абзац 1.", ps.first.text
    assert_equal "Абзац 2.", ps.last.text
  end

  def test_unknown_type_is_accepted_and_lowercased
    input = <<~HTML
      <blockquote>
        <p>[!CuStOm] Title</p>
        <p>Body</p>
      </blockquote>
    HTML

    out = normalize_html(TRANSFORMER.transform(input))

    wrapper = fragment("div.callout.custom[data-callout='custom']", out)
    refute_empty wrapper

    title_p = fragment("div.callout.custom > div.callout-title > div.callout-title-inner > p", out)
    assert_equal "Title", title_p.first.text
  end

  def test_non_matching_blockquote_left_as_is
    input = <<~HTML
      <blockquote>
        <p>Just a quote, no callout.</p>
      </blockquote>
    HTML

    out = normalize_html(TRANSFORMER.transform(input))
    assert_includes out, "<blockquote>", "Non-matching blockquote should not be converted"
  end

  def test_no_blank_line_after_marker_treat_as_body
    input = <<~HTML
      <blockquote>
        <p>[!warning] Эксперты рекомендуют ... упражнениями.</p>
      </blockquote>
    HTML

    out = BridgetownObsidian::CalloutTransformer.transform(input)
    frag = Nokogiri::HTML::DocumentFragment.parse(out)

    # Исправленный селектор
    title = frag.at_css("div.callout.warning > div.callout-title > div.callout-title-inner > p")&.text
    body  = frag.at_css("div.callout.warning > p")&.text

    assert_equal "Warning", title
    assert_match(/Эксперты рекомендуют/, body)
  end
end
