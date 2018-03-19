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

  def search_orcids
    orcid_search_url = "https://pub.orcid.org/v2.1/search?q=keyword%3Ataxonomist"
    req = Typhoeus.get(orcid_search_url, headers: orcid_header)
    JSON.parse(req.body, symbolize_names: true)[:result]
        .map{|o| o[:"orcid-identifier"][:path]} rescue []
  end

  def populate_taxonomists
    (search_orcids - @db[:taxonomists].map(:orcid)).each do |orcid|
      orcid_url = "https://pub.orcid.org/v2.1/#{orcid}"
      req = Typhoeus.get(orcid_url, headers: orcid_header)
      json = JSON.parse(req.body, symbolize_names: true)
      given_names = json[:person][:name][:"given-names"][:value] rescue nil
      family_name = json[:person][:name][:"family-name"][:value] rescue nil
      @db[:taxonomists].insert(orcid: orcid, given_names: given_names, family_name: family_name)
    end
  end

  def populate_works
  end

  def write_webpage
    output = {
      generation_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
      entries: []
    }
    sql = "SELECT 
        t.orcid,
        t.given_names,
        t.family_name,
        t.created 
      FROM 
        taxonomists t 
      LEFT JOIN 
        works w ON (t.id = w.taxonomist_id) 
      ORDER BY t.created DESC"
    @db[sql].each do |row|
      output[:entries] << row
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

end