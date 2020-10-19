require 'cspace_config_untangler'

module CspaceConfigUntangler
  class CommandLine < Thor
    def initialize(*args)
      super(*args)
    end

    no_commands{
      def get_profiles
        all_profiles = [CCU::MAINPROFILE, CCU::PROFILES].flatten.uniq
        if options[:profiles].empty?
          return [CCU::MAINPROFILE]
        elsif options[:profiles] == 'all'
          return all_profiles
        else
          profiles = options[:profiles].split(',').map(&:strip)
          real_profiles = []
          profiles.each{ |p|
            if all_profiles.include?(p)
              real_profiles << p
            else
              puts "Unknown profile \"#{p}\" will be ignored..."
            end
          }
          return real_profiles.uniq
        end
      end
    }

    class_option :profiles,
      desc: 'Comma-separated list (NO SPACES) of non-main profiles you want to process. If not set, will run main profile only. If "all", will run all known profiles.',
      type: 'string',
      default: CCU::MAINPROFILE,
      aliases: '-p'
    
    desc 'main_profile', 'Print the name of the main profile'
    def main_profile
      puts CCU::MAINPROFILE
    end

    desc 'all_profiles', 'Print the names of all known profiles'
    def all_profiles
      puts [CCU::MAINPROFILE, CCU::PROFILES].flatten.uniq.sort
    end

    desc 'check_profiles', 'Print the names of profiles that will be processed'
    def check_profiles
      profiles = get_profiles
      puts profiles
    end

    desc 'list_rec_types', 'Lists record types in each profile'
    def list_rec_types
      get_profiles.each{ |p|
        puts "\n#{p}:"
        puts CCU::Profile.new(profile: p).rectypes.map{ |e| "  #{e.name}" }
      }
    end

    desc 'readable_profiles', 'Reformats (in place) JSON profile configs so that they are not one very long line. Non-destructive if run over JSON multiple times.'
    def readable_profiles
      get_profiles.each{ |p|
        profile = CCU::Profile.new(profile: p).config
        File.open("#{CCU::CONFIGDIR}/#{p}.json", 'w'){ |f|
          f.puts JSON.pretty_generate(profile)
        }
      }
    end

    desc 'write_mappers', 'Writes JSON serializations of RecordMappers for the given rectype(s) for the given profiles'
    option :rectypes, desc: 'Comma-delimited (no spaces) list of record types to write mappers for. If blank, will process all record types in profile', default: '', aliases: '-r' 
    option :outputdir, desc: 'Path to output directory. File name will be: profile-rectype.json', default: 'data/mappers', aliases: '-o'
    option :subdirs, desc: 'y/n. Whether to organize into subdirectories within given output directory by normalized profile name. Normalized profile name is the profile with version info/underscores removed.', default: 'n', aliases: '-s'
    def write_mappers
      rts = options[:rectypes].split(',').map(&:strip)
      get_profiles.each do |profile|
        puts "Writing mappers for #{profile}..."
        norm_name = profile.sub(/_.*/, '')
        p = CCU::Profile.new(profile: profile, rectypes: rts, structured_date_treatment: :collapse)
        dir_path = options[:subdirs] == 'y' ? "#{options[:outputdir]}/#{norm_name}" : options[:outputdir]
        FileUtils.mkdir_p(dir_path)
        p.rectypes.each do |rt|
          puts "  ...#{rt.name}"
          recmapper = RecordMapping.new(profile: p,
                                        rectype: rt
                                       )
          path = "#{dir_path}/#{p.name}-#{rt.name}.json"
          recmapper.to_json(output: path)
        end
      end
    end

    desc 'write_csv_templates', 'Write batch import CSV templates for given (or all) record types in the given profiles'
    option :rectypes, desc: 'Comma-delimited (no spaces) list of record types to create templates for; if blank, will process all record types in profile', default: '', aliases: '-r'
    option :outputdir, desc: 'Path to output directory. File name will be: profile-rectype_template.csv', default:'data/templates', aliases: '-o'
    option :subdirs, desc: 'y/n. Whether to organize into subdirectories within given output directory by normalized profile name. Normalized profile name is the profile with version info/underscores removed.', default: 'n', aliases: '-s'
    def write_csv_templates
      rts = options[:rectypes].split(',').map(&:strip)
      get_profiles.each do |profile|
        puts "Writing templates for #{profile}..."
        norm_name = profile.sub(/_.*/, '')
        p = CCU::Profile.new(profile: profile, rectypes: rts, structured_date_treatment: :collapse)
        dir_path = options[:subdirs] == 'y' ? "#{options[:outputdir]}/#{norm_name}" : options[:outputdir]
        FileUtils.mkdir_p(dir_path)
        p.rectypes.each do |rt|
          puts "  ...#{rt.name}"
          CsvTemplate.new(profile: p,
                          rectype: rt
                         ).write(dir_path)
        end
      end
    end

    desc 'validate_mappers', 'Prints to screen a validation report of the JSON mappers in a directory'
    long_desc <<-LONGDESC
    The output directory given will be recursively traversed to find .json files. It is
      expected that all .json files in this directory structure will be RecordMappers.

    Currently the validation checks for:
      - expected top-level keys
      - a URI for every namespace defined for the Mapper
      - a namespace defined for every field mapping
  LONGDESC
    option :input, desc: 'Path to input directory containing JSON mappers. Will be traversed recursively', default: 'data/mappers', aliases: '-i'
    def validate_mappers
      mapper_paths = Dir.glob("#{options[:input]}/**/*.json")
      mapper_paths.each do |path|
        validator = RecordMapper::Validator.new(path)
        validator.report
      end
      puts "\n\nAll mappers validated. Any errors were reported above. Nothing above means all are valid!"
    end

    desc 'extensions_by_profile', 'List all extensions used in profiles, and list which profile uses each'
    def extensions_by_profile
      exts = {}
      get_profiles.each{ |p|
        CCU::Profile.new(profile: p).extensions.each{ |ext|
          if exts.has_key?(ext)
            exts[ext] << p
          else
            exts[ext] = [p]
          end
        }
      }
      pp(exts)
    end

    desc 'write_field_defs', 'Write file containing field definition data'
    option :rectype, desc: 'Comma separated list (no spaces) of record types to include. Defaults to all.', default: 'all', aliases: '-r'
    option :format, desc: 'Output format: csv or json', default: 'csv', aliases: '-f'
    option :output, desc: 'Path to output file', default: 'data/field_definitions.csv', aliases: '-o'
    def write_field_defs
      field_defs = []
      get_profiles.each {|profile|
        p = CCU::Profile.new(profile: profile)
        if options[:rectype] == 'all'
          rts = p.rectypes.map{ |rt| rt.name }
        else
          rts = options[:rectype].split(',').map{ |e| e.strip }  
        end
        p.field_defs.each{ |id, arr|
          arr.each{ |fd| field_defs << fd if rts.include?(fd.rectype) }
        }
      }

      case options[:format]
      when 'csv'
        CSV.open(options[:output], 'wb'){ |csv|
          csv << field_defs[0].csv_header
          field_defs.each{ |fd| csv << fd.to_csv }
        }
      when 'json'
        File.open(options[:output], 'w'){ |file|
          file.write(JSON.pretty_generate(field_defs.map{ |fd| fd.to_h }))
        }
      else
        puts 'Format must be csv or json'
      end
    end

    desc 'write_form_fields', 'Write file containing form field data'
    option :rectype, desc: 'Comma separated list (no spaces) of record types to include. Defaults to all.', default: 'all', aliases: '-r'
    option :format, desc: 'Output format: csv or json', default: 'csv', aliases: '-f'
    option :output, desc: 'Path to output file', default: 'data/form_fields.csv', aliases: '-o'
    def write_form_fields
      form_fields = []
      get_profiles.each {|profile|
        p = CCU::Profile.new(profile: profile)
        if options[:rectype] == 'all'
          rts = p.rectypes.map{ |rt| rt.name }
        else
          rts = options[:rectype].split(',').map{ |e| e.strip }  
        end
        p.form_fields.each{ |ff| form_fields << ff if rts.include?(ff.rectype) }
      }

      case options[:format]
      when 'csv'
        CSV.open(options[:output], 'wb'){ |csv|
          csv << form_fields[0].csv_header
          form_fields.each{ |ff| csv << ff.to_csv }
        }
      when 'json'
        File.open(options[:output], 'w'){ |file|
          file.write(JSON.pretty_generate(form_fields.map{ |ff| ff.to_h }))
        }
      else
        puts 'Format must be csv or json'
      end
    end

    desc 'write_fields_csv', 'Write CSV containing full field data'
    option :output, desc: 'Path to output file', default: 'data/fields.csv', aliases: '-o'
    option :rectypes, desc: 'Comma separated list (no spaces) of record types to include. Defaults to all.', default: 'all', aliases: '-r'
    option :structured_date,
      desc: 'explode: report all individual structured date fields; collapse: report the parent of individual structured date fields as the field',
      default: 'explode',
      aliases: '-sd'
    def write_fields_csv
      unless %w[explode collapse].include?(options[:structured_date])
        puts '--structured_date parameter must be either "explode" or "collapse"'
        exit
      end
      rt = options[:rectypes] == 'all' ? [] : options[:rectypes].split(',')
      fs = []
      get_profiles.each {|profile|
        p = CCU::Profile.new(profile: profile, rectypes: rt, structured_date_treatment: options[:structured_date].to_sym)
        p.fields.each{ |f| fs << f }
      }
      CSV.open(options[:output], 'wb'){ |csv|
        csv << fs[0].csv_header
        fs.each{ |f| csv << f.to_csv }
      }
    end

    desc 'report_nonunique_fields', 'Print list of non-unique fields per profile'
    long_desc <<-LONGDESC
