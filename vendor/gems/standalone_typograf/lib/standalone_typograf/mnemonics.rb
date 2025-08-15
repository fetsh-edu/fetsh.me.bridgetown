# encoding: UTF-8

module StandaloneTypograf #:nodoc:
  module Mnemonics
    extend ActiveSupport::Concern

    # Contains regexps.
    # May contain signs in several languages separated by regexp's OR
    # e.g. eng|рус
    TEMPLATES = {
      '\([c|с]\)'   => { html: '&copy;',   utf: '©' },
      '\((tm|тм)\)' => { html: '&trade;',  utf: '™' },
      '\([r|р]\)'   => { html: '&reg;',    utf: '®' },
      '(\+\-)'      => { html: '&plusmn;', utf: '±' },
      '(\-\>)'      => { html: '&rarr;',   utf: '→' },
      '(\<\-)'      => { html: '&larr;',   utf: '←' },
      '(\~\=)'      => { html: '&asymp;',  utf: '≈' },
    }.freeze

    included do
      register_processor(Processor)
    end

    module Processor
      def self.compile(text, mode)
        text = text.dup
        TEMPLATES.each_pair do |regexp, data|
          text.gsub!(/#{regexp}/i, data[mode])
        end
        return text
      end
    end
  end
end
