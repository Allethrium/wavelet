#!/bin/bash

# Called once upon installation to generate performance optimization scripts

setup_wavelet_performance_optimizations() {
	local total_cpus=$(nproc)
	echo "Setting up Wavelet performance optimizations for $total_cpus CPU cores..."

	# Create optimization scripts
	create_wavelet_optimization_scripts

	# Configure CPU affinity and scheduling optimizations
	setup_cpu_optimizations "$total_cpus"

	# Create systemd service for runtime optimizations
	create_wavelet_optimization_service

	echo "Performance optimizations configured and will be applied on boot"
}

create_wavelet_optimization_scripts() {
	# USB optimization script
	cat > "/usr/local/bin/wavelet_usb_optimize.sh" <<-EOF
		#!/bin/bash
		USB_DEVICE="$1"
		USB_PATH="/sys/bus/usb/devices/$USB_DEVICE"
		if [[ -d "$USB_PATH" ]]; then
			# Disable USB autosuspend for video devices
			echo -1 > "$USB_PATH/power/autosuspend" 2>/dev/null || true
			echo on > "$USB_PATH/power/control" 2>/dev/null || true
			# Increase USB URB memory allocation
			echo 128 > /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null || true
			echo "$(date): USB optimization applied to $USB_DEVICE" >> /var/log/wavelet/usb.log
		fi
EOF

	# V4L2 optimization script
	cat > "/usr/local/bin/wavelet_v4l2_optimize.sh" <<-EOF
		#!/bin/bash
		V4L_DEVICE="/dev/$1"
		if [[ -c "$V4L_DEVICE" ]]; then
			# Get device capabilities first
			CAPS=$(v4l2-ctl -d "$V4L_DEVICE" --list-ctrls 2>/dev/null)
			# Only optimize what's actually available and beneficial
			if echo "$CAPS" | grep -q "compression_quality"; then
				v4l2-ctl -d "$V4L_DEVICE" --set-ctrl=compression_quality=100 2>/dev/null || true
			fi
			if echo "$CAPS" | grep -q "power_line_frequency"; then
				v4l2-ctl -d "$V4L_DEVICE" --set-ctrl=power_line_frequency=0 2>/dev/null || true
			fi
			# Keep autofocus/exposure enabled but tune for responsiveness
			if echo "$CAPS" | grep -q "focus_auto"; then
				v4l2-ctl -d "$V4L_DEVICE" --set-ctrl=focus_auto=1 2>/dev/null || true
				v4l2-ctl -d "$V4L_DEVICE" --set-ctrl=focus_automatic_continuous=1 2>/dev/null || true
			fi
			if echo "$CAPS" | grep -q "exposure_auto"; then
				v4l2-ctl -d "$V4L_DEVICE" --set-ctrl=exposure_auto=3 2>/dev/null || true
			fi
			echo "$(date): V4L2 optimization applied to $V4L_DEVICE" >> /var/log/wavelet/v4l2.log
		fi
		EOF

	# IRQ optimization script
	cat > "/usr/local/bin/wavelet_irq_optimize.sh" <<-EOF
		#!/bin/bash
		TOTAL_CPUS="$(nproc)"
		# Only optimize IRQ affinity if we have enough cores
		if (( TOTAL_CPUS >= 6 )); then
			# Use cores 2-N for video, reserve 0-1 for system/network
			VIDEO_CORES_MASK=$(printf "0x%x" $(( (1 << (TOTAL_CPUS - 2)) - 1 << 2 )))
			SYSTEM_CORES_MASK="0x3"  # Cores 0,1
			# Move USB video device interrupts to video cores
			for irq in $(grep -E "uhci|ohci|ehci|xhci|usb" /proc/interrupts | cut -d: -f1 | tr -d ' '); do
				echo "$VIDEO_CORES_MASK" > "/proc/irq/$irq/smp_affinity" 2>/dev/null || true
			done
			# Move network interrupts to system cores
			for irq in $(grep -E "eth|ens|enp|wlan" /proc/interrupts | cut -d: -f1 | tr -d ' '); do
				echo "$SYSTEM_CORES_MASK" > "/proc/irq/$irq/smp_affinity" 2>/dev/null || true
			done
			echo "$(date): IRQ affinity optimized for $TOTAL_CPUS cores" >> /var/log/wavelet/irq.log
		fi
		EOF
	# Make scripts executable
	chmod +x /usr/local/bin/wavelet_*.sh
}

