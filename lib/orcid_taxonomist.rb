# encoding: utf-8

class OrcidTaxonomist

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
    (search_orcids - @db[:taxonomists].map(:orcid)).each do |orcid|
      orcid_url = "https://pub.orcid.org/v2.1/#{orcid}/person"
      req = Typhoeus.get(orcid_url, headers: orcid_header)
      json = JSON.parse(req.body, symbolize_names: true)
      given_names = json[:name][:"given-names"][:value] rescue nil
      family_name = json[:name][:"family-name"][:value] rescue nil
      country = json[:addresses][:address][0][:country][:value] rescue nil
      @db[:taxonomists].insert(
        orcid: orcid,
        given_names: given_names,
        family_name: family_name,
        country: country
      )
    end
  end

  def populate_taxa
    @db[:taxonomists].where(status: 0).each do |t|
      orcid_url = "https://pub.orcid.org/v2.1/#{t[:orcid]}/works"
      req = Typhoeus.get(orcid_url, headers: orcid_header)
      json = JSON.parse(req.body, symbolize_names: true)
      titles = json[:group].map{|a| a[:"work-summary"][0][:title][:title][:value]}.join(" ")
      gnrd_url = "http://gnrd.globalnames.org/name_finder.json"
      begin
        req = Typhoeus.post(gnrd_url, body: { text: titles, unique: true }, followlocation: true)
        json = JSON.parse(req.body, symbolize_names: true)
        if json[:names]
          names = json[:names].map{|o| o[:scientificName]}.compact.uniq.sort
          bulk = Array.new(names.count, t[:id]).zip(names)
          @db[:taxa].import([:taxonomist_id, :taxon], bulk)
        end
      rescue
        puts "taxonomist_id #{t[:id]} scientificName extraction failed"
      end
      @db[:taxonomists].where(id: t[:id]).update(status: 1)
    end
  end

  def write_webpage
    output = {
      generation_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
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
      ORDER BY t.created DESC"
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

  def search_orcids
    orcid_search_url = "https://pub.orcid.org/v2.1/search?q=keyword%3Ataxonomist%20OR%20taxonomy"
    req = Typhoeus.get(orcid_search_url, headers: orcid_header)
    JSON.parse(req.body, symbolize_names: true)[:result]
        .map{|o| o[:"orcid-identifier"][:path]} rescue []
  end

end