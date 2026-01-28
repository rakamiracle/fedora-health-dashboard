# dashboard.rb
require 'colorize'
require 'terminal-table'
require 'yaml'
require_relative 'lib/modules/cpu_monitor'
require_relative 'lib/modules/memory_monitor'
require_relative 'lib/modules/disk_monitor'
require_relative 'lib/modules/security_checker'

module FedoraDashboard
  class Dashboard
    def initialize(refresh_interval = 5)
      @interval = refresh_interval
      @cpu = CPUMonitor.new
      @memory = MemoryMonitor.new
      @disk = DiskMonitor.new
      @security = SecurityChecker.new
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
        
        status = data[:usage_percentage] > 90 ? "CRITICAL".red : 
                 data[:usage_percentage] > 70 ? "WARNING".yellow : "NORMAL".green
        
        t.add_row [
          data[:cores],
          "#{data[:load_1min]}/#{data[:load_5min]}/#{data[:load_15min]}",
          "#{data[:usage_percentage]}%".colorize(usage_color(data[:usage_percentage])),
          status,
          data[:recommendations].first || "✅ Optimal"
        ]
        
        # Top processes
        t.add_separator
        t.add_row [{value: "TOP PROCESSES:", colspan: 5}]
        
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
    
    def display_security_table(data)
      table = Terminal::Table.new do |t|
        t.title = "🔒 SECURITY CHECK"
        t.headings = ['Component', 'Status', 'Details', 'Actions']
        
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
        t.add_row [{value: "RECOMMENDATIONS:", colspan: 4}]
        data[:recommendations].each do |rec|
          t.add_row [{value: "• #{rec}", colspan: 4}]
        end
      end
      
      puts table
      puts
    end
    
    def display_quick_actions
      actions = [
        {key: '1', action: '🔍 Detail CPU', command: 'htop'},
        {key: '2', action: '📊 Detail Memory', command: 'free -h'},
        {key: '3', action: '💾 Detail Disk', command: 'df -h'},
        {key: '4', action: '🔐 Check Security', command: 'sudo journalctl -xe'},
        {key: 'r', action: '🔄 Refresh', command: ''},
        {key: 'q', action: '🚪 Quit', command: ''}
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
    
    def run
      loop do
        display_header
        
        # Collect data
        cpu_data = @cpu.analyze
        security_data = @security.generate_report
        
        # Display tables
        display_cpu_table(cpu_data)
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
        when 'q'
          puts "Terima kasih! Dashboard ditutup."
          break
        end
        
        sleep(@interval) unless input == 'q'
      end
    end
  end
end