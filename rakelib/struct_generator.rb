require "rake"
require "rake/tasklib"
require "tempfile"

class StructGenerator
  attr_accessor :size
  attr_reader   :fields

  def initialize
    @struct_name = nil
    @includes = []
    @fields = []
    @found = false
    @size = nil
  end

  def found?
    @found
  end

  def get_field(name)
    @fields.find { |f| name == f.name }
  end

  def self.generate_from_code(code)
    sg = StructGenerator.new
    sg.instance_eval(code)
    sg.calculate
    sg.generate_layout
  end

  def name(n)
    @struct_name = n
  end

  def include(i)
    @includes << i
  end

  def field(name, type=nil)
    fel = Field.new(name, type)
    @fields << fel
    return fel
  end

  def calculate
    binary = "rb_struct_gen_bin_#{Process.pid}"

    raise "struct name not set" if @struct_name.nil?

    Tempfile.open("rbx_struct_gen_tmp") do |f|
      f.puts "#include <stdio.h>"

      @includes.each do |inc|
        f.puts "#include <#{inc}>"
      end

      f.puts "#include <stddef.h>\n\n"
      f.puts "int main(int argc, char **argv)\n{"
      f.puts "  #{@struct_name} s;"
      f.puts %[  printf("sizeof(#{@struct_name}) %u\\n", (unsigned int) sizeof(#{@struct_name}));]

      @fields.each do |field|
        f.puts <<-EOF
  printf("#{field.name} %u %u\\n", (unsigned int) offsetof(#{@struct_name}, #{field.name}),
         (unsigned int) sizeof(s.#{field.name}));
EOF
      end

      f.puts "\n  return 0;\n}"
      f.flush

      if $verbose then
        f.rewind
        $stderr.puts f.read
      end

      `gcc -x c -Wall #{f.path} -o #{binary}`
      if $?.exitstatus == 1
        @found = false
        return
      end
    end

    output = `./#{binary}`.split "\n"
    File.unlink(binary)
    
    sizeof = output.shift
    unless @size
      m = /\s*sizeof\([^)]+\) (\d+)/.match sizeof
      @size = m[1]
    end
    
    line_no = 0
    output.each do |line|
      md = line.match(/.+ (\d+) (\d+)/)
      @fields[line_no].offset = md[1].to_i
      @fields[line_no].size   = md[2].to_i

      line_no += 1
    end
    @found = true
  end

  def generate_config(name)
    @fields.inject(["rbx.platform.#{name}.sizeof = #{@size}"]) do |list, field|
      list.concat field.to_config(name)
    end.join "\n"
  end

  def generate_layout
    buf = ""

    @fields.each_with_index do |field, i|
      if buf.empty?
        buf << "layout :#{field.name}, :#{field.type}, #{field.offset}"
      else
        buf << "       :#{field.name}, :#{field.type}, #{field.offset}"
      end

      if i < @fields.length - 1
        buf << ",\n"
      end
    end

    buf
  end
end

class StructGenerator::Field
  attr_reader :name
  attr_reader :type
  attr_reader :offset
  attr_accessor :size

  def initialize(name, type)
    @name = name
    @type = type
    @offset = nil
  end

  def offset=(o)
    @offset = o
  end

  def to_config(name)
    buf = []
    buf << "rbx.platform.#{name}.#{@name}.offset = #{@offset}"
    buf << "rbx.platform.#{name}.#{@name}.size = #{@size}"
    buf << "rbx.platform.#{name}.#{@name}.type = #{@type}" if @type
    buf
  end
end

module Rake
  class StructGeneratorTask < TaskLib
    attr_accessor :dest

    def initialize
      @dest = nil

      yield self if block_given?

      define
    end

    def define
      task :clean do
        rm_f @dest
      end

      file @dest => %W[#{@dest}.in #{__FILE__}] do |t|
        puts "Generating #{@dest}..."

        file = File.read t.prerequisites.first

        new_file = file.gsub(/^( *)@@@(.*?)@@@/m) do
          indent = $1
          original_lines = $2.count("\n") - 1

          new_lines = StructGenerator.generate_from_code $2
          new_lines = new_lines.split("\n").map { |line| indent + line }
          new_lines += [nil] * (original_lines - new_lines.length)
          new_lines.join "\n"
        end

        File.open(t.name, "w") do |f|
          f.puts "# This file is generated by rake. Do not edit."
          f.puts
          f.puts new_file
        end
      end
    end
  end
end
