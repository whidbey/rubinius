module Rubinius
  class Mirror
    def self.subject=(klass)
      @subject = klass
    end

    def self.subject
      @subject
    end

    def self.reflect(obj)
      klass = Rubinius.invoke_primitive :module_mirror, obj
      klass.new obj if klass
    end

    attr_reader :object

    def initialize(obj)
      @object = obj
    end

    class Object < Mirror
      self.subject = ::Object
    end

    def instance_fields
      Rubinius.invoke_primitive :object_instance_fields, @object
    end

    def instance_variables
      Rubinius.invoke_primitive :object_instance_variables, @object
    end

    def inspect
      "#<#{self.class.name}:0x#{self.object_id.to_s(16)} object=#{@object.inspect}>"
    end
  end
end
