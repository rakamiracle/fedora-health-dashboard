# lib/modules/cpu_monitor.rb
module FedoraDashboard
  class CPUMonitor
    def initialize
      @cores = OS.cpu_count
      @load_avg = File.read('/proc/loadavg').split.map(&:to_f)
    end
    
    def analyze
      {
        cores: @cores,
        load_1min: @load_avg[0],
        load_5min: @load_avg[1],
        load_15min: @load_avg[2],
        usage_percentage: calculate_usage,
        recommendations: generate_recommendations
      }
    end
    
    def calculate_usage
      # Simulasi penggunaan CPU
      stat1 = File.read('/proc/stat').lines.first.split[1..4].map(&:to_i)
      sleep(0.1)
      stat2 = File.read('/proc/stat').lines.first.split[1..4].map(&:to_i)
      
      total = stat2.sum - stat1.sum
      idle = stat2[3] - stat1[3]
      
      ((total - idle).to_f / total * 100).round(2)
    end
    
    def generate_recommendations
      recs = []
      usage = calculate_usage
      
      if usage > 90
        recs << "⚠️  CPU overload! Cek process dengan `ps aux --sort=-%cpu | head -10`"
        recs << "📉 Consider matikan service tidak penting: `sudo systemctl list-units --state=running`"
      elsif usage > 70
        recs << "📊 CPU cukup tinggi. Monitor dengan `htop`"
      end
      
      recs << "🎯 Tips: Gunakan `taskset` untuk pin process ke core tertentu" if @cores > 4
      recs
    end
    
    def top_processes(limit = 5)
      `ps aux --sort=-%cpu | head -#{limit + 1}`.lines[1..-1].map do |line|
        cols = line.split
        {
          user: cols[0],
          pid: cols[1],
          cpu: cols[2],
          mem: cols[3],
          command: cols[10..-1].join(' ')[0..50]
        }
      end
    end
  end
end