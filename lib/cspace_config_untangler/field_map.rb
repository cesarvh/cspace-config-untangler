require 'cspace_config_untangler'

module CspaceConfigUntangler
  module FieldMap
    class FieldMapping
      ::FieldMapping = CspaceConfigUntangler::FieldMap::FieldMapping
      include CCU::TrackAttributes
      attr_reader :fieldname, :transforms, :source_type, :source_name, :namespace, :xpath, :data_type,
        :repeats, :in_repeating_group, :opt_list_values
      attr_accessor :datacolumn, :required
      def initialize(field:, datacolumn:, transforms: {}, source_type:, source_name:)
        @fieldname = field.name
        @namespace = field.ns.sub('ns2:', '')
        @xpath = field.schema_path
        @required = field.required
        @repeats = field.repeats
        @in_repeating_group = field.in_repeating_group
        @datacolumn = datacolumn
        @source_type = source_type
        @source_name = source_name
        @transforms = transforms
        @opt_list_values = field.value_list
        @data_type = @datacolumn['Refname'] ? 'csrefname' : field.data_type
      end

      def to_h
        readable = self.attr_readers
        accessible = self.attr_accessors
        attrs = readable + accessible
        
        ivs = attrs.flatten.map{ |e| '@' + e.to_s }.map{ |e| e.to_sym }
        h = {}
        attrs.each_with_index{ |a, i| h[a.to_sym] = self.instance_variable_get(ivs[i]) }
        return h
      end
    end

    # given a CSpace field, will generate one or more FieldMapping objects (which relate to incoming data key/columns)
    class FieldMapper
      ::FieldMapper = CspaceConfigUntangler::FieldMap::FieldMapper
      attr_reader :mappings, :hash, :source_type
      def initialize(field:, column_style: :consistent)
        @field = field
        @column_style = column_style
        @hash = structure_hash
        get_data_columns
        get_source_type
        get_transforms
        @mappings = create_mappings
      end

      private

      def structure_hash
        h = {}
        sources = @field.value_source.blank? ? ['no source'] : @field.value_source
        sources.each do |vs|
          h[vs] = { column_name: '',
                   transforms: {},
                   source_type: ''}
        end
        h
      end
      
      def get_source_type
        types = []
        @hash.each do |source, h|
          if source.start_with?('authority')
            h[:source_type] = 'authority'
          elsif source.start_with?('vocabulary')
            h[:source_type] = 'vocabulary'
          elsif source.start_with?('option list')
            h[:source_type] = 'optionlist'
          elsif source.start_with?('other')
            h[:source_type] = 'invalid source type'
          elsif source['refname']
            h[:source_type] = source.delete('refname')
          else
            h[:source_type] = 'na'
          end
          types << h[:source_type]
        end
        @source_type = types[0]
      end

      def get_transforms
        @hash.each do |source, h|
          xform = { special: []}
          if source['refname']
            #do nothing
          elsif source.start_with?('authority: ')
            xform[:authority] = AuthorityConfigLookup.new(profile: @field.profile,
                                                          authority: source).result
          elsif source.start_with?('vocabulary: ')
            xform[:vocabulary] = source.sub('vocabulary: ', '')
            xform[:special] << 'behrensmeyer_translate' if @field.name.downcase['behrensmeyer']
          elsif @field.data_type == 'boolean'
            xform[:special] << 'boolean'
          end

          xform.delete(:special) if xform[:special].empty?
          
          h[:transforms] = h[:transforms].merge(xform)
        end
      end
      
      def create_mappings
        mappings = []
        @hash.each do |source, h|
          mappings << FieldMapping.new(field: @field,
                                       datacolumn: h[:column_name],
                                       transforms: h[:transforms],
                                       source_type: h[:source_type],
                                       source_name: h[:source_name])
        end
        mappings
      end
      
      def get_data_columns
        value_source = @field.value_source
        if value_source.blank?
          @hash['no source'] = { column_name: @field.name, transforms: {} }
        elsif value_source.size == 1
          vs = value_source.first
          source_name = get_source_name(vs)
          @hash[vs] = { column_name: @field.name, transforms: {}, source_name: source_name }
          unless vs['option list']
            @hash["#{vs}refname"] = { column_name: "#{@field.name}Refname", transforms: {}, source_name: source_name }
          end
        else #multiple sources
          namer_opts = {fieldname: @field.name, sources: transform_sources(value_source)}
          namer = @column_style == :fancy ? DataColumnNamerFancy.new(**namer_opts) : DataColumnNamerConsistent.new(**namer_opts)
          namer.result.each do |src, colname|
            @hash[src][:column_name] = colname
            @hash[src][:transforms] = {}
            @hash[src][:source_name] = get_source_name(src)
          end
          @hash["#{value_source.first}refname"] = {
            column_name: "#{@field.name}Refname",
            transforms: {},
            source_name: value_source.map{ |s| get_source_name(s) }.join('; ')
          }
        end
      end

      def transform_sources(sources)
        sources.map{|source| AuthoritySource.new(source) }
      end

      def get_source_name(source)
        if source.is_a?(AuthoritySource)
          source.string
        else
          source.sub(/^(option list|authority|vocabulary): /, '')
        end
      end
    end #class FieldMapper

    class AuthoritySource
      ::AuthoritySource = CspaceConfigUntangler::FieldMap::AuthoritySource
      attr_reader :type, :subtype, :string

      def initialize(value_source)
        @string = value_source
        split = value_source.sub('authority: ', '').split('/')
        @type = split[0]
        @subtype = split[1]
      end
    end
    
    class AuthorityConfigLookup
      ::AuthorityConfigLookup = CspaceConfigUntangler::FieldMap::AuthorityConfigLookup
      attr_reader :result
      def initialize(profile:, authority:)
        source = authority.sub('authority: ', '').split('/')
        authtype = source[0]
        authsubtype = source[1]
        path = profile.config.dig('recordTypes', authtype, 'serviceConfig', 'servicePath')
        subpath = profile.config.dig('recordTypes', authtype, 'vocabularies', authsubtype,
                                     'serviceConfig', 'servicePath')
        subpath = subpath.match(/\((.*)\)$/)[1]
        @result = [path, subpath]
      end
    end
  end
end
