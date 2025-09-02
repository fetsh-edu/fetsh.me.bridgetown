require 'minitest/autorun'
require 'minitest/spec'
require_relative '../plugins/obsidian_media_blocks'

class TestObsidianMediaBlocks < Minitest::Test
  def setup
    @mock_logger = MockLogger.new
  end

  # Accept either single- or double-quoted ERB argument. Verifies the inner payload.
  def assert_picture_erb_includes(result, inner_payload)
    dq = %Q{<%= picture "#{inner_payload}" %>}
    sq = %Q{<%= picture '#{inner_payload}' %>}
    assert(
      result.include?(dq) || result.include?(sq),
      "Expected ERB picture with payload:\n  #{inner_payload.inspect}\nGot:\n#{result}"
    )
  end

  def test_transform_with_nil_or_empty_text
    assert_equal '', ObsidianMediaBlocks.transform('', logger: @mock_logger)
    assert_nil ObsidianMediaBlocks.transform(nil, logger: @mock_logger)
  end

  def test_transform_without_obsidian_blocks
    text = "This is regular markdown text with no special blocks."
    result = ObsidianMediaBlocks.transform(text, logger: @mock_logger)
    assert_equal text, result
  end

  # Picture blocks

  def test_picture_block_with_pipe_separator_and_options
    input = <<~MARKDOWN
      > [!picture] jpt-webp | --img class="rounded" --picture decoding="async"
      > ![[images/foo.png|Nice caption]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_picture_erb_includes(
      result,
      'jpt-webp images/foo.png --alt Nice caption --img class="rounded" --picture decoding="async"'
    )
  end

  def test_picture_block_without_pipe_separator
    input = <<~MARKDOWN
      > [!picture] jpt-webp
      > ![[images/test.png|Test image]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_picture_erb_includes(result, 'jpt-webp images/test.png --alt Test image')
  end

  def test_picture_block_without_preset
    input = <<~MARKDOWN
      > [!picture] | --img class="rounded"
      > ![[images/test.png|Test image]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_picture_erb_includes(result, 'images/test.png --alt Test image --img class="rounded"')
  end

  def test_picture_block_empty_header
    input = <<~MARKDOWN
      > [!picture]
      > ![[images/test.png|Test image]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_picture_erb_includes(result, 'images/test.png --alt Test image')
  end

  def test_alt_text_with_quotes
    input = <<~MARKDOWN
      > [!picture] jpt-webp
      > ![[images/test.png|A "quoted" caption]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '--alt A &quot;quoted&quot; caption'
  end

  def test_alt_text_html_entities_are_escaped_in_picture_args
    input = <<~MARKDOWN
      > [!picture] jpt-webp
      > ![[images/x.png|5 < 6 & "ok"]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '--alt 5 &lt; 6 &amp; &quot;ok&quot;'
  end

  def test_filename_based_alt_text_generation
    input = <<~MARKDOWN
      > [!picture] jpt
      > ![[assets/my_image-01.png]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '--alt my image 01'
  end

  def test_complex_header_parsing
    input = <<~MARKDOWN
      > [!picture] jpt-webp preset-option | --img class="btn primary" --picture loading="lazy"
      > ![[images/test.png|Caption]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_picture_erb_includes(
      result,
      'jpt-webp preset-option images/test.png --alt Caption --img class="btn primary" --picture loading="lazy"'
    )
  end

  # Figure blocks

  def test_simple_figure_block
    input = <<~MARKDOWN
      > [!figure] jpt-webp
      > ![[images/test.png|Test caption]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '<figure'
    assert_picture_erb_includes(result, 'jpt-webp images/test.png --alt Test caption')
    # Caption is rendered via markdownify ERB
    assert_includes result, "<figcaption class=\"figure-caption\"><%= markdownify \"Test caption\" %></figcaption>"
    assert_includes result, '</figure>'
  end

  def test_figure_block_with_additional_content_markdown_passthrough
    input = <<~MARKDOWN
      > [!figure] jpt
      > ![[img/bar.jpg|Title]]
      > Extra details here.
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '<figure'
    assert_picture_erb_includes(result, 'jpt img/bar.jpg --alt Title')
    # markdownify should receive both parts with a blank line between
    assert_includes result, "<figcaption class=\"figure-caption\"><%= markdownify 'Title\\n\\nExtra details here.' %></figcaption>"
  end

  def test_figure_block_with_figure_classes
    input = <<~MARKDOWN
      > [!figure] jpt-webp | --wrap class="wide hero"
      > ![[images/test.png|Test caption]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '<figure class="wide hero">'
    refute_includes result, '--wrap'
    refute_includes result, '--parent'
  end

  def test_figure_wrap_only_header
    input = <<~MARKDOWN
      > [!figure] | --wrap class="wide"
      > ![[images/test.png|Test caption]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '<figure class="wide">'
    assert_picture_erb_includes(result, 'images/test.png --alt Test caption')
  end

  # Edge cases

  def test_malformed_picture_block
    input = <<~MARKDOWN
      > [!picture] jpt-webp
      > No wikilink here, just text
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '[!picture] jpt-webp'
    assert_includes result, 'No wikilink here, just text'
    refute_includes result, '<%= picture'
    assert(@mock_logger.warnings.any? { |w| w.include?('Picture block without wikilink') })
  end

  def test_malformed_figure_block
    input = <<~MARKDOWN
      > [!figure] jpt-webp
      > No wikilink here either
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    assert_includes result, '[!figure] jpt-webp'
    assert_includes result, 'No wikilink here either'
    refute_includes result, '<%= picture'
    refute_includes result, '<figure'
    assert @mock_logger.warnings.any? { |w| w.include?("No valid wikilink") }
  end

  def test_unknown_callouts_passthrough
    input = <<~MARKDOWN
      > [!note] header text
      > body
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)
    assert_equal input, result
  end

  # Multiple blocks

  def test_multiple_blocks_in_document
    input = <<~MARKDOWN
      # Document with multiple media blocks

      > [!picture] jpt-webp
      > ![[images/first.png|First image]]

      Some text in between.

      > [!figure] jpt-webp | --wrap class="wide"
      > ![[images/second.jpg|Second image]]
      > Additional figure content

      More text.

      > [!picture] preset | --img class="rounded"
      > ![[images/third.png]]
    MARKDOWN

    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

    picture_count = result.scan(/<%= picture/).size
    figure_count  = result.scan(/<figure class/).size

    assert_equal 3, picture_count
    assert_equal 1, figure_count

    assert_includes result, 'jpt-webp images/first.png --alt First image'
    assert_includes result, 'jpt-webp images/second.jpg --alt Second image'
    assert_includes result, 'preset images/third.png'
    assert_includes result, '<figure class="wide"'
  end

  # Simple (non-callout) wikilinks

  def test_simple_wikilink_line_transforms_to_picture
    input = "![[images/2024/puzyr.jpg]]\n"
    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)
    assert_picture_erb_includes(result, 'images/2024/puzyr.jpg --alt puzyr')
  end

  def test_simple_wikilink_with_caption
    input = "![[images/foo.png|Nice]]"
    result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)
    assert_picture_erb_includes(result, 'images/foo.png --alt Nice')
  end
  def test_figure_block_with_additional_content_markdown_passthrough
      input = <<~MARKDOWN
        > [!figure] jpt
        > ![[img/bar.jpg|Title]]
        > Extra details here.
      MARKDOWN

      result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

      assert_includes result, '<figure'
      assert_picture_erb_includes(result, 'jpt img/bar.jpg --alt Title')

      expected = "<figcaption class=\"figure-caption\"><%= markdownify \"Title\n\nExtra details here.\" %></figcaption>"
      assert_includes result, expected
    end

    def test_figure_caption_with_apostrophe_and_multiparagraph_markdown
      input = <<~MARKDOWN
        > [!figure] preset
        > ![[images/2024/puzyr.jpg|**Bold title**]]
        > Here's some *emphasized text* and a [link](http://test.com).
        >
        > Multiple paragraphs work too.
      MARKDOWN

      result = ObsidianMediaBlocks.transform(input, logger: @mock_logger)

      expected = "<figcaption class=\"figure-caption\"><%= markdownify \"**Bold title**\n\nHere's some *emphasized text* and a [link](http://test.com).\n\nMultiple paragraphs work too.\" %></figcaption>"
      assert_includes result, expected

      # Ensure the apostrophe is present in the ERB payload and text isn't duplicated
      assert_equal 1, result.scan("Here's some").size, "Caption text duplicated or apostrophe lost"
    end
end

# Mock logger
class MockLogger
  attr_reader :warnings, :errors, :info_messages, :debug_messages

  def initialize
    @warnings = []
    @errors = []
    @info_messages = []
    @debug_messages = []
  end

  def warn(component, message)
    @warnings << "#{component}: #{message}"
  end

  def error(component, message)
    @errors << "#{component}: #{message}"
  end

  def info(component, message)
    @info_messages << "#{component}: #{message}"
  end

  def debug(component)
    msg = block_given? ? yield : ""
    @debug_messages << "#{component}: #{msg}"
  end
end

# Mock site
class MockSite
  def logger
    @logger ||= MockLogger.new
  end
end

if __FILE__ == $0
  Minitest.autorun
end