Uniqueness is determined by the full XML schema, i.e. the schema_path plus the field name.

The full schema_path should be unique within a record type. Non-unique fields are unexpected and the profile, record type, and schema path will be printed to the screen if any are found.
  LONGDESC
    def report_nonunique_fields
      get_profiles.each {|profile|
        p = CCU::Profile.new(profile: profile)
        h = {}
        p.nonunique_fields.each{ |rt, fields| h[rt] = fields if fields.length > 0 }
        h.each{ |rt, fields| fields.each{ |f| puts "#{@name} - #{rt} - #{f}" } }
      }
    end
    
    desc 'compare_profiles', 'Outputs a comparison of two profiles in CSV format'
    option :output, desc: 'Path to directory in which to output file. Name of the file is hardcoded, using the names of the profiles.', default: 'data', aliases: '-o'
    def compare_profiles
      if options[:profiles] == 'all'
        profiles = get_profiles
      else
        profiles = options[:profiles].split(',').map{ |p| p.strip }
      end
      
      if profiles.length > 2
        puts "Can only compare two profiles at a time"
        exit
      elsif profiles.length == 1
        puts "Needs two profiles to compare"
        exit
      else
        CCU::ProfileComparison.new(profiles, options[:output]).write_csv
      end
    end

    desc 'test', 'temporary stuff for expediency'
    def test
      profile = 'botgarden_1_0_0'
      rt = 'collectionobject'
      rm = RecordMapping.new(profile: profile, rectype: rt)
      
    end
  end #class Thor::CommandLine
end #module
