describe "OrcidTaxonomist" do
  subject { OrcidTaxonomist }
  let(:ot) { subject.new('', { yaml: REGEX_FILE }) }

  describe ".new" do
    it "works" do
      expect(ot).to be_kind_of OrcidTaxonomist
    end
  end

  def read(file)
    File.read(File.join(__dir__, "files", file))
  end

end
