require 'rspec'
require_relative '../lib/modules/cpu_monitor'

RSpec.describe FedoraDashboard::CPUMonitor do
  let(:monitor) { described_class.new }
  
  describe '#analyze' do
    it 'returns a hash with cpu data' do
      result = monitor.analyze
      
      expect(result).to be_a(Hash)
      expect(result).to have_key(:cores)
      expect(result).to have_key(:load_1min)
      expect(result).to have_key(:recommendations)
    end
  end
  
  describe '#generate_recommendations' do
    it 'returns an array of recommendations' do
      recommendations = monitor.generate_recommendations
      
      expect(recommendations).to be_a(Array)
      expect(recommendations).to all(be_a(String))
    end
  end
end