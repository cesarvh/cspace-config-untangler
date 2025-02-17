require_relative 'properties'

module CspaceConfigUntangler
  module Forms
    class Form
      ::CCU::Form = CspaceConfigUntangler::Forms::Form
      attr_reader :rectype, :name, :config, :fields

      def initialize(rectypeobj, formname)
        @rectype = rectypeobj
        @name = formname
        @config = get_config
        @fields = []
        get_form_fields
        # This logic loop prevents failure for of publicart work due to an inconsistency in the config
        #  described at https://collectionspace.atlassian.net/browse/DRYD-882
        if @rectype.profile.name.start_with?('publicart') && @rectype.name == 'work'
          @fields = @fields.reject{ |f| f.name == 'addressCounty' }
        end
      end

      private

      def get_config
        return @rectype.config['forms'][@name]['template']['props']
      end

      def get_form_fields
        CCU::Forms::Properties.new(self, @config)
      end
    end
  end
end
