# lib/modules/security_checker.rb
module FedoraDashboard
  class SecurityChecker
    def initialize
      @logs_dir = '/var/log'
    end
    
    def check_firewall
      {
        firewalld: check_service('firewalld'),
        ufw: check_service('ufw'),
        ports: check_open_ports
      }
    end
    
    def check_updates
      update_info = `dnf check-update --quiet 2>/dev/null`
      {
        available: update_info.lines.count,
        security_updates: update_info.scan(/Security/).count,
        last_update: `rpm -qa --last | head -1`.split(/\s{2,}/)[1]
      }
    end
    
    def suspicious_logins
      # Cek login mencurigakan
      logins = `last -f /var/log/wtmp | head -20`.lines.map(&:chomp)
      failed = `sudo tail -100 /var/log/secure 2>/dev/null | grep 'Failed password' | wc -l`.to_i
      
      {
        recent_logins: logins[0..4],
        failed_attempts: failed,
        has_sudoers: File.exist?('/etc/sudoers.d')
      }
    end
    
    def generate_report
      {
        firewall: check_firewall,
        updates: check_updates,
        auth: suspicious_logins,
        recommendations: security_recommendations
      }
    end
    
    private
    
    def check_service(name)
      status = `systemctl is-active #{name} 2>/dev/null`.chomp
      enabled = `systemctl is-enabled #{name} 2>/dev/null`.chomp
      {
        status: status,
        enabled: enabled == 'enabled',
        running: status == 'active'
      }
    end
    
    def check_open_ports
      `ss -tuln 2>/dev/null | grep LISTEN`.lines.map do |line|
        parts = line.split
        {
          protocol: parts[0],
          address: parts[4],
          state: parts[5]
        }
      end
    end
    
    def security_recommendations
      recs = []
      
      # Rekomendasi berdasarkan hasil check
      recs << "🔒 Aktifkan firewall: `sudo systemctl enable --now firewalld`" unless check_firewall[:firewalld][:running]
      recs << "🔄 Update sistem: `sudo dnf update --security`" if check_updates[:security_updates] > 0
      recs << "👁️  Monitor login: `sudo tail -f /var/log/secure`" if suspicious_logins[:failed_attempts] > 10
      recs << "🔑 Setup 2FA: `sudo dnf install google-authenticator`" 
      
      recs
    end
  end
end