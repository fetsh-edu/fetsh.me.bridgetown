module BridgetownObsidian
  module CalloutTransformerHook
    Bridgetown::Hooks.register [:documents, :pages, :posts], :post_render do |resource|
      # Only transform HTML outputs
      next unless resource.output_ext == ".html"
      # Run pure transformer over resource.output
      transformed = BridgetownObsidian::CalloutTransformer.transform(resource.output)
      resource.output = transformed
    end
  end
end
