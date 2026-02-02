module FedoraDashboard
  class NetworkMonitor
    def initialize
      @interfaces = detect_interfaces
      @prev_stats = {}
      initialize_stats
    end
    
    def analyze
      current_stats = read_network_stats
      bandwidth = calculate_bandwidth(current_stats)
      connections = analyze_connections
      
      {
        interfaces: @interfaces,
        bandwidth: bandwidth,
        connections: connections,
        firewall_status: check_firewall,
        dns_status: check_dns,
        recommendations: generate_recommendations(bandwidth, connections),
        top_connections: get_top_connections(5),
        suspicious_connections: suspicious_connections
      }
    end
    
    def realtime_bandwidth(interface = 'eth0', duration = 2)
      start_stats = read_interface_stats(interface)
      return nil unless start_stats
      
      sleep(duration)
      end_stats = read_interface_stats(interface)
      return nil unless end_stats
      
      rx_diff = end_stats[:rx_bytes] - start_stats[:rx_bytes]
      tx_diff = end_stats[:tx_bytes] - start_stats[:tx_bytes]
      
      {
        interface: interface,
        download_mbps: (rx_diff * 8 / duration / 1_000_000.0).round(2),
        upload_mbps: (tx_diff * 8 / duration / 1_000_000.0).round(2),
        download_kbps: (rx_diff / duration / 1024.0).round(2),
        upload_kbps: (tx_diff / duration / 1024.0).round(2),
        total_bytes: rx_diff + tx_diff
      }
    end
    
    def suspicious_connections
      connections = []
      begin
        output = `ss -tunap 2>/dev/null`
        return [] unless output
        
        output.lines[1..]&.each do |line|
          parts = line.split
          next if parts.size < 6
          
          local = parts[4]
          remote = parts[5]
          state = parts[1]
          process = parts[6..]&.join(' ') || ''
          
          # Check for suspicious patterns
          if remote.match?(/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:/) && 
             !remote.match?(/:(80|443|22|53|25|587)$/) &&
             state == 'ESTAB'
            
            connections << {
              local: local,
              remote: remote,
              state: state,
              process: process,
              reason: 'Connection to non-standard port'
            }
          end
        end
      rescue
        # Ignore errors
      end
      
      connections
    end
    
    private
    
    def detect_interfaces
      interfaces = []
      
      begin
        `ip -o link show 2>/dev/null`.lines.each do |line|
          if line =~ /^\d+: (\w+):/
            interface = $1
            next if interface == 'lo'  # Skip loopback
            
            # Check interface state
            state_file = "/sys/class/net/#{interface}/operstate"
            if File.exist?(state_file)
              state = File.read(state_file).chomp
              if state == 'up'
                interfaces << {
                  name: interface,
                  state: state,
                  mac: read_mac_address(interface),
                  ipv4: read_ip_address(interface, 4),
                  ipv6: read_ip_address(interface, 6)
                }
              end
            end
          end
        end
      rescue
        # Fallback to eth0 if detection fails
        interfaces << {
          name: 'eth0',
          state: 'unknown',
          mac: 'unknown',
          ipv4: 'N/A',
          ipv6: 'N/A'
        }
      end
      
      interfaces
    end
    
    def initialize_stats
      @interfaces.each do |iface|
        stats = read_interface_stats(iface[:name])
        @prev_stats[iface[:name]] = stats if stats
      end
    end
    
    def read_network_stats
      stats = {}
      @interfaces.each do |iface|
        stats[iface[:name]] = read_interface_stats(iface[:name])
      end
      stats
    end
    
    def read_interface_stats(interface)
      begin
        stats_dir = "/sys/class/net/#{interface}/statistics/"
        return nil unless File.exist?(stats_dir)
        
        {
          rx_bytes: File.read("#{stats_dir}rx_bytes").to_i,
          tx_bytes: File.read("#{stats_dir}tx_bytes").to_i,
          rx_packets: File.read("#{stats_dir}rx_packets").to_i,
          tx_packets: File.read("#{stats_dir}tx_packets").to_i,
          rx_errors: File.read("#{stats_dir}rx_errors").to_i,
          tx_errors: File.read("#{stats_dir}tx_errors").to_i
        }
      rescue
        nil
      end
    end
    
    def calculate_bandwidth(current_stats)
      bandwidth = {}
      interval = 5  # seconds between checks
      
      current_stats.each do |interface, current|
        prev = @prev_stats[interface]
        
        if prev && current
          rx_rate = (current[:rx_bytes] - prev[:rx_bytes]) / interval
          tx_rate = (current[:tx_bytes] - prev[:tx_bytes]) / interval
          
          bandwidth[interface] = {
            download_bps: rx_rate,
            upload_bps: tx_rate,
            download_mbps: (rx_rate * 8 / 1_000_000.0).round(2),
            upload_mbps: (tx_rate * 8 / 1_000_000.0).round(2),
            download_kbps: (rx_rate / 1024.0).round(2),
            upload_kbps: (tx_rate / 1024.0).round(2)
          }
        else
          bandwidth[interface] = {
            download_mbps: 0,
            upload_mbps: 0,
            download_kbps: 0,
            upload_kbps: 0
          }
        end
      end
      
      @prev_stats = current_stats
      bandwidth
    end
    
    def analyze_connections
      begin
        tcp_output = `ss -tun 2>/dev/null`
        tcp_lines = tcp_output ? tcp_output.lines[1..] || [] : []
        
        udp_output = `ss -uun 2>/dev/null`
        udp_lines = udp_output ? udp_output.lines[1..] || [] : []
        
        {
          total: tcp_lines.size + udp_lines.size,
          tcp: tcp_lines.size,
          udp: udp_lines.size,
          established: tcp_lines.count { |c| c.split[1] == 'ESTAB' },
          listening: tcp_lines.count { |c| c.split[1] == 'LISTEN' },
          time_wait: tcp_lines.count { |c| c.split[1] == 'TIME-WAIT' }
        }
      rescue
        { total: 0, tcp: 0, udp: 0, established: 0, listening: 0, time_wait: 0 }
      end
    end
    
    def check_firewall
      begin
        firewalld = `systemctl is-active firewalld 2>/dev/null`.chomp == 'active'
        
        {
          firewalld_active: firewalld,
          protected: firewalld
        }
      rescue
        { firewalld_active: false, protected: false }
      end
    end
    
    def check_dns
      begin
        resolv_time = `timeout 2 dig google.com 2>/dev/null | grep "Query time:"`.to_s
        resolv_success = !resolv_time.empty?
        
        resolv_conf = []
        if File.exist?('/etc/resolv.conf')
          File.read('/etc/resolv.conf').lines.each do |line|
            resolv_conf << line.split[1] if line.start_with?('nameserver')
          end
        end
        
        {
          resolvable: resolv_success,
          nameservers: resolv_conf.compact,
          response_time: resolv_time[/\d+/].to_i rescue 0
        }
      rescue
        { resolvable: false, nameservers: [], response_time: 0 }
      end
    end
    
    def get_top_connections(limit = 5)
      connections = []
      begin
        output = `ss -tunp 2>/dev/null`
        return [] unless output
        
        output.lines[1..limit]&.each do |line|
          parts = line.split
          next if parts.size < 7
          
          connections << {
            protocol: parts[0],
            state: parts[1],
            local: parts[4],
            remote: parts[5],
            process: parts[6..]&.join(' ') || ''
          }
        end
      rescue
        # Return empty array on error
      end
      
      connections
    end
    
    def generate_recommendations(bandwidth, connections)
      recs = []
      
      # Bandwidth recommendations
      bandwidth.each do |interface, stats|
        if stats[:download_mbps] > 100 || stats[:upload_mbps] > 100
          recs << "📶 #{interface}: High bandwidth (#{stats[:download_mbps]}↓/#{stats[:upload_mbps]}↑ Mbps)"
        elsif stats[:download_mbps] < 0.1 && stats[:upload_mbps] < 0.1
          recs << "🐌 #{interface}: Very low bandwidth"
        end
      end
      
      # Connection recommendations
      if connections[:total] > 1000
        recs << "🔗 Many connections (#{connections[:total]} total). Check: `ss -tunap`"
      end
      
      if connections[:time_wait] > 100
        recs << "⏰ Many TIME-WAIT connections (#{connections[:time_wait]}). Consider tuning TCP"
      end
      
      # Firewall recommendations
      firewall = check_firewall
      unless firewall[:protected]
        recs << "🛡️  Firewall inactive! Enable: `sudo systemctl enable --now firewalld`"
      end
      
      # DNS recommendations
      dns = check_dns
      unless dns[:resolvable]
        recs << "🔍 DNS resolution failed. Check: `cat /etc/resolv.conf`"
      end
      
      recs << "✅ Network status normal" if recs.empty?
      recs
    end
    
    def read_mac_address(interface)
      File.read("/sys/class/net/#{interface}/address").chomp rescue 'unknown'
    end
    
    def read_ip_address(interface, version = 4)
      cmd = version == 4 ? "ip -4 addr show #{interface}" : "ip -6 addr show #{interface}"
      output = `#{cmd} 2>/dev/null`
      return 'N/A' unless output
      
      pattern = version == 4 ? /inet\s+([^\/\s]+)/ : /inet6\s+([^\/\s]+)/
      match = output.match(pattern)
      match ? match[1] : 'N/A'
    end
  end
end