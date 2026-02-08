require 'colorize'
require 'terminal-table'
require 'yaml'
require_relative 'lib/modules/cpu_monitor'
require_relative 'lib/modules/memory_monitor'
require_relative 'lib/modules/disk_monitor'
require_relative 'lib/modules/security_checker'
require_relative 'lib/modules/network_monitor'
require_relative 'lib/modules/service_monitor'

module FedoraDashboard
  class Dashboard
    def initialize(refresh_interval = 5)
      @interval = refresh_interval
      @cpu = CPUMonitor.new
      @memory = MemoryMonitor.new
      @disk = DiskMonitor.new
      @security = SecurityChecker.new
      @network = NetworkMonitor.new
      @services = ServiceMonitor.new
      @alerts = []
    end
    
    def display_header
      system('clear') || system('cls')
      puts "=" * 80
      puts "🖥️  FEDORA SYSTEM HEALTH DASHBOARD".center(80).bold.blue
      puts "=" * 80
      puts "Waktu: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}".ljust(40) + 
           "Uptime: #{`uptime -p`.chomp}".rjust(40)
      puts "-" * 80
    end
    
    def display_cpu_table(data)
      table = Terminal::Table.new do |t|
        t.title = "🔄 CPU STATUS"
        t.headings = ['Cores', 'Load (1/5/15)', 'Usage %', 'Status', 'Recommendations']
        
        status = if data[:usage_percentage] > 90
                   "CRITICAL".red
                 elsif data[:usage_percentage] > 70
                   "WARNING".yellow
                 else
                   "NORMAL".green
                 end
        
        t.add_row [
          data[:cores],
          "#{data[:load_1min]}/#{data[:load_5min]}/#{data[:load_15min]}",
          "#{data[:usage_percentage]}%".colorize(usage_color(data[:usage_percentage])),
          status,
          data[:recommendations].first || "✅ Optimal"
        ]
        
        # Top processes
        t.add_separator
        t.add_row [{ value: "TOP PROCESSES:", colspan: 5 }]
        
        @cpu.top_processes(3).each do |process|
          t.add_row [
            "→ #{process[:user]}",
            "PID: #{process[:pid]}",
            "#{process[:cpu]}%",
            "#{process[:mem]}%",
            process[:command]
          ]
        end
      end
      
      puts table
      puts
    end
    
    def display_memory_table(data)
      table = Terminal::Table.new do |t|
        t.title = "🧠 MEMORY STATUS"
        t.headings = ['Total', 'Used', 'Free', 'Usage %', 'Status']
        
        status = if data[:usage_percentage] > 90
                   "CRITICAL".red
                 elsif data[:usage_percentage] > 80
                   "WARNING".yellow
                 else
                   "NORMAL".green
                 end
        
        t.add_row [
          "#{data[:total_gb]} GB",
          "#{data[:used_gb]} GB",
          "#{data[:free_gb]} GB",
          "#{data[:usage_percentage]}%",
          status
        ]
      end
      
      puts table
      puts
    end
    
    def display_disk_table(data)
      table = Terminal::Table.new do |t|
        t.title = "💾 DISK STATUS"
        t.headings = ['Mount', 'Total', 'Used', 'Free', 'Usage %', 'Status']
        
        data[:partitions].first(3).each do |partition|
          status = if partition[:usage_percentage] > 95
                     "CRITICAL".red
                   elsif partition[:usage_percentage] > 85
                     "WARNING".yellow
                   else
                     "NORMAL".green
                   end
          
          t.add_row [
            partition[:mount],
            "#{partition[:total_gb]} GB",
            "#{partition[:used_gb]} GB",
            "#{partition[:free_gb]} GB",
            "#{partition[:usage_percentage]}%",
            status
          ]
        end
      end
      
      puts table
      puts
    end
    
    def display_network_table(data)
      return if data[:interfaces].empty?
      
      table = Terminal::Table.new do |t|
        t.title = "🌐 NETWORK STATUS"
        t.headings = ['Interface', 'State', 'IP Address', 'Bandwidth', 'Connections']
        
        data[:interfaces].each do |iface|
          bandwidth = data[:bandwidth][iface[:name]]
          bw_str = bandwidth ? "#{bandwidth[:download_mbps]}↓/#{bandwidth[:upload_mbps]}↑ Mbps" : "N/A"
          
          t.add_row [
            iface[:name],
            iface[:state] == 'up' ? '✅ Up'.green : '❌ Down'.red,
            iface[:ipv4],
            bw_str,
            data[:connections][:total]
          ]
        end
        
        # Add summary row
        t.add_separator
        t.add_row [
          { value: "SUMMARY:", colspan: 5 }
        ]
        t.add_row [
          "Firewall:",
          data[:firewall_status][:protected] ? '✅ Active'.green : '❌ Inactive'.red,
          "DNS:",
          data[:dns_status][:resolvable] ? '✅ OK'.green : '❌ Failed'.red,
          "Connections: #{data[:connections][:total]}"
        ]
      end
      
      puts table
      puts
    end
    
    def display_service_table(data)
      table = Terminal::Table.new do |t|
        t.title = "🛠️  SERVICE STATUS"
        t.headings = ['Service', 'Status', 'Enabled', 'Memory', 'Uptime']
        
        # Show critical services
        data[:critical_services].each do |service|
          next unless service[:exists]
          
          status = service[:active] ? '✅ Active'.green : '❌ Inactive'.red
          enabled = service[:enabled] ? 'Yes'.green : 'No'.yellow
          memory = service[:memory_usage] ? "#{service[:memory_usage]} MB" : 'N/A'
          uptime = service[:uptime] || 'N/A'
          
          t.add_row [
            service[:name],
            status,
            enabled,
            memory,
            uptime
          ]
        end
        
        # Add failed services section
        unless data[:failed_services].empty?
          t.add_separator
          t.add_row [{ value: "FAILED SERVICES:", colspan: 5 }]
          
          data[:failed_services].each do |failed|
            t.add_row [
              "❌ #{failed[:name]}",
              { value: failed[:description][0..40], colspan: 4 }
            ]
          end
        end
      end
      
      puts table
      puts
    end
    
    def display_security_table(data)
      table = Terminal::Table.new do |t|
        t.title = "🔒 SECURITY CHECK"
        t.headings = %w[Component Status Details Actions]
        
        # Firewall
        fw = data[:firewall][:firewalld]
        fw_status = fw[:running] ? "✅ Active".green : "❌ Inactive".red
        t.add_row ['Firewall', fw_status, fw[:enabled] ? 'Enabled' : 'Disabled', 
                  fw[:running] ? '' : 'sudo systemctl start firewalld']
        
        # Updates
        updates = data[:updates]
        update_status = updates[:security_updates] > 0 ? "🔄 Needed".yellow : "✅ Updated".green
        t.add_row ['Security Updates', update_status, 
                  "#{updates[:security_updates]} updates", 
                  'sudo dnf update --security']
        
        # Authentication
        auth = data[:auth]
        auth_status = auth[:failed_attempts] > 20 ? "⚠️  Suspicious".red : "✅ Normal".green
        t.add_row ['Authentication', auth_status, 
                  "#{auth[:failed_attempts]} failed attempts",
                  'Check /var/log/secure']
        
        # Recommendations
        t.add_separator
        t.add_row [{ value: "RECOMMENDATIONS:", colspan: 4 }]
        data[:recommendations].each do |rec|
          t.add_row [{ value: "• #{rec}", colspan: 4 }]
        end
      end
      
      puts table
      puts
    end
    
    def display_quick_actions
      actions = [
        { key: '1', action: '🔍 Detail CPU', command: 'htop' },
        { key: '2', action: '📊 Detail Memory', command: 'free -h' },
        { key: '3', action: '💾 Detail Disk', command: 'df -h' },
        { key: '4', action: '🔐 Check Security', command: 'sudo journalctl -xe' },
        { key: '5', action: '🌐 Network Details', command: '' },
        { key: '6', action: '🛠️  Service Details', command: '' },
        { key: '7', action: '📡 Bandwidth Test', command: '' },
        { key: '8', action: '📊 Export Report', command: '' },
        { key: 'r', action: '🔄 Refresh', command: '' },
        { key: 'q', action: '🚪 Quit', command: '' }
      ]
      
      puts "⚡ QUICK ACTIONS:"
      actions.each_slice(3) do |row|
        row.each do |action|
          print "[#{action[:key]}] #{action[:action]}".ljust(30)
        end
        puts
      end
      puts "-" * 80
    end
    
    def usage_color(percentage)
      case percentage
      when 0..70 then :green
      when 71..90 then :yellow
      else :red
      end
    end
    
    def export_full_report
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      filename = "reports/system_report_#{timestamp}.txt"
      
      FileUtils.mkdir_p('reports')
      
      File.open(filename, 'w') do |f|
        f.puts "Fedora System Health Report"
        f.puts "Generated: #{Time.now}"
        f.puts "=" * 60
        
        # CPU Data
        cpu_data = @cpu.analyze
        f.puts "\nCPU STATUS:"
        f.puts "  Cores: #{cpu_data[:cores]}"
        f.puts "  Load Avg: #{cpu_data[:load_1min]}/#{cpu_data[:load_5min]}/#{cpu_data[:load_15min]}"
        f.puts "  Usage: #{cpu_data[:usage_percentage]}%"
        f.puts "  Recommendations:"
        cpu_data[:recommendations].each { |r| f.puts "    • #{r}" }
        
        # Memory Data
        memory_data = @memory.analyze
        f.puts "\nMEMORY STATUS:"
        f.puts "  Total: #{memory_data[:total_gb]} GB"
        f.puts "  Used: #{memory_data[:used_gb]} GB"
        f.puts "  Usage: #{memory_data[:usage_percentage]}%"
        
        # Disk Data
        disk_data = @disk.analyze
        f.puts "\nDISK STATUS:"
        disk_data[:partitions].each do |partition|
          f.puts "  #{partition[:mount]}: #{partition[:used_gb]}GB/#{partition[:total_gb]}GB (#{partition[:usage_percentage]}%)"
        end
        
        # Network Data
        network_data = @network.analyze
        f.puts "\nNETWORK STATUS:"
        f.puts "  Interfaces: #{network_data[:interfaces].size}"
        network_data[:interfaces].each do |iface|
          f.puts "    #{iface[:name]}: #{iface[:state]} - #{iface[:ipv4]}"
        end
        f.puts "  Active Connections: #{network_data[:connections][:total]}"
        
        # Service Data
        service_data = @services.analyze
        f.puts "\nSERVICE STATUS:"
        f.puts "  Critical Services: #{service_data[:critical_services].count { |s| s[:active] }}/#{service_data[:critical_services].size} active"
        f.puts "  Failed Services: #{service_data[:failed_services].size}"
        unless service_data[:failed_services].empty?
          f.puts "  Failed:"
          service_data[:failed_services].each do |failed|
            f.puts "    • #{failed[:name]}: #{failed[:description]}"
          end
        end
        
        # Security Data
        security_data = @security.generate_report
        f.puts "\nSECURITY STATUS:"
        f.puts "  Firewall: #{security_data[:firewall][:firewalld][:running] ? 'Active' : 'Inactive'}"
        f.puts "  Security Updates: #{security_data[:updates][:security_updates]}"
        
        # Recommendations
        f.puts "\nRECOMMENDATIONS:"
        cpu_data[:recommendations].each { |r| f.puts "  • #{r}" }
        service_data[:recommendations].each { |r| f.puts "  • #{r}" }
        network_data[:recommendations].each { |r| f.puts "  • #{r}" }
        security_data[:recommendations].each { |r| f.puts "  • #{r}" }
        
        f.puts "\n" + "=" * 60
        f.puts "Report saved to: #{filename}"
      end
      
      puts "✅ Full report exported to: #{filename}"
    end
    
    def run
      loop do
        display_header
        
        # Collect data
        cpu_data = @cpu.analyze
        memory_data = @memory.analyze
        disk_data = @disk.analyze
        security_data = @security.generate_report
        network_data = @network.analyze
        service_data = @services.analyze
        
        # Display tables
        display_cpu_table(cpu_data)
        display_memory_table(memory_data)
        display_disk_table(disk_data)
        display_network_table(network_data)
        display_service_table(service_data)
        display_security_table(security_data)
        
        display_quick_actions
        
        # Handle input
        print "Pilihan Anda: "
        input = gets.chomp.downcase
        
        case input
        when '1'
          system('htop')
        when '2'
          system('free -h && echo "---" && vmstat 1 5')
        when '3'
          system('df -h && echo "---" && sudo du -sh /* 2>/dev/null | sort -hr | head -10')
        when '4'
          system('sudo tail -20 /var/log/secure')
          puts "Tekan enter untuk lanjut..."
          gets
        when '5'
          puts "🌐 Network Details:"
          puts "=" * 50
          network_data[:interfaces].each do |iface|
            puts "  #{iface[:name]}:"
            puts "    State: #{iface[:state]}"
            puts "    MAC: #{iface[:mac]}"
            puts "    IPv4: #{iface[:ipv4]}"
            puts "    IPv6: #{iface[:ipv6]}"
          end
          puts "\n📊 Bandwidth Usage:"
          network_data[:bandwidth].each do |interface, bw|
            puts "  #{interface}: #{bw[:download_mbps]} Mbps ↓ / #{bw[:upload_mbps]} Mbps ↑"
          end
          puts "\n🔗 Top Connections:"
          network_data[:top_connections].each do |conn|
            puts "  #{conn[:local]} -> #{conn[:remote]} (#{conn[:state]})"
          end
          puts "\nTekan enter untuk lanjut..."
          gets
        when '6'
          puts "🛠️  Service Details:"
          puts "=" * 50
          puts "Critical Services Status:"
          service_data[:critical_services].each do |service|
            if service[:exists]
              status = service[:active] ? '✅ Active' : '❌ Inactive'
              puts "  #{service[:name]}: #{status}"
              puts "    Enabled: #{service[:enabled] ? 'Yes' : 'No'}"
              puts "    Memory: #{service[:memory_usage]} MB" if service[:memory_usage]
              puts "    Uptime: #{service[:uptime]}" if service[:uptime]
            end
          end
          
          unless service_data[:failed_services].empty?
            puts "\n❌ Failed Services:"
            service_data[:failed_services].each do |failed|
              puts "  #{failed[:name]}: #{failed[:description]}"
            end
          end
          
          puts "\n📊 Service Statistics:"
          puts "  Total Services: #{service_data[:service_counts][:total]}"
          puts "  Active: #{service_data[:service_counts][:active]}"
          puts "  Inactive: #{service_data[:service_counts][:inactive]}"
          puts "  Failed: #{service_data[:service_counts][:failed]}"
          
          puts "\n💡 Recommendations:"
          service_data[:recommendations].each { |r| puts "  • #{r}" }
          
          puts "\nTekan enter untuk lanjut..."
          gets
        when '7'
          puts "📡 Bandwidth Test (2 seconds)..."
          result = @network.realtime_bandwidth('eth0', 2)
          if result
            puts "  Download: #{result[:download_mbps]} Mbps"
            puts "  Upload: #{result[:upload_mbps]} Mbps"
          else
            result = @network.realtime_bandwidth('wlan0', 2)
            if result
              puts "  Download: #{result[:download_mbps]} Mbps"
              puts "  Upload: #{result[:upload_mbps]} Mbps"
            else
              puts "  Could not measure bandwidth"
            end
          end
          puts "Tekan enter untuk lanjut..."
          gets
        when '8'
          export_full_report
          puts "Tekan enter untuk lanjut..."
          gets
        when 'q'
          puts "Terima kasih! Dashboard ditutup."
          break
        end
        
        sleep(@interval) unless input == 'q'
      end
    end
  end
end