module ASpaceExport
  # Convenience methods that will work for resource
  # or archival_object models during serialization
  module ArchivalObjectDescriptionHelpers
    def ead_extents
      unless @ead_extents
        array = []
        extents = self.extents || []
        extents.each do |e|
          if e['container_summary']
            array << e['container_summary']
          end
          if e['number'] && e['extent_type']
            array << "#{e['number']} #{I18n.t('enumerations.extent_extent_type.'+e['extent_type'], :default => e['extent_type'])}"
          end
        end
        @ead_extents = array
      end

      @ead_extents
    end


    def controlaccess_linked_agents
      unless @controlaccess_linked_agents
        results = []
        linked = self.linked_agents || []
        linked.each do |link|

          role = link['relator'] ? link['relator'] : (link['role'] == 'source' ? 'fmo' : nil)

          agent = link['_resolved']
          sort_name = agent['names'][0]['sort_name']
          rules = agent['names'][0]['rules']
          source = agent['names'][0]['source']

          content = sort_name

          if link['terms'].length > 0
            content << " -- "
            content << link['terms'].map{|t| t['term']}.join(' -- ')
          end

          node_name = case agent['agent_type']
                      when 'agent_person'; 'persname'
                      when 'agent_family'; 'famname'
                      when 'agent_corporate_entity'; 'corpname'
                      end

          atts = {}
          atts[:role] = role if role
          atts[:source] = source if source
          atts[:rules] = rules if rules

          results << {:node_name => node_name, :atts => atts, :content => content}
        end

        @controlaccess_linked_agents = results
      end

      @controlaccess_linked_agents
    end


    def controlaccess_subjects
      unless @controlaccess_subjects
        results = []
        linked = self.subjects || []
        linked.each do |link|
          subject = link['_resolved']

          node_name = case subject['terms'][0]['term_type']
                      when 'function'; 'function'
                      when 'genre_form' || 'style_period';  'genreform'
                      when 'geographic'|| 'cultural_context'; 'geogname'
                      when 'occupation';  'occupation'
                      when 'topical'; 'subject'
                      when 'uniform_title'; 'title'
                      else; nil
                      end

          next unless node_name

          content = subject['terms'].map{|t| t['term']}.join(' -- ')

          atts = {}
          atts['source'] = subject['source'] if subject['source']

          results << {:node_name => node_name, :atts => atts, :content => content}
        end

        @controlaccess_subjects = results
      end

      @controlaccess_subjects
    end


    def archdesc_dates
      unless @archdesc_dates
        results = []
        dates = self.dates || []
        dates.each do |date|
          normal = "#{date['begin']}/"
          normal += (date['date_type'] == 'single' || date['end'].nil? || date['end'] == date['begin']) ? date['begin'] : date['end']
          type = %w(single inclusive).include?(date['date_type']) ? 'inclusive' : 'bulk'
          content = if date['expression']
                    date['expression']
                  elsif date['date_type'] == 'bulk'
                    'bulk'
                  elsif date['end'].nil? || date['end'] == date['begin']
                    date['begin']
                  else
                    "#{date['begin']}-#{date['end']}"
                  end

          atts = {:type => type}
          atts[:normal] = normal unless normal.empty?

          results << {:content => content, :atts => atts}
        end

        @archdesc_dates = results
      end

      @archdesc_dates
    end
  end
end


