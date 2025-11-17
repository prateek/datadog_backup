# frozen_string_literal: true

require 'spec_helper'

describe DatadogBackup::Notebooks do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:api_client_double) { Faraday.new { |f| f.adapter :test, stubs } }
  let(:tempdir) { Dir.mktmpdir }
  let(:notebooks) do
    notebooks = described_class.new(
      action: 'backup',
      backup_dir: tempdir,
      output_format: :json,
      resources: []
    )
    allow(notebooks).to receive(:api_service).and_return(api_client_double)
    notebooks
  end
  let(:first_notebook) do
    {
      'type' => 'notebooks',
      'id' => 11_111,
      'attributes' => {
        'name' => 'Example notebook',
        'cells' => [
          {
            'attributes' => {
              'definition' => {
                'type' => 'markdown',
                'text' => '## A heading'
              }
            }
          }
        ],
        'status' => 1,
        'time' => { 'live_span' => '1h' }
      }
    }
  end
  let(:second_notebook) do
    {
      'type' => 'notebooks',
      'id' => 22_222,
      'attributes' => {
        'name' => 'Another notebook',
        'cells' => [
          {
            'attributes' => {
              'definition' => {
                'type' => 'markdown',
                'text' => 'Second cell'
              }
            }
          }
        ],
        'status' => 2,
        'time' => { 'live_span' => '1w' }
      }
    }
  end
  let(:all_notebooks) { respond_with200({ 'data' => [first_notebook, second_notebook] }) }
  let(:first_notebook_response) { respond_with200({ 'data' => first_notebook }) }
  let(:second_notebook_response) { respond_with200({ 'data' => second_notebook }) }

  before do
    stubs.get('/api/v1/notebooks') { all_notebooks }
    stubs.get('/api/v1/notebooks/11111') { first_notebook_response }
    stubs.get('/api/v1/notebooks/22222') { second_notebook_response }
  end

  describe '#all' do
    subject(:all) { notebooks.all }

    it { is_expected.to contain_exactly(first_notebook, second_notebook) }
  end

  describe '#backup' do
    it 'writes each notebook to disk' do
      first_file = instance_double(File)
      allow(File).to receive(:open).with(notebooks.filename(11_111), 'w').and_return(first_file)
      allow(first_file).to receive(:write)
      allow(first_file).to receive(:close)

      second_file = instance_double(File)
      allow(File).to receive(:open).with(notebooks.filename(22_222), 'w').and_return(second_file)
      allow(second_file).to receive(:write)
      allow(second_file).to receive(:close)

      notebooks.backup

      expect(first_file).to have_received(:write).with(::JSON.pretty_generate(first_notebook.deep_sort))
      expect(second_file).to have_received(:write).with(::JSON.pretty_generate(second_notebook.deep_sort))
    end
  end

  describe '#filename' do
    subject(:filename) { notebooks.filename(11_111) }

    it { is_expected.to eq("#{tempdir}/notebooks/11111.json") }
  end

  describe '#get_by_id' do
    subject(:notebook) { notebooks.get_by_id(11_111) }

    it { is_expected.to eq(first_notebook) }
  end

  describe '#create' do
    subject(:create) { notebooks.create(first_notebook) }

    before do
      stubs.post('/api/v1/notebooks') do |env|
        expect(env.body).to eq(
          'data' => {
            'type' => 'notebooks',
            'attributes' => first_notebook.fetch('attributes')
          }
        )
        respond_with200({ 'data' => first_notebook })
      end
    end

    it { is_expected.to eq(first_notebook) }
  end

  describe '#update' do
    subject(:update) { notebooks.update(11_111, first_notebook) }

    before do
      stubs.put('/api/v1/notebooks/11111') do |env|
        expect(env.body).to eq(
          'data' => {
            'type' => 'notebooks',
            'attributes' => first_notebook.fetch('attributes'),
            'id' => 11_111
          }
        )
        respond_with200({ 'data' => first_notebook })
      end
    end

    it { is_expected.to eq(first_notebook) }
  end
end
