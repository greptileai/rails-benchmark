require 'active_support/deprecation'

module ActionView
  module Assertions
    NO_STRIP = %w{pre script style textarea}

    # Adds the +assert_select+ method for use in Rails functional
    # test cases, which can be used to make assertions on the response HTML of a controller
    # action. You can also call +assert_select+ within another +assert_select+ to
    # make assertions on elements selected by the enclosing assertion.
    #
    # Use +css_select+ to select elements without making an assertions, either
    # from the response HTML or elements selected by the enclosing assertion.
    #
    # In addition to HTML responses, you can make the following assertions:
    #
    # * +assert_select_encoded+ - Assertions on HTML encoded inside XML, for example for dealing with feed item descriptions.
    # * +assert_select_email+ - Assertions on the HTML body of an e-mail.
    module SelectorAssertions
      # Select and return all matching elements.
      #
      # If called with a single argument, uses that argument as a selector
      # to match all elements of the current page. Returns an empty
      # Nokogiri::XML::NodeSet if no match is found.
      #
      # If called with two arguments, uses the first argument as the root
      # element and the second argument as the selector. Attempts to match the
      # root element and any of its children.
      # Returns an empty Nokogiri::XML::NodeSet if no match is found.
      #
      # The selector may be a CSS selector expression (String).
      # css_select returns nil if called with an invalid css selector.
      #
      #   # Selects all div tags
      #   divs = css_select("div")
      #
      #   # Selects all paragraph tags and does something interesting
      #   pars = css_select("p")
      #   pars.each do |par|
      #     # Do something fun with paragraphs here...
      #   end
      #
      #   # Selects all list items in unordered lists
      #   items = css_select("ul>li")
      #
      #   # Selects all form tags and then all inputs inside the form
      #   forms = css_select("form")
      #   forms.each do |form|
      #     inputs = css_select(form, "input")
      #     ...
      #   end
      def css_select(*args)
        raise ArgumentError, "you at least need a selector argument" if args.empty?

        root = args.size == 1 ? response_from_page : args.shift
        selector = args.first

        catch_invalid_selector do
          root.css(selector).tap do |matches|
            if matches.empty? && root.matches?(selector)
              return Nokogiri::XML::NodeSet.new(root.document, [root])
            end
          end
        end
      end

      # An assertion that selects elements and makes one or more equality tests.
      #
      # If the first argument is an element, selects all matching elements
      # starting from (and including) that element and all its children in
      # depth-first order.
      #
      # If no element is specified, calling +assert_select+ selects from the
      # response HTML unless +assert_select+ is called from within an +assert_select+ block.
      #
      # When called with a block +assert_select+ passes an array of selected elements
      # to the block. Calling +assert_select+ from the block, with no element specified,
      # runs the assertion on the complete set of elements selected by the enclosing assertion.
      # Alternatively the array may be iterated through so that +assert_select+ can be called
      # separately for each element.
      #
      #
      # ==== Example
      # If the response contains two ordered lists, each with four list elements then:
      #   assert_select "ol" do |elements|
      #     elements.each do |element|
      #       assert_select element, "li", 4
      #     end
      #   end
      #
      # will pass, as will:
      #   assert_select "ol" do
      #     assert_select "li", 8
      #   end
      #
      # The selector may be a CSS selector expression (String) or an expression
      # with substitution values (Array).
      # Substitution uses a custom pseudo class match. Pass in whatever attribute you want to match (enclosed in quotes) and a ? for the substitution.
      # assert_select returns nil if called with an invalid css selector.
      #
      # assert_select "div:match('id', ?)", /\d+/
      #
      # === Equality Tests
      #
      # The equality test may be one of the following:
      # * <tt>true</tt> - Assertion is true if at least one element selected.
      # * <tt>false</tt> - Assertion is true if no element selected.
      # * <tt>String/Regexp</tt> - Assertion is true if the text value of at least
      #   one element matches the string or regular expression.
      # * <tt>Integer</tt> - Assertion is true if exactly that number of
      #   elements are selected.
      # * <tt>Range</tt> - Assertion is true if the number of selected
      #   elements fit the range.
      # If no equality test specified, the assertion is true if at least one
      # element selected.
      #
      # To perform more than one equality tests, use a hash with the following keys:
      # * <tt>:text</tt> - Narrow the selection to elements that have this text
      #   value (string or regexp).
      # * <tt>:html</tt> - Narrow the selection to elements that have this HTML
      #   content (string or regexp).
      # * <tt>:count</tt> - Assertion is true if the number of selected elements
      #   is equal to this value.
      # * <tt>:minimum</tt> - Assertion is true if the number of selected
      #   elements is at least this value.
      # * <tt>:maximum</tt> - Assertion is true if the number of selected
      #   elements is at most this value.
      #
      # If the method is called with a block, once all equality tests are
      # evaluated the block is called with an array of all matched elements.
      #
      #   # At least one form element
      #   assert_select "form"
      #
      #   # Form element includes four input fields
      #   assert_select "form input", 4
      #
      #   # Page title is "Welcome"
      #   assert_select "title", "Welcome"
      #
      #   # Page title is "Welcome" and there is only one title element
      #   assert_select "title", {count: 1, text: "Welcome"},
      #       "Wrong title or more than one title element"
      #
      #   # Page contains no forms
      #   assert_select "form", false, "This page must contain no forms"
      #
      #   # Test the content and style
      #   assert_select "body div.header ul.menu"
      #
      #   # Use substitution values
      #   assert_select "ol>li:match('id', ?)", /item-\d+/
      #
      #   # All input fields in the form have a name
      #   assert_select "form input" do
      #     assert_select ":match('name', ?)", /.+/  # Not empty
      #   end
      def assert_select(*args, &block)
        @selected ||= nil

        selector = HTMLSelector.new(@selected, response_from_page, args)

        matches = nil
        catch_invalid_selector do
          matches = selector.select

          assert_size_match!(matches.size, selector.equality_tests, selector.source, selector.message)
        end

        # Set @selected to allow nested assert_select.
        # Can be nested several levels deep.
        if block_given? && !matches.empty?
          begin
            in_scope, @selected = @selected, matches
            yield matches
          ensure
            @selected = in_scope
          end
        end

        matches
      end

      def count_description(min, max, count) #:nodoc:
        pluralize = lambda {|word, quantity| word << (quantity == 1 ? '' : 's')}

        if min && max && (max != min)
          "between #{min} and #{max} elements"
        elsif min && max && max == min && count
          "exactly #{count} #{pluralize['element', min]}"
        elsif min && !(min == 1 && max == 1)
          "at least #{min} #{pluralize['element', min]}"
        elsif max
          "at most #{max} #{pluralize['element', max]}"
        end
      end

      # Extracts the content of an element, treats it as encoded HTML and runs
      # nested assertion on it.
      #
      # You typically call this method within another assertion to operate on
      # all currently selected elements. You can also pass an element or array
      # of elements.
      #
      # The content of each element is un-encoded, and wrapped in the root
      # element +encoded+. It then calls the block with all un-encoded elements.
      #
      #   # Selects all bold tags from within the title of an Atom feed's entries (perhaps to nab a section name prefix)
      #   assert_select "feed[xmlns='http://www.w3.org/2005/Atom']" do
      #     # Select each entry item and then the title item
      #     assert_select "entry>title" do
      #       # Run assertions on the encoded title elements
      #       assert_select_encoded do
      #         assert_select "b"
      #       end
      #     end
      #   end
      #
      #
      #   # Selects all paragraph tags from within the description of an RSS feed
      #   assert_select "rss[version=2.0]" do
      #     # Select description element of each feed item.
      #     assert_select "channel>item>description" do
      #       # Run assertions on the encoded elements.
      #       assert_select_encoded do
      #         assert_select "p"
      #       end
      #     end
      #   end
      def assert_select_encoded(element = nil, &block)
        case element
          when Array
            elements = element
          when Nokogiri::XML::Node
            elements = [element]
          when nil
            unless elements = @selected
              raise ArgumentError, "First argument is optional, but must be called from a nested assert_select"
            end
          else
            raise ArgumentError, "Argument is optional, and may be node or array of nodes"
        end

        content = elements.map do |elem|
          elem.children.select(&:cdata?).map(&:content)
        end.join
        selected = Loofah.fragment(content)

        begin
          old_selected, @selected = @selected, selected
          if content.empty?
            yield selected
          else
            assert_select ":root", &block
          end
        ensure
          @selected = old_selected
        end
      end

      # Extracts the body of an email and runs nested assertions on it.
      #
      # You must enable deliveries for this assertion to work, use:
      #   ActionMailer::Base.perform_deliveries = true
      #
      #  assert_select_email do
      #    assert_select "h1", "Email alert"
      #  end
      #
      #  assert_select_email do
      #    items = assert_select "ol>li"
      #    items.each do
      #       # Work with items here...
      #    end
      #  end
      def assert_select_email(&block)
        deliveries = ActionMailer::Base.deliveries
        assert !deliveries.empty?, "No e-mail in delivery list"

        deliveries.each do |delivery|
          (delivery.parts.empty? ? [delivery] : delivery.parts).each do |part|
            if part["Content-Type"].to_s =~ /^text\/html\W/
              root = Loofah.fragment(part.body.to_s)
              assert_select root, ":root", &block
            end
          end
        end
      end

      protected

        def catch_invalid_selector
          begin
            yield
          rescue Nokogiri::CSS::SyntaxError => e
            ActiveSupport::Deprecation.warn("The assertion was not run because of an invalid css selector.\n#{e}")
            return
          end
        end

        # +equals+ must contain :minimum, :maximum and :count keys
        def assert_size_match!(size, equals, css_selector, message = nil)
          min, max, count = equals[:minimum], equals[:maximum], equals[:count]

          message ||= %(Expected #{count_description(min, max, count)} matching "#{css_selector}", found #{size}.)
          if count
            assert_equal size, count, message
          else
            assert_operator size, :>=, min, message if min
            assert_operator size, :<=, max, message if max
          end
        end

        # +html_document+ is used in testing/integration.rb
        def html_document
          @html_document ||= if @response.content_type =~ /xml$/
            Loofah.xml_document(@response.body)
          else
            Loofah.document(@response.body)
          end
        end

        def response_from_page
          html_document.root
        end

        class HTMLSelector #:nodoc:
          attr_accessor :root, :selector, :equality_tests, :message

          alias :source :selector

          def initialize(selected, page, args)
            # Start with possible optional element followed by mandatory selector.
            @selector_is_second_argument = false
            @root = determine_root_from(args.first, page, selected)
            @selector = extract_selector(args)

            @equality_tests = equality_tests_from(args.shift)
            @message = args.shift

            if args.shift
              raise ArgumentError, "Not expecting that last argument, you either have too many arguments, or they're the wrong type"
            end
          end

          def select
            filter root.css(selector, context)
          end

          def filter(matches)
            match_with = equality_tests[:text] || equality_tests[:html]
            return matches if matches.empty? || !match_with

            content_mismatch = nil
            text_matches = equality_tests.has_key?(:text)
            regex_matching = match_with.is_a?(Regexp)

            remaining = matches.reject do |match|
              # Preserve markup with to_s for html elements
              content = text_matches ? match.text : match.children.to_s

              content.strip! unless NO_STRIP.include?(match.name)
              content.sub!(/\A\n/, '') if text_matches && match.name == "textarea"

              next if regex_matching ? (content =~ match_with) : (content == match_with)
              content_mismatch ||= sprintf("<%s> expected but was\n<%s>.", match_with, content)
              true
            end

            self.message ||= content_mismatch if remaining.empty?
            Nokogiri::XML::NodeSet.new(matches.document, remaining)
          end

          def determine_root_from(root_or_selector, page, previous_selection = nil)
            if root_or_selector == nil
              raise ArgumentError, "First argument is either selector or element to select, but nil found. Perhaps you called assert_select with an element that does not exist?"
            elsif root_or_selector.respond_to?(:css)
              @selector_is_second_argument = true
              root_or_selector
            elsif previous_selection
              if previous_selection.is_a?(Array)
                Nokogiri::XML::NodeSet.new(previous_selection[0].document, previous_selection)
              else
                previous_selection
              end
            else
              page
            end
          end

          def extract_selector(values)
            selector = @selector_is_second_argument ? values.shift(2).last : values.shift
            unless selector.is_a? String
              raise ArgumentError, "Expecting a selector as the first argument"
            end
            context.substitute!(selector, values)
          end

          def equality_tests_from(comparator)
              comparisons = {}
              case comparator
                when Hash
                  comparisons = comparator
                when String, Regexp
                  comparisons[:text] = comparator
                when Integer
                  comparisons[:count] = comparator
                when Range
                  comparisons[:minimum] = comparator.begin
                  comparisons[:maximum] = comparator.end
                when FalseClass
                  comparisons[:count] = 0
                when NilClass, TrueClass
                  comparisons[:minimum] = 1
                else raise ArgumentError, "I don't understand what you're trying to match"
              end

              # By default we're looking for at least one match.
              if comparisons[:count]
                comparisons[:minimum] = comparisons[:maximum] = comparisons[:count]
              else
                comparisons[:minimum] ||= 1
              end
            comparisons
          end

          def context
            @context ||= SubstitutionContext.new
          end

          class SubstitutionContext
            def initialize(substitute = '?')
              @substitute = substitute
              @regexes = []
            end

            def add_regex(regex)
              # Nokogiri doesn't like arbitrary values without quotes, hence inspect.
              return regex.inspect unless regex.is_a?(Regexp)
              @regexes.push(regex)
              last_id.to_s # avoid implicit conversions of Fixnum to String
            end

            def last_id
              @regexes.count - 1
            end

            def match(matches, attribute, id)
              matches.find_all { |node| node[attribute] =~ @regexes[id] }
            end

            def substitute!(selector, values)
              while !values.empty? && selector.index(@substitute)
                selector.sub!(@substitute, add_regex(values.shift))
              end
              selector
            end
          end
        end
    end
  end
end
