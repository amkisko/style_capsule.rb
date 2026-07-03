# frozen_string_literal: true

require "rack/mock"
require "style_capsule/head_injection_middleware"

RSpec.describe StyleCapsule::HeadInjectionMiddleware do
  let(:app) do
    lambda do |env|
      [200, {"Content-Type" => "text/html; charset=utf-8", "Content-Length" => body.bytesize.to_s}, [body]]
    end
  end

  let(:middleware) { described_class.new(app) }

  let(:body) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head><title>Test</title></head>
        <body><main>Hello</main></body>
      </html>
    HTML
  end

  before do
    StyleCapsule::StylesheetRegistry.clear
    StyleCapsule::StylesheetRegistry.clear_manifest
  end

  def read_response_body(response)
    parts = []
    response.each { |part| parts << part.to_s }
    parts.join
  end

  it "injects pending stylesheets before </head> on the same request" do
    capturing_app = lambda do |env|
      StyleCapsule::StylesheetRegistry.render_head_stylesheets(nil, namespace: :user)
      StyleCapsule::StylesheetRegistry.register(
        "stylesheets/user/order_history_component",
        namespace: :user,
        "data-turbo-track": "reload"
      )

      [200, {"Content-Type" => "text/html; charset=utf-8"}, [body]]
    end

    _status, headers, response = described_class.new(capturing_app).call(Rack::MockRequest.env_for("/"))
    html = read_response_body(response)

    expect(html).to include("/assets/stylesheets/user/order_history_component.css")
    expect(html).to include('data-turbo-track="reload"')
    expect(html.index("/assets/stylesheets/user/order_history_component.css")).to be < html.index("<body>")
    expect(StyleCapsule::StylesheetRegistry.any?).to be false
  end

  it "passes through non-html responses" do
    json_app = ->(_env) { [200, {"Content-Type" => "application/json"}, ['{"ok":true}']] }

    status, headers, response = described_class.new(json_app).call(Rack::MockRequest.env_for("/"))

    expect(status).to eq(200)
    expect(read_response_body(response)).to eq('{"ok":true}')
  end

  it "passes through html without a head element" do
    fragment_app = lambda do |_env|
      StyleCapsule::StylesheetRegistry.register("stylesheets/user/order_history_component", namespace: :user)
      [200, {"Content-Type" => "text/html"}, ["<div>fragment</div>"]]
    end

    _status, _headers, response = described_class.new(fragment_app).call(Rack::MockRequest.env_for("/"))

    expect(read_response_body(response)).to eq("<div>fragment</div>")
  end

  it "updates Content-Length when injection changes the body" do
    capturing_app = lambda do |_env|
      StyleCapsule::StylesheetRegistry.register("stylesheets/user/order_history_component", namespace: :user)
      [200, {"Content-Type" => "text/html; charset=utf-8", "Content-Length" => body.bytesize.to_s}, [body]]
    end

    _status, headers, response = described_class.new(capturing_app).call(Rack::MockRequest.env_for("/"))
    html = read_response_body(response)

    expect(html).to include("/assets/stylesheets/user/order_history_component.css")
    expect(headers["Content-Length"]).to eq(html.bytesize.to_s)
  end

  it "passes through chunked html responses without buffering" do
    seen = []
    streaming_app = lambda do |_env|
      StyleCapsule::StylesheetRegistry.register("stylesheets/user/order_history_component", namespace: :user)
      body_proxy = Object.new
      body_proxy.define_singleton_method(:each) { |&block| seen << :each }
      [200, {"Content-Type" => "text/html", "Transfer-Encoding" => "chunked"}, body_proxy]
    end

    _status, headers, response = described_class.new(streaming_app).call(Rack::MockRequest.env_for("/"))

    expect(seen).to be_empty
    expect(headers["Transfer-Encoding"]).to eq("chunked")
    expect(response).not_to be_a(Array)
  end

  it "passes through html when no pending request-scoped stylesheets remain" do
    _status, headers, response = middleware.call(Rack::MockRequest.env_for("/"))
    html = read_response_body(response)

    expect(html).to eq(body)
    expect(headers["Content-Length"]).to eq(body.bytesize.to_s)
  end

  it "injects pending inline CSS on 201 responses" do
    capturing_app = lambda do |_env|
      StyleCapsule::StylesheetRegistry.register_inline(".created { color: green; }")
      [201, {"Content-Type" => "text/html; charset=utf-8"}, [body]]
    end

    _status, _headers, response = described_class.new(capturing_app).call(Rack::MockRequest.env_for("/"))
    html = read_response_body(response)

    expect(html).to include(".created { color: green; }")
    expect(html.index("<style")).to be < html.index("<body>")
  end
end
