module GDockerUtil
  def self.underscore(s)
    s.split(%r{([A-Z]+[a-z0-9]*)}).reject(&:empty?).join('_').downcase
  end

  def self.underscore_hash(h)
    h.map { |k, v|
      if v.is_a?(Hash)
        v = underscore_hash(v)
      elsif v.is_a?(Array) && !v.empty? && v[0].is_a?(Hash)
        v = v.map do |j|
          underscore_hash(j)
        end
      end
      [underscore(k), v]
    }.to_h
  end
end