setup_cpu_optimizations() {
	local total_cpus="$1"

	# Create CPU optimization configuration
	cat > /etc/wavelet/cpu_config << EOF
TOTAL_CPUS=$total_cpus
ENABLE_CPU_ISOLATION=$( (( total_cpus >= 6 )) && echo "true" || echo "false" )
SYSTEM_CPUS="0"
NETWORK_CPUS="1"
VIDEO_CPUS="2-$((total_cpus-1))"
EOF

	# Store CPU affinity settings for systemd units
	if (( total_cpus >= 6 )); then
		cat > /etc/wavelet/ultragrid_cpu_affinity << EOF
CPUAffinity=2-$((total_cpus-1))
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=50
IOSchedulingClass=1
IOSchedulingPriority=4
MemoryLow=512M
MemoryHigh=2G
EOF
		echo "$(date): High-performance CPU affinity configured for $total_cpus cores" >> /var/log/wavelet/system.log
	elif (( total_cpus >= 4 )); then
		cat > /etc/wavelet/ultragrid_cpu_affinity << EOF
CPUAffinity=1-$((total_cpus-1))
CPUSchedulingPolicy=other
IOSchedulingClass=1
IOSchedulingPriority=4
MemoryLow=256M
MemoryHigh=1G
EOF
		echo "$(date): Moderate CPU affinity configured for $total_cpus cores" >> /var/log/wavelet/system.log
	else
		cat > /etc/wavelet/ultragrid_cpu_affinity << EOF
# No CPU affinity restrictions for systems with fewer than 4 cores
IOSchedulingClass=2
IOSchedulingPriority=7
EOF
		echo "$(date): Minimal optimizations configured for $total_cpus cores" >> /var/log/wavelet/system.log
	fi
}

create_wavelet_optimization_service() {
	# System service for runtime optimizations
	cat > /etc/systemd/system/wavelet-optimize.service << 'EOF'
[Unit]
Description=Wavelet System Optimizations
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wavelet_runtime_optimize.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

	# Runtime system optimization script
	cat > /usr/local/bin/wavelet_runtime_optimize.sh << 'EOF'
#!/bin/bash
# Source CPU configuration
if [[ -f /etc/wavelet/cpu_config ]]; then
    source /etc/wavelet/cpu_config
else
    echo "Warning: CPU config not found, using defaults"
    TOTAL_CPUS=$(nproc)
    ENABLE_CPU_ISOLATION="false"
fi

echo "Applying Wavelet runtime optimizations for $TOTAL_CPUS cores..."

# CPU scheduler optimizations for A/V workloads
echo 0 > /proc/sys/kernel/sched_autogroup_enabled
echo 1000000 > /proc/sys/kernel/sched_latency_ns
echo 100000 > /proc/sys/kernel/sched_min_granularity_ns

# Memory management for video buffers
echo 1 > /proc/sys/vm/compact_memory
echo 0 > /proc/sys/vm/swappiness

# Network optimizations for UltraGrid
echo 16777216 > /proc/sys/net/core/rmem_max
echo 16777216 > /proc/sys/net/core/wmem_max
echo "4096 16384 16777216" > /proc/sys/net/ipv4/tcp_rmem
echo "4096 16384 16777216" > /proc/sys/net/ipv4/tcp_wmem

# File system optimizations for video file I/O
for device in /sys/block/*/queue/scheduler; do
    if [[ -w "$device" ]]; then
        echo deadline > "$device" 2>/dev/null || echo mq-deadline > "$device" 2>/dev/null || true
    fi
done

# Apply IRQ optimizations
/usr/local/bin/wavelet_irq_optimize.sh

# USB optimizations
echo 128 > /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null || true

echo "$(date): Wavelet runtime optimizations applied" >> /var/log/wavelet/system.log
EOF

	chmod +x /usr/local/bin/wavelet_runtime_optimize.sh

	# Enable the service
	systemctl enable wavelet-optimize.service
}


####
#
# Main execution
#
####

# Check if we're being called properly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Wavelet System Optimization Setup"
    echo "=================================="

    # Ensure we're running as root
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
    # Create log directory if it doesn't exist
    mkdir -p /var/log/wavelet
    # Run the setup
    setup_wavelet_performance_optimizations
    echo "Setup completed successfully!"
    echo "Runtime optimizations will be applied on next boot via wavelet-optimize.service"
else
    # Script is being sourced, just define functions
    :
fi