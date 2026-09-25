# HeadInjectionMiddleware injects bufferable chunked HTML

## Participants

Andrei Makarov

## Decisions

HeadInjectionMiddleware no longer skips every response with Transfer-Encoding chunked. Injection runs when the Rack body responds to to_ary. Non-bufferable streaming bodies are still passed through without calling each. After a successful rewrite, Transfer-Encoding is removed and Content-Length is set to the injected body size.

## Effects

Pending request-scoped stylesheet tags reach head on bufferable chunked HTML. True streaming responses without to_ary stay untouched. README late-head section matches that contract. Specs cover bufferable chunked inject and non-bufferable pass-through.

## Next

Cut a patch release when ready to publish. Confirm consumers that relied on the old skip still expect streaming bodies without to_ary.

## Source

lib/style_capsule/head_injection_middleware.rb
spec/style_capsule/head_injection_middleware_spec.rb
CHANGELOG.md Unreleased
README.md Late head injection
