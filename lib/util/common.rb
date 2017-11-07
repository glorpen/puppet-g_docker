module Facter
  module Util
    module Docker
      def self.underscore(s)
        s.split(/([A-Z]+[a-z0-9]*)/).reject(&:empty?).join("_").downcase
      end
      
      def self.underscore_hash(h)
        h.map do | k, v |
          if v.is_a?(Hash)
            v = self.underscore_hash(v)
          elsif v.is_a?(Array) and not v.empty? and v[0].is_a?(Hash)
            v = v.map do | j |
              self.underscore_hash(j)
            end
          end
          [self.underscore(k), v]
        end.to_h
      end
    end
  end
end
