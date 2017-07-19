module Mongoid
  module TagsArentHard

    def self.included(klass)
      klass.extend(ClassMethods)
    end

    module ClassMethods

      def taggable_with(name, options = {})
        options = {separator: Mongoid::TagsArentHard.config.separator, _name: name}.merge(options)
        self.field(name, type: Mongoid::TagsArentHard::Tags, default: Mongoid::TagsArentHard::Tags.new([], options))

        self.class.send(:define_method, "enable_#{name}_index!") do |*val|
          @do_tags_index = true
        end

        self.class_eval do
          define_method(name) do
            val = super()
            unless val.is_a?(Mongoid::TagsArentHard::Tags)
              options.merge!(owner: self)
              val = Mongoid::TagsArentHard::Tags.new(val, options)
              self.send("#{name}=", val) unless self.frozen?
            end
            return val
          end
          define_method("#{name}=") do |val|
            unless val.is_a?(Mongoid::TagsArentHard::Tags)
              options.merge!(owner: self)
              val = Mongoid::TagsArentHard::Tags.new(val, options)
            end
            super(val)
          end

          index({name => 1})

          # add callback to save indexes
          after_save do |document|
            document.class.send("save_#{name}_index!") if document.send("#{name}_changed?")
          end
        end

        self.class.send(:define_method, "with_#{name}") do |*val|
          self.send("with_any_#{name}", *val)
        end

        self.class.send(:define_method, "all_#{name}") do
          all.distinct(name.to_s)
        end


        self.class.send(:define_method, "with_any_#{name}") do |*val|
          any_in(name => Mongoid::TagsArentHard::Tags.new(*val, {}).tag_list)
        end

        self.class.send(:define_method, "with_all_#{name}") do |*val|
          all_in(name => Mongoid::TagsArentHard::Tags.new(*val, {}).tag_list)
        end

        self.class.send(:define_method, "without_any_#{name}") do |*val|
          not_in(name => Mongoid::TagsArentHard::Tags.new(*val, {}).tag_list)
        end

        self.class.send(:define_method, "#{name}_like") do |*val|
          self.send("#{name}_index_collection").find(:value => /#{val[0]}/).limit(val[1] || 10).sort(:_id => (val[2] || 1)).map{ |r| [r["value"]] }
        end

        self.class.send(:define_method, "#{name}_with_weight") do |*val|
          self.send("#{name}_index_collection").find.to_a.map{ |r| [r["_id"], r["value"]] }
        end

        self.class.send(:define_method, "#{name}_index_collection_name") do |*val|
          "#{collection_name}_#{name}_index"
        end

        self.class.send(:define_method, "#{name}_index_collection") do |*val|
          Mongo::Collection.new(self.collection.database, self.send("#{name}_index_collection_name"))
        end

        self.class.send(:define_method, "save_#{name}_index!") do |*val|
          map = "function() {
            if (!this.#{name}) {
              return;
            }

            for (index in this.#{name}) {
              emit(this.#{name}[index], 1);
            }
          }"

          reduce = "function(previous, current) {
            var count = 0;

            for (index in current) {
              count += current[index]
            }

            return count;
          }"

          # Since map_reduce is normally lazy-executed, call 'raw'
          # Should not be influenced by scoping. Let consumers worry about
          # removing tags they wish not to appear in index.
          self.unscoped.map_reduce(map, reduce).out(replace: self.send("#{name}_index_collection_name")).raw
        end
      end

    end

  end
end
