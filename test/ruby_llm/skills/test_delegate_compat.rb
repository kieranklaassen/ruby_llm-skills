# frozen_string_literal: true

require "test_helper"

class RubyLLM::Skills::TestDelegateCompat < Minitest::Test
  def test_delegate_supports_prefix_keyword
    klass = Class.new do
      def value
        "hello"
      end

      delegate :upcase, to: :value, prefix: true
    end

    assert_equal "HELLO", klass.new.value_upcase
  end

  def test_delegate_supports_allow_nil_keyword
    klass = Class.new do
      def value
        nil
      end

      delegate :upcase, to: :value, allow_nil: true
    end

    assert_nil klass.new.upcase
  end
end
