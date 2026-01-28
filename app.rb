require_relative 'dashboard'

begin
  puts "🚀 Starting Fedora System Health Dashboard..."
  puts "📊 Monitoring system resources setiap 5 detik"
  puts "📝 Logs disimpan di: logs/system.log"
  puts "-" * 50
  
  dashboard = FedoraDashboard::Dashboard.new(5)
  dashboard.run
  
rescue Interrupt
  puts "\n\n👋 Dashboard dihentikan oleh user"
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts "Backtrace: #{e.backtrace.first}"
ensure
  puts "\n💾 Logging completed. Check logs/system.log for details"
end