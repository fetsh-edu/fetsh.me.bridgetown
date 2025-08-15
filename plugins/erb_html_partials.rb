# Prefer _partials/_name.html.erb when calling: <%= render "name" %>
module ErbHTMLPartials
  def render(partial_name, *args, **kwargs, &block)
    # support "dir/name" too
    path      = partial_name.to_s
    dir       = File.dirname(path)
    base      = File.basename(path)
    candidate = site.in_source_dir("_partials", dir, "_#{base}.html.erb")

    if File.file?(candidate)
      # Bridgetown's resolver will look for _#{base}.html.erb when we pass "base.html"
      return super(File.join(dir, "#{base}.html"), *args, **kwargs, &block)
    end

    # fallback to the default resolution (_name.erb, etc.)
    super(partial_name, *args, **kwargs, &block)
  end
end

Bridgetown::RubyTemplateView.prepend(ErbHTMLPartials)
