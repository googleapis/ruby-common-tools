def init
  @objects = options.item
  sections :toc
end

def objects
  return @objects_list if @objects_list

  @objects_list = @objects.dup
  @objects_list.uniq!
  @objects_list.sort_by! { |obj| obj.path }
  @objects_list.reject! do |obj|
    obj.visibility == :private || obj.tags.any? { |tag| tag.tag_name == "private" }
  end
  @objects_list
end

def toc_text
  text = []
  objects.each do |obj|
    text << "  - uid: #{obj.path}"
    text << "    name: #{obj.path}"
  end
  text.join "\n"
end

def overview_items
  custom_names = {
    "index.md" => "Getting started",
    "AUTHENTICATION.md" => "Authenticating the library"
  }
  text = []
  readme_filename = options.readme.filename
  options.files.each do |file|
    href =
      case file.filename
        when readme_filename
          "index.md"
        when /^(.+)\.txt$/, /^(\.?[^.]+)$/
          name = Regexp.last_match[1].tr("_", "-")
          "#{name}.md"
        when /^(.+\.md)$/
          Regexp.last_match[1].tr("_", "-")
        end
    next unless href
    name = custom_names[href] || File.basename(href, ".*").tr("_-", " ").capitalize
    text << "    - name: #{name}"
    text << "      href: #{href}"
  end
  text.join "\n"
end
