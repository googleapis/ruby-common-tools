class RADLinkFormatter
  class Log
    # YARD records issues finding links via YARD::Logger#warn
    def warn str
      raise str
    end
  end

  include YARD::Templates::Helpers::BaseHelper
  include YARD::Templates::Helpers::HtmlHelper

  attr_accessor :object
  attr_accessor :options
  attr_accessor :serializer

  def initialize object, options
    @original_object = object
    @object = object
    @options = options
    @serializer = options.serializer
  end

  def log
    @log ||= Log.new
  end

  def parse_links str
    # resolve_links fails when a link is defined above the object containing the item the link is pointing to
    objects_list = [@object]
    objects_list += @object.children if @object.respond_to? :children
    err = nil
    objects_list.each do |obj|
      @object = obj
      begin
        str = resolve_links str
        return str
      rescue => e
        if e.message.match /In file [\s\w\d`\/\.:']*Cannot resolve link to \S+ from text:/
          err = e
          next
        else
          YARD::Logger.instance.warn e.message
          return str
        end
      ensure
        reset_object
      end
    end
    YARD::Logger.instance.warn err.message if err

    str
  end

  alias_method :original_url_for, :url_for

  def url_for obj, anchor = nil, relative = true
    if obj.is_a? YARD::CodeObjects::Base
      unless obj.is_a? YARD::CodeObjects::NamespaceObject
        # If the obj is not a namespace obj make it the anchor.
        anchor = obj
        obj = obj.namespace
      end
      link = obj.path.sub(/^::/, "").gsub("::", "-")
      result = link + (anchor ? "#" + urlencode(anchor_for(anchor)) : "")
      return result
    end

    original_url_for obj, anchor, relative
  end

  alias_method :original_url_for_file, :url_for_file

  def url_for_file filename, anchor = nil
    if filename.is_a? YARD::CodeObjects::ExtraFileObject
      link = filename == options.readme ? "index.html" : filename.name
      link = "./#{link}"
      link = "#{link}##{urlencode(anchor)}" if anchor
      return link
    end

    original_url_for_file filename, anchor
  end

  alias_method :original_link_url, :link_url

  def link_url url, title = nil, params = {}
    title ||= url
    title.gsub! "_", "&lowbar;"
    original_link_url url, title, params
  end

  def anchor_for obj
    anchor = obj.path.tr "?!:#\.", "_"
    if obj.type == :method
      anchor += obj.scope == :class ? "_class_" : "_instance_"
    end
    anchor
  end

  def reset_object
    @object = @original_object
  end
end