ASpaceExport::model :ead do
  include ASpaceExport::ArchivalObjectDescriptionHelpers

  @data_src = Class.new do
    def initialize(json)
      @json = json
    end


    def method_missing(meth)
      if @json.respond_to?(meth)
        @json.send(meth)
      elsif @json.is_a?(Hash) && @json.has_key?("#{meth.to_s}")
        @json["#{meth.to_s}"]
      else
        nil
      end
    end
  end


  def self.data_src(json)
    @data_src.new(json)
  end


  @ao = Class.new do
    include ASpaceExport::ArchivalObjectDescriptionHelpers

    def initialize(tree)
      rec = URIResolver.resolve_references(ArchivalObject.to_jsonmodel(tree['id']), ['subjects', 'linked_agents'], {'ASPACE_REENTRANT' => false})
      @json = JSONModel::JSONModel(:archival_object).new(rec)
      @tree = tree
    end

    def method_missing(meth, *args)
      if @json.respond_to?(meth)
        @json.send(meth, *args)
      else
        nil
      end
    end

    def children
      return nil unless @tree['children']
      @tree['children'].map { |subtree| self.class.new(subtree) }
    end
  end


  def initialize(obj)
    @json = obj
    repo_ref = obj.repository['ref']
    repo_id = JSONModel::JSONModel(:repository).id_for(repo_ref)
    @repo = Repository.to_jsonmodel(repo_id)
  end


  def archdesc_note_types
    %w(accruals appraisal arrangement bioghist accessrestirct userestrict custodhist altformavail originalsloc fileplan odd acqinfo otherfindaid phystech prefercite processinfo relatedmaterial scopecontent separatedmaterial)
  end


  def bibliographies
    self.notes.select{|n| n['jsonmodel_type'] == 'note_bibliography'}
  end


  def indexes
    self.notes.select{|n| n['jsonmodel_type'] == 'note_index'}
  end


  def index_item_type_map
    {
      'corporate_entity'=> 'corpname',
      'genre_form'=> 'genreform',
      'name'=> 'name',
      'occupation'=> 'occupation',
      'person'=> 'persname',
      'subject'=> 'subject',
      'family'=> 'famname',
      'function'=> 'function',
      'geographic_name'=> 'geogname',
      'title'=> 'title'
    }
  end


  def self.from_aspace_object(obj)
    ead = self.new(obj)

    ead
  end


  def self.from_resource(obj)
    ead = self.from_aspace_object(obj)

    ead
  end


  def method_missing(meth)
    if self.instance_variable_get("@#{meth.to_s}")
      self.instance_variable_get("@#{meth.to_s}")
    elsif @json.respond_to?(meth)
      @json.send(meth)
    else
      nil
    end
  end


  def children
    return nil unless @json.tree['_resolved']['children']

    ao_class = self.class.instance_variable_get(:@ao)

    children = @json.tree['_resolved']['children'].map { |subtree| ao_class.new(subtree) }

    children
  end


  def mainagencycode
    @mainagencycode ||= repo.country && repo.org_code ? [repo.country, repo.org_code].join('-') : nil
    @mainagencycode
  end


  def agent_representation
    return false unless @repo['agent_representation_id']

    agent_id = @repo['agent_representation_id']
    json = AgentCorporateEntity.to_jsonmodel(agent_id)

    json
  end


  def addresslines
    agent = self.agent_representation
    return [] unless agent

    contact = agent.agent_contacts[0]

    data = []
    (1..3).each do |i|
      data << contact["address_#{i}"]
    end

    line = ""
    line += %w(city region).map{|k| contact[k] }.compact.join(', ')
    line += " #{contact['post_code']}"
    line.strip!

    data <<  line unless line.empty?

    %w(telephone email).each do |property|
      data << contact[property]
    end

    data.compact!

    data
  end


  def descrules
    return nil unless @descrules || self.finding_aid_description_rules
    @descrules ||= I18n.t("enumerations.resource_finding_aid_description_rules.#{self.finding_aid_description_rules}", :default => self.finding_aid_description_rules)
    @descrules
  end


  def ead_containers
    unless @ead_containers
      data = []
      self.instances.each do |inst|
        cont = inst['container']
        (1..3).each do |i|
          next unless cont.has_key?("type_#{i}") && cont.has_key?("indicator_#{i}")
          data << {:type => cont["type_#{i}"], :text => cont["indicator_#{1}"]}
          if i == 1 && inst['instance_type']
            data.last[:label] = I18n.t("enumerations.instance_instance_type.#{inst['instance_type']}",:default => inst['instance_type'])
          end
        end
      end
      @ead_containers = data
    end

    @ead_containers
  end


  def creators_and_sources
    self.linked_agents.select{|link| ['creator', 'source'].include?(link['role']) }
  end


  def digital_objects
    self.instances.select{|inst| inst['digital_object']}.compact.map{|inst| inst['digital_object']['_resolved'] }.compact
  end
end
