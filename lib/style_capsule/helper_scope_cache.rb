# frozen_string_literal: true

require "strscan"

module StyleCapsule
  # Bounded per-thread cache for scoped CSS from ERB / standalone helpers (avoids unbounded Thread.current growth).
  module HelperScopeCache
    MAX_SCOPE_CACHE_ENTRIES = 256
    STYLE_OPEN = %r{<style[^>]*>}im
    STYLE_CLOSE = %r{</style>}im

    private

    # @param full_html [String]
    # @return [Array(String, String, nil)] html_without_styles, combined_css (nil if none)
    def extract_styles_from_markup(full_html)
      scanner = StringScanner.new(full_html)
      html_out = +""
      segments = []

      until scanner.eos?
        text = scanner.scan_until(STYLE_OPEN)
        if text.nil?
          html_out << scanner.rest
          break
        end

        html_out << text.sub(STYLE_OPEN, "")

        css = scanner.scan_until(STYLE_CLOSE)
        if css.nil?
          html_out << scanner.rest
          break
        end

        segments << css.sub(STYLE_CLOSE, "")
      end

      combined = segments.empty? ? nil : segments.join("\n\n")
      [html_out.strip, combined]
    end

    def scope_css_with_bounded_cache(css_content, capsule_id)
      fingerprint = Digest::SHA1.hexdigest(css_content.to_s)
      cache_key = "style_capsule_#{capsule_id}_#{fingerprint}"

      bucket = Thread.current[:style_capsule_scope_cache] ||= {order: [], hash: {}}
      hash = bucket[:hash]
      order = bucket[:order]

      return hash[cache_key] if hash.key?(cache_key)

      scoped_css = CssProcessor.scope_selectors(css_content, capsule_id)
      evict_scope_cache_if_full!(hash, order)
      hash[cache_key] = scoped_css
      order << cache_key
      scoped_css
    end

    def evict_scope_cache_if_full!(hash, order)
      while order.size >= MAX_SCOPE_CACHE_ENTRIES
        old = order.shift
        hash.delete(old)
      end
    end
  end
end
