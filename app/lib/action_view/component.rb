# frozen_string_literal: true
#
# Use this monkey patch if you aren't running Rails master / 6.1 alpha
# class ActionView::Base
#   module RenderMonkeyPatch
#     def render(component, _ = nil, &block)
#       return super unless component.respond_to?(:render_in)
#
#       component.render_in(self, &block)
#     end
#   end
#
#   prepend RenderMonkeyPatch
# end

module ActionView
  class Component < ActionView::Base
    include ActiveModel::Validations

    # Entrypoint for rendering. Called by ActionView::RenderingHelper#render.
    #
    # view_context: ActionView context from calling view
    # args(hash): params to be passed to component being rendered
    # block: optional block to be called within the view context
    #
    # returns HTML that has been escaped with the ERB pipeline
    #
    # Example subclass:
    #
    # app/components/my_component.rb:
    # class MyComponent < ActionView::Component
    #   def initialize(title:)
    #     @title = title
    #   end
    # end
    #
    # app/components/my_component.html.erb
    # <span title="<%= @title %>">Hello, <%= content %>!</span>
    #
    # In use:
    # <%= render MyComponent.new(title: "greeting") do %>world<% end %>
    # returns:
    # <span title="greeting">Hello, world!</span>
    #
    def render_in(view_context, *args, &block)
      self.class.compile
      @content = view_context.capture(&block) if block_given?
      validate!
      call
    end

    def initialize(*); end

    class << self
      def inherited(child)
        child.include Rails.application.routes.url_helpers unless child < Rails.application.routes.url_helpers

        super
      end

      def compile
        @compiled ||= nil
        return if @compiled

        class_eval(
          "def call; @output_buffer = ActionView::OutputBuffer.new; " +
          compiled_template +
          "; end"
        )

        @compiled = true
      end

      def template
        File.read(template_file_path)
      end

      private

      def compiled_template
        handler = ActionView::Template.handler_for_extension(template_handler)

        if handler.method(:call).parameters.length > 1
          handler.call(DummyTemplate.new, template)
        else
          handler.call(DummyTemplate.new(template))
        end
      end

      def template_handler
        # Does the subclass implement .template ? If so, we assume the template is an ERB HEREDOC
        if self.method(:template).owner == self.singleton_class
          :erb
        else
          File.extname(template_file_path).gsub(".", "").to_sym
        end
      end

      def template_file_path
        raise NotImplementedError.new("#{self} must implement #initialize.") unless self.instance_method(:initialize).owner == self

        filename = self.instance_method(:initialize).source_location[0]
        filename_without_extension = filename[0..-(File.extname(filename).length + 1)]
        sibling_files = Dir["#{filename_without_extension}.*"] - [filename]

        if sibling_files.length > 1
          raise StandardError.new("More than one template found for #{self}. There can only be one sidecar template file per component.")
        end

        if sibling_files.length == 0
          raise NotImplementedError.new(
            "Could not find a template for #{self}. Either define a .template method or add a sidecar template file."
          )
        end

        sibling_files[0]
      end
    end

    class DummyTemplate
      attr_reader :source

      def initialize(source = nil)
        @source = source
      end

      def identifier
        ""
      end

      # we'll eventually want to update this to support other types
      def type
        "text/html"
      end
    end

    private

    attr_reader :content
  end
end