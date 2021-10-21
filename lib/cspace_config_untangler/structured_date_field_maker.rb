module CspaceConfigUntangler
  class StructuredDateFieldMaker
    attr_reader :profile, :rectype, :ns, :ns_for_id, :panel, :ui_path,
      :schema_path,
      :repeats, :in_repeating_group,
      :required

    def initialize(field_obj)
      @parent = field_obj
      @profile = @parent.profile
      @rectype = @parent.rectype
      @ns = @parent.ns
      @ns_for_id = 'ext.structuredDate'
      @panel = @parent.panel
      @ui_path = @parent.ui_path << @parent.id
      @schema_path = @parent.schema_path << @parent.name
      @repeats = 'n'
      @in_repeating_group = set_group_repeats
      @required = 'n'
    end

    def fields(profile_obj)
      sdfields = profile_obj.messages.keys.select{ |e| e['structuredDate'] }.map{ |e| e.sub('field.', '') }
      return sdfields.map{ |sdf| CCU::StructuredDateField.new(profile_obj, self, sdf) }
    end

    private

    def set_group_repeats
      if @parent.repeats == 'y'
        return 'y'
      elsif @parent.in_repeating_group == 'y'
        return 'as part of larger repeating group'
      elsif @parent.in_repeating_group == 'n/a'
        return 'n'
      end
    end
    
  end #class
end #module
