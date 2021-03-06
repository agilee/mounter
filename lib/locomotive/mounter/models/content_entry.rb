module Locomotive
  module Mounter
    module Models

      class ContentEntry < Base

        ## fields ##
        field :_slug,               localized: true
        field :_position,           default: 0
        field :_visible,            default: true
        field :seo_title,           localized: true
        field :meta_keywords,       localized: true
        field :meta_description,    localized: true

        field :content_type,        association: true

        attr_accessor :dynamic_attributes

        alias :_permalink :_slug
        alias :_permalink= :_slug=

        ## callbacks ##
        set_callback :initialize, :after, :set_slug

        ## methods ##

        # Return the internal label used to identify a content entry
        # in a YAML file for instance. It is based on the first field
        # of the related content type.
        #
        # @return [ String ] The internal label
        #
        def _label
          name = self.content_type.label_field_name
          self.dynamic_getter(name)
        end

        # Determine if field passed in parameter is one of the dynamic fields.
        #
        # @param [ String/Symbol ] name Name of the dynamic field
        #
        # @return [ Boolean ] True if it is a dynamic field
        #
        def is_dynamic_field?(name)
          name = name.to_s.gsub(/\=$/, '').to_sym
          !self.content_type.find_field(name).nil?
        end

        # Return the value of a dynamic field and cast it depending
        # on the type of the field (string, date, belongs_to, ...etc).
        #
        # @param [ String/Symbol ] name Name of the dynamic field
        #
        # @return [ Object ] The casted value (String, Date, ContentEntry, ...etc)
        #
        def dynamic_getter(name)
          field = self.content_type.find_field(name)

          value = (self.dynamic_attributes || {})[name.to_sym]

          value = value.try(:[], Locomotive::Mounter.locale) unless field.is_relationship? || !field.localized

          case field.type
          when :string, :text, :select, :boolean, :category
            value
          when :date
            value.is_a?(String) ? Date.parse(value) : value
          when :file
            { 'url' => value }
          when :belongs_to
            field.klass.find_entry(value)
          when :has_many
            field.klass.find_entries_by(field.inverse_of, [self._label, self._permalink])
          when :many_to_many
            field.klass.find_entries_among(value)
          end
        end

        # Set the value of a dynamic field. If the value is a hash,
        # it assumes that it represents the translations.
        #
        # @param [ String/Symbol ] name Name of the dynamic field
        # @param [ Object ] value Value to set
        #
        def dynamic_setter(name, value)
          self.dynamic_attributes ||= {}
          self.dynamic_attributes[name.to_sym] ||= {}

          field = self.content_type.find_field(name)

          if value.is_a?(Hash) # already localized
            value.keys.each { |locale| self.add_locale(locale) }
            self.dynamic_attributes[name.to_sym].merge!(value)
          else
            if field.is_relationship? || !field.localized
              self.dynamic_attributes[name.to_sym] = value
            else
              self.add_locale(Locomotive::Mounter.locale)
              self.dynamic_attributes[name.to_sym][Locomotive::Mounter.locale] = value
            end
          end
        end

        # The magic of dynamic fields happens within this method.
        # It calls the getter/setter of a dynamic field if it is one of them.
        def method_missing(name, *args, &block)
          if self.is_dynamic_field?(name)
            if name.to_s.ends_with?('=')
              name = name.to_s.gsub(/\=$/, '').to_sym
              self.dynamic_setter(name, args.first)
            else
              self.dynamic_getter(name)
            end
          else
            super
          end
        end

        # Returns a hash with the label_field value as the key and the other fields as the value
        #
        # @return [ Hash ] A hash of hash
        #
        def to_hash
          # no need of _position and _visible (unless it's false)
          hash = super.delete_if { |k, v| k == '_position' || (k == '_visible' && v == true) }

          # dynamic attributes
          hash.merge!(self.dynamic_attributes.deep_stringify_keys)

          # no need of the translation of the field name in the current locale
          label_field = self.content_type.label_field

          if label_field.localized && !hash[label_field.name].empty?
            hash[label_field.name].delete(Locomotive::Mounter.locale.to_s)

            hash.delete(label_field.name) if hash[label_field.name].empty?
          end

          { self._label => hash }
        end

        # Return the params used for the API.
        #
        # @return [ Hash ] The params
        #
        def to_params
          fields = %w(_slug _position _visible seo_title meta_keywords meta_description)

          # make sure get set, especially, we are using a different locale than the main one.
          self.set_slug

          params = self.attributes.delete_if { |k, v| !fields.include?(k.to_s) || v.blank? }.deep_symbolize_keys

          # TODO

          params
        end

        protected

        # Sets the slug of the instance by using the value of the highlighted field
        # (if available). If a sibling content instance has the same permalink then a
        # unique one will be generated
        def set_slug
          self._slug = self._label.dup if self._slug.blank? && self._label.present?

          if self._slug.present?
            self._slug.permalink!
            self._slug = self.next_unique_slug if self.slug_already_taken?
          end
        end

        # Return the next available unique slug as a string
        #
        # @return [ String] An unique permalink (or slug)
        #
        def next_unique_slug
          slug        = self._slug.gsub(/-\d*$/, '')
          next_number = 0

          self.content_type.entries.each do |entry|
            if entry._permalink =~ /^#{slug}-?(\d*)$/i
              next_number = $1 if $1 > next_number
            end
          end

          [slug, next_number + 1].join('-')
        end

        def slug_already_taken?
          entry = self.content_type.find_entry(self._slug)
          !entry.nil? && entry._slug != self._slug
        end

      end

    end
  end
end