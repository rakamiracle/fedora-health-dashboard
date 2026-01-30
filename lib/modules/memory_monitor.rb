module FedoraDashboard
  class MemoryMonitor
    def initialize
      @meminfo = read_meminfo
    end
    
    def analyze
      {
        total_gb: (@meminfo[:mem_total].to_f / (1024 * 1024)).round(2),
        used_gb: calculate_used_gb,
        free_gb: (@meminfo[:mem_free].to_f / (1024 * 1024)).round(2),
        available_gb: (@meminfo[:mem_available].to_f / (1024 * 1024)).round(2),
        usage_percentage: calculate_usage,
        recommendations: generate_recommendations
      }
    end
    
    private
    
    def read_meminfo
      meminfo = { 
        mem_total: 8192 * 1024,  # Default 8GB in KB
        mem_free: 4096 * 1024,
        mem_available: 5120 * 1024,
        swap_total: 4096 * 1024,
        swap_free: 2048 * 1024
      }
      
      begin
        File.read('/proc/meminfo').lines.each do |line|
          key, value = line.split(':')
          if key && value
            key_sym = key.strip.downcase.gsub('(', '').gsub(')', '').gsub(' ', '_').to_sym
            meminfo[key_sym] = value.strip.split.first.to_i
          end
        end
      rescue
        # Use defaults if can't read
      end
      
      meminfo
    end
    
    def calculate_usage
      total = @meminfo[:mem_total].to_f
      available = @meminfo[:mem_available].to_f
      used = total - available
      ((used / total) * 100).round(2)
    end
    
    def calculate_used_gb
      total = @meminfo[:mem_total].to_f
      available = @meminfo[:mem_available].to_f
      ((total - available) / (1024 * 1024)).round(2)
    end
    
    def generate_recommendations
      usage = calculate_usage
      recs = []
      
      if usage > 95
        recs << "🚨 Memory kritis! Pertimbangkan restart service berat"
        recs << "💡 Cek memory leak: `ps aux --sort=-%mem | head -10`"
      elsif usage > 85
        recs << "⚠️  Memory tinggi. Clear cache: `sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches`"
      else
        recs << "✅ Memory usage normal"
      end
      
      recs
    end
  end
end