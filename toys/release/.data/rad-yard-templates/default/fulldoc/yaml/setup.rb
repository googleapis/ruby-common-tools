# The very first method that runs in the template folder
def init
  options.serializer = Serializers::FileSystemSerializer.new :extension => "yml"
  toc_items = []
  # yard populates options.objects w/ all classes & modules and also yardoc root
  options.objects.each do |object|
    next if object.root?
    toc_items << object
    serialize object
  end
  copy_files
  toc toc_items
end

def serialize object
  file_name = "#{object.path.gsub "::", "-"}.yml"

  # runs the init method in layout/yaml/setup.rb
  Templates::Engine.with_serializer file_name, options.serializer do
    T('layout').run options.merge(:item => object)
  end
end

def copy_files
  readme_filename = options.readme.filename
  # copy markdown files into the yard output folder
  options.files.each do |file|
    dest_filename = file.filename == readme_filename ? "index.md" : file.filename
    case File.extname dest_filename
    when ".md"
      copy_markdown_file file.filename, dest_filename
    when ".txt", ""
      copy_text_file file.filename, dest_filename
    end
  end
end

def copy_markdown_file source_filename, dest_filename
  source_lines = File.readlines source_filename
  source_lines = ensure_markdown_header source_lines, source_filename
  dest_path = File.join options.serializer.basepath, dest_filename
  File.open dest_path, "w" do |dest|
    in_code_state = 0
    source_lines.each do |line|
      case in_code_state
      when 0
        if line.rstrip == "```ruby"
          in_code_state = 1
          next
        end
      when 1
        line = "<pre class=\"prettyprint lang-rb\">#{line}"
        in_code_state = 2
      when 2
        if line.rstrip == "```"
          in_code_state = 0
          line = "</pre>\n"
        end
      end
      dest.puts line
    end
  end
end

def ensure_markdown_header lines, filename
  lines.shift while lines.first&.empty?
  case lines.first
  when nil, /^##? \S/
    # pass
  when /^###+ (\S.*\n?)$/
    lines[0] = "## #{Regexp.last_match[1]}"
  else
    title = File.basename filename, ".*"
    lines = ["# #{title}\n", "\n"] + lines
  end
  lines
end

def copy_text_file source_filename, dest_filename
  source_content = File.read source_filename
  dest_content = source_content.gsub(/(^|\n+)([^\n])/, "\\1    \\2")
  dest_content = "# #{source_filename}\n\n#{dest_content}"

  base_name = File.basename dest_filename, ".*"
  dest_filename = "#{base_name}.md"
  dest_path = File.join options.serializer.basepath, dest_filename

  File.open dest_path, "w" do |dest|
    dest.puts dest_content
  end
end

def toc objects
  # runs the init method in toc/yaml/setup.rb
  Templates::Engine.with_serializer "toc.yml", options.serializer do
    T('toc').run options.merge(:item => objects)
  end
end
