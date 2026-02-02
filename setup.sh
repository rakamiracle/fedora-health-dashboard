#!/bin/bash
# setup.sh - Setup script for Fedora Health Dashboard

echo "🚀 Setting up Fedora Health Dashboard..."
echo "=========================================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "❌ Jangan jalankan sebagai root! Gunakan user biasa."
    exit 1
fi

# Check Ruby version
echo "🔍 Checking Ruby version..."
ruby_version=$(ruby -v | cut -d' ' -f2)
echo "Ruby version: $ruby_version"

# Install system dependencies
echo "📦 Installing system dependencies..."
sudo dnf install -y \
    gcc-c++ \
    make \
    sqlite-devel \
    iproute \
    net-tools \
    bind-utils \
    iputils \
    htop \
    atop \
    nmon 2>/dev/null || echo "⚠️  Some packages not installed (optional)"

# Clean gem cache
echo "🧹 Cleaning gem cache..."
gem cleanup 2>/dev/null || true

# Install Ruby gems
echo "💎 Installing Ruby gems..."
if [ -f "Gemfile" ]; then
    bundle install
else
    echo "❌ Gemfile not found!"
    exit 1
fi

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p \
    logs \
    backups \
    reports \
    data \
    public/{css,js,images} \
    lib/{modules,utils} \
    specs

# Create empty files if they don't exist
echo "📄 Creating required files..."
touch logs/system.log
touch data/config.yaml

# Check for required modules
echo "🔧 Checking module files..."
required_modules=(
    "lib/modules/cpu_monitor.rb"
    "lib/modules/memory_monitor.rb" 
    "lib/modules/disk_monitor.rb"
    "lib/modules/security_checker.rb"
    "lib/modules/network_monitor.rb"
    "lib/utils/logger.rb"
    "lib/utils/formatter.rb"
)

for module in "${required_modules[@]}"; do
    if [ ! -f "$module" ]; then
        echo "⚠️  Missing: $module"
        # Create basic version
        mkdir -p "$(dirname "$module")"
        echo "# Placeholder for $(basename "$module")" > "$module"
    else
        echo "✅ Found: $module"
    fi
done

# Setup permissions
echo "🔐 Setting permissions..."
chmod +x app.rb 2>/dev/null || true
chmod +x setup.sh

# Create sample config if doesn't exist
if [ ! -f "data/config.yaml" ] || [ ! -s "data/config.yaml" ]; then
    echo "⚙️ Creating sample config..."
    cat > data/config.yaml << EOF
# Fedora Health Dashboard Configuration
dashboard:
  refresh_interval: 5
  log_level: info
  enable_alerts: true

modules:
  cpu:
    warning_threshold: 70
    critical_threshold: 90
  memory:
    warning_threshold: 80
    critical_threshold: 95
  disk:
    warning_threshold: 85
    critical_threshold: 95
  network:
    monitor_bandwidth: true
    check_firewall: true

security:
  check_firewall: true
  check_updates: true
  monitor_logins: true

ui:
  color_scheme: "dark"
  show_top_processes: 5
EOF
fi

# Create .env.example if doesn't exist
if [ ! -f ".env.example" ]; then
    echo "🌍 Creating .env.example..."
    cat > .env.example << EOF
# Environment variables for Fedora Health Dashboard
# Copy to .env and edit

# Telegram Bot (optional)
# TELEGRAM_BOT_TOKEN=your_bot_token_here
# TELEGRAM_CHAT_ID=your_chat_id_here

# Dashboard Configuration
DASHBOARD_REFRESH_INTERVAL=5
DASHBOARD_PORT=4567
DASHBOARD_HOST=0.0.0.0

# Alert Thresholds
CPU_WARNING_THRESHOLD=80
CPU_CRITICAL_THRESHOLD=95
MEMORY_WARNING_THRESHOLD=85
MEMORY_CRITICAL_THRESHOLD=95
DISK_WARNING_THRESHOLD=90
DISK_CRITICAL_THRESHOLD=95

# Logging
LOG_LEVEL=info
LOG_RETENTION_DAYS=7
EOF
fi

echo ""
echo "✅ Setup completed successfully!"
echo ""
echo "📋 Next steps:"
echo "   1. Edit data/config.yaml for customization"
echo "   2. Copy .env.example to .env if needed"
echo "   3. Run the dashboard: ruby app.rb"
echo ""
echo "🛠️  Available commands:"
echo "   ruby app.rb              # Run terminal dashboard"
echo "   ./setup.sh               # Run setup again"
echo "   bundle exec rspec specs/ # Run tests"
echo "   rubocop                  # Check code style"
echo ""
echo "📊 Dashboard will monitor:"
echo "   • CPU usage and temperature"
echo "   • Memory usage"
echo "   • Disk space"
echo "   • Network bandwidth"
echo "   • Security status"
echo ""
echo "Happy monitoring! 🚀"