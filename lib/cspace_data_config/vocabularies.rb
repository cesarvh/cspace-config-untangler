require 'cspace_data_config'

module CspaceDataConfig
  class ProfileVocabularies
    attr_reader :list
    attr_reader :profile

    # profiles = array of profile name strings
    def initialize(profile)
      @profile = profile
      @list = []
      get_profile_vocabularies
    end

    private

    def get_profile_vocabularies
      config = CDC::Config.new(profile)
      doc = Nokogiri::XML(config.rest('/vocabularies?pgSz=0'))
      doc.xpath('//shortIdentifier').each{ |e| @list << e.text }
    end
  end #class ProfileAuthorities
end #module
