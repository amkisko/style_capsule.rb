# frozen_string_literal: true

module StyleCapsule
  # Injects stylesheets registered during body rendering into +<head>+ on the same request.
  #
  # Layouts call +stylesheet_registry_tags+ before the body, so +register_stylesheet+ in
  # components runs too late for that call. This middleware appends pending link/style tags
  # immediately before +</head>+ once the full HTML response is available.
  class HeadInjectionMiddleware
    HTML_CONTENT_TYPE = %r{\Atext/html}i
    SUCCESS_STATUS = (200..299)

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)
      return [status, headers, response] unless inject_response?(status, headers, response)
      return [status, headers, response] unless StylesheetRegistry.pending_head_stylesheets?

      maybe_inject_head_styles(status, headers, response, env)
    end

    private

    def maybe_inject_head_styles(status, headers, response, env)
      body = read_response_body(response)
      return [status, headers, response] if body.empty?

      view_context = view_context_for(env)
      injected_body = StylesheetRegistry.inject_pending_head_stylesheets(body, view_context)
      return [status, headers, response] if injected_body.equal?(body)

      headers = headers.dup
      headers["Content-Length"] = injected_body.bytesize.to_s if headers.key?("Content-Length")

      [status, headers, [injected_body]]
    end

    def inject_response?(status, headers, response)
      return false unless SUCCESS_STATUS.cover?(status)
      return false unless html_content_type?(headers["Content-Type"])
      return false if chunked_response?(headers)
      return false if response.respond_to?(:to_ary) && response.to_ary == [""]

      true
    end

    def chunked_response?(headers)
      transfer_encoding = headers["Transfer-Encoding"]
      transfer_encoding&.match?(/chunked/i)
    end

    def html_content_type?(content_type)
      return false if content_type.blank?

      content_type.split(";", 2).first.to_s.strip.match?(HTML_CONTENT_TYPE)
    end

    def read_response_body(response)
      parts = []
      response.each { |part| parts << part.to_s }
      parts.join
    end

    def view_context_for(env)
      controller = env["action_controller.instance"]
      controller&.view_context
    end
  end
end
