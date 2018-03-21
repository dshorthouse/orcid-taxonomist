# encoding: utf-8

class OrcidTaxonomist

  ORCID_API = "https://pub.orcid.org/v2.1"
  GNRD_API = "http://gnrd.globalnames.org/name_finder.json"

  def initialize args
    args.each do |k,v|
      instance_variable_set("@#{k}", v) unless v.nil?
    end
    @config = parse_config
    @db = Sequel.connect(
      adapter: @config[:adapter],
      user: @config[:username],
      host: @config[:host],
      database: @config[:database],
      password: @config[:password]
      )
  end

  def populate_taxonomists
    (search_orcids.to_a - @db[:taxonomists].map(:orcid)).each do |orcid|
      o = orcid_metadata(orcid)
      @db[:taxonomists].insert(
        orcid: orcid,
        given_names: o[:given_names],
        family_name: o[:family_name],
        country: o[:country],
        orcid_created: o[:orcid_created],
        orcid_updated: o[:orcid_updated]
      )
    end
  end

  def populate_taxa
    @db[:taxonomists].where(status: 0).each do |t|
      works = orcid_works(t[:orcid])
      scientific_names = gnrd_names(works.join(" "))
      if scientific_names
        bulk = Array.new(scientific_names.count, t[:id]).zip(scientific_names)
        @db[:taxa].import([:taxonomist_id, :taxon], bulk)
      end
      @db[:taxonomists].where(id: t[:id]).update(status: 1)
    end
  end

  def write_webpage
    output = {
      entries: []
    }
    sql = "SELECT 
        t.id,
        t.orcid,
        t.given_names,
        t.family_name,
        t.country,
        t.created 
      FROM 
        taxonomists t
      ORDER BY t.family_name"
    @db[sql].each do |row|
      if row[:country]
        code = IsoCountryCodes.find(row[:country])
        row[:country] = code.name if code
      end
      extras = { 
        taxa: @db[:taxa].where(taxonomist_id: row[:id])
                        .all.map{ |t| t[:taxon] }
                        .compact.sort.join(", ")
      }
      output[:entries] << row.merge(extras)
    end
    template = File.join(root, 'template', "template.slim")
    web_page = File.join(root, 'index.html')
    html = Slim::Template.new(template).render(Object.new, output)
    File.open(web_page, 'w') { |file| file.write(html) }
    html
  end

  def update_taxonomists
    @db[:taxonomists].each do |t|
      o = orcid_metadata(t[:orcid])
      if t[:orcid_updated] != o[:orcid_updated]
        existing_taxa = @db[:taxa].where(taxonomist_id: t[:id]).map(:taxa)
        works = orcid_works(t[:orcid])
        scientific_names = gnrd_names(works.join(" ")) - existing_taxa
        if !scientific_names.empty?
          bulk = Array.new(scientific_names.count, t[:id]).zip(scientific_names)
          @db[:taxa].import([:taxonomist_id, :taxon], bulk)
        end
        @db[:taxonomists].where(id: t[:id]).update(o)
      end
    end
  end

  private

  def root
    File.dirname(File.dirname(__FILE__))
  end

  def parse_config
    config = YAML.load_file(@config_file).deep_symbolize_keys!
    env = ENV.key?("ENVIRONMENT") ? ENV["ENVIRONMENT"] : "development"
    config[env.to_sym]
  end

  def orcid_header
    { 'Accept': 'application/orcid+json' }
  end

  def orcid_metadata(orcid)
    orcid_url = "#{ORCID_API}/#{orcid}/person"
    req = Typhoeus.get(orcid_url, headers: orcid_header)
    json = JSON.parse(req.body, symbolize_names: true)
    given_names = json[:name][:"given-names"][:value] rescue nil
    family_name = json[:name][:"family-name"][:value] rescue nil
    country = json[:addresses][:address][0][:country][:value] rescue nil
    orcid_created = json[:name][:"created-date"][:value] rescue nil
    orcid_updated = json[:"last-modified-date"][:value] rescue nil
    {
      given_names: given_names,
      family_name: family_name,
      country: country,
      orcid_created: orcid_created,
      orcid_updated: orcid_updated
    }
  end

  def orcid_works(orcid)
    orcid_url = "#{ORCID_API}/#{orcid}/works"
    req = Typhoeus.get(orcid_url, headers: orcid_header)
    json = JSON.parse(req.body, symbolize_names: true)
    json[:group].map{|a| a[:"work-summary"][0][:title][:title][:value]} rescue []
  end

  def gnrd_names(text)
    req = Typhoeus.post(GNRD_API, body: { text: text, unique: true }, followlocation: true)
    json = JSON.parse(req.body, symbolize_names: true)
    json[:names].map{|o| o[:scientificName]}.compact.uniq.sort rescue []
  end

  def search_orcids
    Enumerator.new do |yielder|
      start = 1

      loop do
        orcid_search_url = "#{ORCID_API}/search?q=keyword%3Ataxonomist%20OR%20keyword:taxonomy&start=#{start}&rows=100"
        req = Typhoeus.get(orcid_search_url, headers: orcid_header)
        results = JSON.parse(req.body, symbolize_names: true)[:result]

        if results
          results.map { |item| yielder << item[:"orcid-identifier"][:path] }
          start += 100
        else
          raise StopIteration
        end
      end
    end.lazy
  end

end