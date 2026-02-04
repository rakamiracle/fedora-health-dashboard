module FedoraDashboard
  class ServiceMonitor
    def initialize
      @critical_services = [
        'sshd',          # SSH server
        'firewalld',     # Firewall
        'NetworkManager', # Network management
        'systemd-logind', # Login management
        'dbus',          # Message bus system
        'systemd-journald' # Logging
      ]
      
      @optional_services = [
        'httpd',         # Web server
        'mariadb',       # Database
        'postfix',       # Mail server
        'docker',        # Docker
        'nginx',         # Nginx
        'php-fpm'        # PHP
      ]
    end
    
    def analyze
      {
        critical_services: check_services(@critical_services),
        optional_services: check_services(@optional_services),
        failed_services: find_failed_services,
        recommendations: generate_recommendations,
        systemd_status: check_systemd_overall,
        service_counts: count_services_by_state
      }
    end
    
    def check_service(service_name)
      begin
        # Check if service exists
        exists = `systemctl list-unit-files | grep -w #{service_name}.service 2>/dev/null`.chomp != ''
        
        if exists
          # Get service status
          active = `systemctl is-active #{service_name} 2>/dev/null`.chomp
          enabled = `systemctl is-enabled #{service_name} 2>/dev/null`.chomp
          
          {
            name: service_name,
            exists: true,
            active: active == 'active',
            enabled: enabled == 'enabled',
            status: active,
            enabled_status: enabled,
            memory_usage: get_service_memory(service_name),
            uptime: get_service_uptime(service_name)
          }
        else
          {
            name: service_name,
            exists: false,
            active: false,
            enabled: false,
            status: 'not-found',
            enabled_status: 'not-found'
          }
        end
      rescue => e
        {
          name: service_name,
          exists: false,
          active: false,
          enabled: false,
          status: 'error',
          error: e.message
        }
      end
    end
    
    def restart_service(service_name)
      begin
        output = `sudo systemctl restart #{service_name} 2>&1`
        success = $?.success?
        
        {
          success: success,
          output: output.chomp,
          service: service_name,
          timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S')
        }
      rescue => e
        {
          success: false,
          error: e.message,
          service: service_name
        }
      end
    end
    
    def get_service_logs(service_name, lines = 20)
      begin
        logs = `sudo journalctl -u #{service_name} -n #{lines} 2>/dev/null`
        
        {
          service: service_name,
          lines: lines,
          logs: logs.lines.map(&:chomp),
          has_logs: !logs.empty?
        }
      rescue => e
        {
          service: service_name,
          error: "Failed to get logs: #{e.message}",
          logs: []
        }
      end
    end
    
    def find_high_memory_services(limit = 10)
      begin
        # Get services sorted by memory usage
        services = `ps aux --sort=-rss | head -#{limit + 1}`.lines[1..] || []
        
        services.map do |line|
          cols = line.split
          {
            user: cols[0],
            pid: cols[1],
            memory_percent: cols[3].to_f,
            memory_mb: (cols[5].to_i / 1024.0).round(2),
            command: cols[10..].join(' ')[0..100],
            service: extract_service_name(cols[10..].join(' '))
          }
        end
      rescue
        []
      end
    end
    
    def generate_service_report
      report = analyze
      timestamp = Time.now.strftime('%Y-%m-%d_%H%M%S')
      
      {
        timestamp: timestamp,
        summary: {
          total_critical: report[:critical_services].size,
          active_critical: report[:critical_services].count { |s| s[:active] },
          failed_services: report[:failed_services].size,
          total_services: report[:service_counts][:total]
        },
        details: report,
        recommendations: report[:recommendations]
      }
    end
    
    private
    
    def check_services(service_list)
      service_list.map { |service| check_service(service) }
    end
    
    def find_failed_services
      begin
        failed = `systemctl --failed 2>/dev/null`.lines[1..] || []
        
        failed.map do |line|
          parts = line.split
          next if parts.empty?
          
          {
            name: parts[0],
            load: parts[1],
            active: parts[2],
            sub: parts[3],
            description: parts[4..].join(' ')
          }
        end.compact
      rescue
        []
      end
    end
    
    def check_systemd_overall
      begin
        # Check systemd overall status
        status = `systemctl status 2>/dev/null | head -5`.lines
        
        {
          loaded: status.any? { |line| line.include?('loaded') },
          active: status.any? { |line| line.include?('active (running)') },
          status_lines: status.map(&:chomp)
        }
      rescue
        { loaded: false, active: false, status_lines: [] }
      end
    end
    
    def count_services_by_state
      begin
        states = {
          loaded: 0,
          active: 0,
          inactive: 0,
          failed: 0
        }
        
        # Count services by state
        `systemctl list-units --type=service --all 2>/dev/null`.lines[1..-2]&.each do |line|
          parts = line.split
          next if parts.empty?
          
          case parts[2]
          when 'active'
            states[:active] += 1
          when 'inactive'
            states[:inactive] += 1
          when 'failed'
            states[:failed] += 1
          end
          
          states[:loaded] += 1 if parts[1] == 'loaded'
        end
        
        states[:total] = states[:loaded]
        states
      rescue
        { total: 0, loaded: 0, active: 0, inactive: 0, failed: 0 }
      end
    end
    
    def get_service_memory(service_name)
      begin
        # Get memory usage of service's main process
        pid = `systemctl show #{service_name} --property=MainPID 2>/dev/null`.split('=').last.to_i
        
        if pid > 0
          mem_info = `ps -o rss= -p #{pid} 2>/dev/null`.to_i
          (mem_info / 1024.0).round(2) # Convert to MB
        else
          0.0
        end
      rescue
        0.0
      end
    end
    
    def get_service_uptime(service_name)
      begin
        # Get service uptime
        active_enter = `systemctl show #{service_name} --property=ActiveEnterTimestamp 2>/dev/null`
        
        if active_enter =~ /=(.+)/
          timestamp = $1.strip
          # Calculate uptime
          start_time = Time.parse(timestamp) rescue nil
          
          if start_time
            uptime_seconds = (Time.now - start_time).to_i
            
            # Format uptime
            days = uptime_seconds / (24 * 3600)
            hours = (uptime_seconds % (24 * 3600)) / 3600
            minutes = (uptime_seconds % 3600) / 60
            
            if days > 0
              "#{days}d #{hours}h"
            elsif hours > 0
              "#{hours}h #{minutes}m"
            else
              "#{minutes}m"
            end
          else
            'unknown'
          end
        else
          'not-running'
        end
      rescue
        'unknown'
      end
    end
    
    def extract_service_name(command)
      # Try to extract service name from command
      if command =~ /(\w+)\.service/
        $1
      elsif command =~ /\/usr\/(bin|sbin)\/(\w+)/
        $2
      else
        command.split.first.split('/').last
      end
    rescue
      'unknown'
    end
    
    def generate_recommendations
      recs = []
      analysis = analyze
      
      # Check critical services
      analysis[:critical_services].each do |service|
        unless service[:active]
          recs << "🔴 Critical service #{service[:name]} is not active!"
          recs << "   Start with: sudo systemctl start #{service[:name]}"
        end
      end
      
      # Check failed services
      unless analysis[:failed_services].empty?
        recs << "⚠️  #{analysis[:failed_services].size} services failed"
        analysis[:failed_services].each do |failed|
          recs << "   • #{failed[:name]}: #{failed[:description]}"
        end
        recs << "   View details: sudo systemctl --failed"
      end
      
      # Memory usage check
      high_memory = find_high_memory_services(5)
      high_memory.each do |service|
        if service[:memory_mb] > 500 # More than 500MB
          recs << "💾 High memory: #{service[:service]} (#{service[:memory_mb]} MB)"
        end
      end
      
      # Systemd health
      unless analysis[:systemd_status][:active]
        recs << "⚠️  Systemd has issues. Check: sudo systemctl status"
      end
      
      recs << "✅ All services running normally" if recs.empty?
      recs
    end
  end
end