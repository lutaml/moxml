RSpec.shared_examples 'Moxml::Doctype' do
  let(:context) { Moxml.new }
  let(:doc) { context.create_document }
  let(:doctype) do
    doc.create_doctype(
      'html',
      "-//W3C//DTD HTML 4.01 Transitional//EN",
      "http://www.w3.org/TR/html4/loose.dtd"
    )
  end

  it "identifies as doctype node" do
    expect(doctype).to be_doctype
  end

  describe "serialization" do
    it "wraps content in doctype markers" do
      expect(doctype.to_xml).to eq(
        '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'
      )
    end
  end
end
