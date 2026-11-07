# frozen_string_literal: true

module StyleCapsule
  # Storage for request-scoped stylesheet registry state and helper scope cache.
  #
  # Default +:thread+ keeps the historical backends:
  # - +ActiveSupport::CurrentAttributes+ when available
  # - +Thread.current+ otherwise (and for +HelperScopeCache+)
  #
  # Experimental +:fiber+ stores StyleCapsule keys on the current Fiber so concurrent
  # Fibers on one Thread do not share request-scoped stylesheets or the helper cache.
  # Does not change Rails' +ActiveSupport::IsolatedExecutionState.isolation_level+;
  # Falcon-style apps should still set +config.active_support.isolation_level = :fiber+
  # for the rest of Rails.
  module ExecutionState
    INLINE_KEY = :style_capsule_inline_stylesheets
    REQUEST_FILES_KEY = :style_capsule_request_file_stylesheets
    SCOPE_CACHE_KEY = :style_capsule_scope_cache

    module_function

    def fiber_mode?
      StyleCapsule.isolation_level == :fiber
    end

    def [](key)
      backend[key]
    end

    def []=(key, value)
      backend[key] = value
    end

    def delete(key)
      store = backend
      if store.respond_to?(:delete)
        store.delete(key)
      else
        store[key] = nil
      end
    end

    def backend
      if fiber_mode?
        fiber_backend
      else
        thread_backend
      end
    end

    def fiber_backend
      state = Fiber.current.style_capsule_execution_state
      unless state
        state = {}
        Fiber.current.style_capsule_execution_state = state
      end
      state
    end

    def thread_backend
      Thread.current
    end
  end
end

unless Fiber.method_defined?(:style_capsule_execution_state)
  Fiber.attr_accessor :style_capsule_execution_state
end
