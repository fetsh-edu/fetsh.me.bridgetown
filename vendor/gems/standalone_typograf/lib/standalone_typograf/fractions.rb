# encoding: UTF-8

module StandaloneTypograf #:nodoc:
  module Fractions
    extend ActiveSupport::Concern

    included do
      register_processor(Processor)
    end

    module Processor
      def self.compile(text, mode)
        return text unless mode == :html

        text.gsub(/(\s|^)(\d+)(\/)(\d+)(?:\s|$)/, '\1<sup>\2</sup>&frasl;<sub>\4</sub>')
      end
    end
  end
end
