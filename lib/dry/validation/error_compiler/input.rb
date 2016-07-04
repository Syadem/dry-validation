require 'dry/validation/deprecations'

module Dry
  module Validation
    Message = Struct.new(:rule, :predicate, :path, :text) do
      def to_s
        text
      end

      def root?
        path.empty?
      end

      def hint?
        @hint == true
      end

      def each?
        @each == true
      end

      def to_h
        @to_h ||= [[self], *path.reverse].reduce { |a, e| { e => a } }
      end

      def signature
        @signature ||= [rule, predicate].hash
      end

      def hint!(each = false)
        @hint = true
        @each = each
      end

      def eql?(other)
        other.is_a?(String) ? text == other : super
      end

      def empty?
        false
      end
    end

    class ErrorCompiler::Input < ErrorCompiler
      include Deprecations

      attr_reader :name, :input, :rule, :val_type

      def initialize(messages, options)
        super
        @name = options.fetch(:name)
        @input = options.fetch(:input)
        @rule = Array(name).last
        @val_type = input.class
      end

      def visit_each(node)
        node.map { |el| visit(el) }
      end

      def visit_set(node, *)
        result = node.map do |input|
          visit(input)
        end
        merge(result)
      end

      def visit_el(node)
        idx, el = node
        path = [*Array(name), idx]
        input_visitor(path, input[idx]).visit(el)
      end

      def visit_check(node)
        _, other = node
        visit(other)
      end

      def visit_predicate(node)
        predicate, args = node

        lookup_options = options.merge(
          rule: rule, val_type: val_type, arg_type: args.size > 0 && args[0][1].class
        )

        tokens = options_for(predicate, args)
        template = messages[predicate, lookup_options.merge(tokens)]

        unless template
          raise MissingMessageError.new("message for #{predicate} was not found")
        end

        rule_name =
          if rule.is_a?(Symbol)
            messages.rule(rule, lookup_options) || rule
          else
            rule
          end

        text =
          if full?
            "#{rule_name || tokens[:name]} #{template % tokens}"
          else
            template % tokens
          end

        *arg_vals, _ = args.map(&:last)

        path = name ? Array(name).reverse : Array(tokens[:name])
        path.unshift(tokens[:name]) unless path.include?(tokens[:name])

        message = Message.new(rule, [predicate, arg_vals], text)
        msgpath = [[message], *path]

        msgpath.reduce { |a, e| { e => a } }
      end

      def options_for_inclusion?(args)
        warn 'inclusion is deprecated - use included_in instead.'
        options_for_included_in?(args)
      end

      def options_for_exclusion?(args)
        warn 'exclusion is deprecated - use excluded_from instead.'
        options_for_excluded_from?(args)
      end

      def options_for_excluded_from?(args)
        { list: args[:list].join(', ') }
      end

      def options_for_included_in?(args)
        { list: args[:list].join(', ') }
      end

      def options_for_size?(args)
        size = args[:size]

        if size.is_a?(Range)
          { left: size.first, right: size.last }
        else
          args
        end
      end

      def options_for(predicate, args)
        meth = :"options_for_#{predicate}"

        args_map = Hash[args]
        defaults = { name: rule, rule: rule, value: input }.update(args_map)

        if respond_to?(meth)
          defaults.merge!(__send__(meth, args_map))
        end

        defaults
      end
    end
  end
end
