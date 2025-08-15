# frozen_string_literal: true

# Обработка Obsidian callouts в markdown до конвертации:
# > [!picture] jpt-webp img.class=rounded picture.decoding=async
# > ![[Attachments/foo.png|Подпись]]
#
# > [!figure] jpt-webp figure.class=wide img.class=rounded
# > ![[Attachments/bar.jpg|Заголовок/подпись]]
#
# Генерируется ERB:
# <%= picture "jpt-webp", "images/foo.png", "--alt", "Подпись", "--img", "class=\"rounded\"", "--picture", "decoding=async" %>
# или с figure-обёрткой.

module ObsidianMediaBlocks
  module_function

  # --- публичная точка входа ---
  def transform(text, site:)
    return text if text.nil? || text.empty?

    text = transform_picture_blocks(text, site: site)
    text = transform_figure_blocks(text, site: site)
    text
  end

  # ---------- разбор блоков ----------
  CALL_PICTURE_RE = /
    ^[ \t]*>+[ \t]*\[\!picture\][ \t]*(?<header>[^\n]*)\n
    (?<body>(?:^[ \t]*>[^\n]*\n)+)
  /ix.freeze

  CALL_FIGURE_RE = /
    ^[ \t]*>+[ \t]*\[\!figure\][ \t]*(?<header>[^\n]*)\n
    (?<body>(?:^[ \t]*>[^\n]*\n)+)
  /ix.freeze

  WIKILINK_IMG_RE = /
    \!\[\[
      (?<path>[^\|\]]+?)            # путь
      (?:\|(?<caption>[^\]]*?))?    # необязательная подпись
    \]\]
  /mx.freeze

  def transform_picture_blocks(text, site:)
    text.gsub(CALL_PICTURE_RE) do
      header = Regexp.last_match[:header].to_s.strip
      body   = undent_quote(Regexp.last_match[:body])
      media  = extract_wikilink(body)
      next Regexp.last_match[0] if media.nil? # нет wikilink — не трогаем

      preset, keys = parse_header(header)
      path    = resolve_path(media[:path], site: site)
      alt     = keys["alt"] || media[:caption] || alt_from_filename(path)

      img_attrs, picture_attrs, _figure_classes = split_attrs(keys)

      erb = build_picture_erb(
        preset: preset, path: path, alt: alt,
        img_attrs: img_attrs, picture_attrs: picture_attrs
      )

      # пустая строка вокруг — чтобы не ломать параграфы Markdown
      "\n\n#{erb}\n\n"
    end
  end

  def transform_figure_blocks(text, site:)
    text.gsub(CALL_FIGURE_RE) do
      header = Regexp.last_match[:header].to_s.strip
      body   = undent_quote(Regexp.last_match[:body])
      media  = extract_wikilink(body)
      next Regexp.last_match[0] if media.nil?

      preset, keys = parse_header(header)
      path    = resolve_path(media[:path], site: site)
      caption = media[:caption].to_s.strip
      alt     = keys["alt"] || caption || alt_from_filename(path)

      img_attrs, picture_attrs, figure_classes = split_attrs(keys, prefer_figure_class: true)
      figure_class = ["figure", *figure_classes].join(" ").strip

      erb_picture = build_picture_erb(
        preset: preset, path: path, alt: alt,
        img_attrs: img_attrs, picture_attrs: picture_attrs
      )
      figcaption =
        if caption.empty?
          ""
        else
          # оставляем простой HTML; если нужно Markdown → подключите markdownify в layout’е
          %(\n  <figcaption class="figure-caption">#{escape_html(caption)}</figcaption>\n)
        end

      <<~ERB

        <figure class="#{figure_class}">
          #{erb_picture}#{figcaption}
        </figure>

      ERB
    end
  end

  # ---------- парсинг/утилиты ----------

  def undent_quote(body)
    # срезаем префикс "> " у строк тела блока
    body.lines.map { |l| l.sub(/^[ \t]*>[ \t]?/, "") }.join
  end

  def extract_wikilink(body)
    m = body.match(WIKILINK_IMG_RE)
    return nil unless m
    { path: m[:path].strip, caption: m[:caption].to_s.strip }
  end

  # header: "jpt-webp img.class=rounded picture.decoding=async alt=AAA figure.class=wide"
  # -> preset: "jpt-webp", keys: { "img.class"=>"rounded", "picture.decoding"=>"async", "alt"=>"AAA", "figure.class"=>"wide" }
  def parse_header(header)
    tokens = shell_split(header)
    preset = nil
    keys   = {}

    tokens.each do |tok|
      if tok.include?("=")
        k, v = tok.split("=", 2)
        v = v.strip
        # strip surrounding single/double quotes if present
        if (v.start_with?('"') && v.end_with?('"')) || (v.start_with?("'") && v.end_with?("'"))
          v = v[1..-2]
        end
        keys[k.strip] = v
      elsif preset.nil?
        preset = tok.strip
      else
        # ignore extra positionals
      end
    end

    [preset, keys]
  end

  # Простейший split по пробелам с поддержкой "quoted value"
  def shell_split(s)
    return [] if s.nil? || s.empty?
    s.scan(/"([^"\\]*(?:\\.[^"\\]*)*)"|'([^'\\]*(?:\\.[^'\\]*)*)'|(\S+)/).map do |dq, sq, bare|
      str = dq || sq || bare
      str.gsub(/\\([\\'"])/, '\1')
    end
  end

  def split_attrs(keys, prefer_figure_class: false)
    img_attrs, picture_attrs, figure_classes = {}, {}, []

    keys.each do |k, v|
      case k
      when /\Aimg\.(.+)\z/      then img_attrs[$1] = v
      when /\Apicture\.(.+)\z/  then picture_attrs[$1] = v
      when "figure.class"       then figure_classes.concat(v.split(/\s+/))
      when "class"
        if prefer_figure_class
          figure_classes.concat(v.split(/\s+/))
        else
          img_attrs["class"] = [img_attrs["class"], v].compact.join(" ")
        end
      end
    end

    [img_attrs, picture_attrs, figure_classes]
  end

  def escape_html(s)
    s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
  end

  def alt_from_filename(path)
    File.basename(path.to_s).sub(/\.[^.]+\z/, "").tr("_-", " ").strip
  end

  # Пример маппинга Obsidian → каталог сайта. Подстройте под ваш пайплайн.
  # Примеры:
  #  "Attachments/foo.png"  -> "images/foo.png"
  #  "img/Pasted image.png" -> "images/Pasted image.png"
  def resolve_path(obsidian_path, site:)
    p = obsidian_path.to_s.strip
    if p.start_with?("Attachments/")
      File.join("images", p.sub(%r{\AAttachments/}, ""))
    elsif p.start_with?("img/")
      File.join("images", p.sub(%r{\Aimg/}, ""))
    else
      # как есть — если вы уже копируете ассеты в images/
      p
    end
  end

  # Сборка ERB-вызова <%= picture ... %> с безопасным квотингом
  # def build_picture_erb(preset:, path:, alt:, img_attrs:, picture_attrs:)
  #   args = []
  #   args << preset if preset && !preset.empty?
  #   args << path
  #   if alt && !alt.empty?
  #     args << "--alt" << alt
  #   end
  #   img_attrs.each do |k, v|
  #     next if v.nil? || v.empty?
  #     args << "--img" << %Q{#{k}=#{v}}
  #   end
  #   picture_attrs.each do |k, v|
  #     next if v.nil? || v.empty?
  #     args << "--picture" << %Q{#{k}=#{v}}
  #   end

  #   # Инспект для корректного экранирования каждого аргумента как строкового литерала Ruby.
  #   rendered = args.map { |a| a.to_s }.map(&:inspect).join(", ")
  #   %Q{<%= picture #{rendered} %>}
  # end
  def build_picture_erb(preset:, path:, alt:, img_attrs:, picture_attrs:)
    tokens = []
    tokens << preset if preset && !preset.empty?          # пресет не обязателен
    tokens << %Q{"#{path}"}                               # путь всегда в кавычках

    tokens << "--alt" << alt unless alt.to_s.empty?

    img_attrs.each do |k, v|                              # только явные img.*
      next if v.to_s.empty?
      tokens << "--img" << %Q{#{k}="#{v.gsub('"','\"')}"}
    end

    picture_attrs.each do |k, v|
      next if v.to_s.empty?
      tokens << "--picture" << %Q{#{k}="#{v.gsub('"','\"')}"}
    end

    args_string = tokens.join(" ")
    %Q{<%= raw(picture #{args_string.inspect}) %>}
  end
end

# Hook: до конвертации Markdown → HTML, чтобы ERB отработал в конвертере ERBTemplates
Bridgetown::Hooks.register [:documents, :pages, :posts], :pre_render do |doc, _payload|
  next unless doc.respond_to?(:content) && doc.content
  # Работает только для текстовых исходников (md/markdown/erb)
  next unless %w[.md .markdown .erb .md.erb .markdown.erb].any? { |ext| doc.relative_path.to_s.end_with?(ext) }
  doc.content = ObsidianMediaBlocks.transform(doc.content, site: doc.site)
end
