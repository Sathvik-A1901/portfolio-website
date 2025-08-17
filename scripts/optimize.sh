#!/bin/bash

# Asset Optimization Script
# Optimizes images, CSS, and JavaScript files for portfolio website
# Author: Sathvik Addicharla
# Date: 2024

# Configuration
ASSETS_DIR="../assets"
IMAGES_DIR="$ASSETS_DIR/images"
CSS_DIR="$ASSETS_DIR/css"
JS_DIR="$ASSETS_DIR/js"
BACKUP_DIR="backups"
LOG_FILE="optimization.log"
MAX_IMAGE_SIZE=500000  # 500KB
QUALITY=85

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    # Check for ImageMagick
    if ! command -v convert &> /dev/null; then
        missing_tools+=("ImageMagick")
    fi
    
    # Check for jpegoptim
    if ! command -v jpegoptim &> /dev/null; then
        missing_tools+=("jpegoptim")
    fi
    
    # Check for optipng
    if ! command -v optipng &> /dev/null; then
        missing_tools+=("optipng")
    fi
    
    # Check for gzip
    if ! command -v gzip &> /dev/null; then
        missing_tools+=("gzip")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_message "❌ Missing required tools: ${missing_tools[*]}"
        log_message "Please install the missing tools:"
        echo ""
        echo "Ubuntu/Debian:"
        echo "  sudo apt-get install imagemagick jpegoptim optipng gzip"
        echo ""
        echo "CentOS/RHEL:"
        echo "  sudo yum install ImageMagick jpegoptim optipng gzip"
        echo ""
        echo "macOS:"
        echo "  brew install imagemagick jpegoptim optipng gzip"
        echo ""
        return 1
    fi
    
    log_message "✅ All required tools are available"
    return 0
}

# Function to create backup
create_backup() {
    local source_dir="$1"
    local backup_name="$2"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
    fi
    
    local backup_path="$BACKUP_DIR/${backup_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    if tar -czf "$backup_path" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>/dev/null; then
        log_message "💾 Backup created: $backup_path"
        return 0
    else
        log_message "❌ Failed to create backup of $source_dir"
        return 1
    fi
}

# Function to optimize JPEG images
optimize_jpeg() {
    local image_path="$1"
    local original_size=$(stat -c%s "$image_path" 2>/dev/null || stat -f%z "$image_path" 2>/dev/null)
    
    if [ "$original_size" -gt "$MAX_IMAGE_SIZE" ]; then
        log_message "🖼️  Optimizing JPEG: $(basename "$image_path") (${original_size} bytes)"
        
        # Create temporary file
        local temp_file="${image_path}.tmp"
        cp "$image_path" "$temp_file"
        
        # Optimize with jpegoptim
        if jpegoptim --strip-all --max="$QUALITY" "$temp_file" >/dev/null 2>&1; then
            local optimized_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null)
            local savings=$((original_size - optimized_size))
            local savings_percent=$((savings * 100 / original_size))
            
            if [ "$optimized_size" -lt "$original_size" ]; then
                mv "$temp_file" "$image_path"
                log_message "✅ JPEG optimized: $(basename "$image_path") - Saved ${savings} bytes (${savings_percent}%)"
            else
                rm "$temp_file"
                log_message "ℹ️  JPEG already optimized: $(basename "$image_path")"
            fi
        else
            rm "$temp_file"
            log_message "❌ Failed to optimize JPEG: $(basename "$image_path")"
        fi
    else
        log_message "ℹ️  JPEG already small enough: $(basename "$image_path") (${original_size} bytes)"
    fi
}

# Function to optimize PNG images
optimize_png() {
    local image_path="$1"
    local original_size=$(stat -c%s "$image_path" 2>/dev/null || stat -f%z "$image_path" 2>/dev/null)
    
    if [ "$original_size" -gt "$MAX_IMAGE_SIZE" ]; then
        log_message "🖼️  Optimizing PNG: $(basename "$image_path") (${original_size} bytes)"
        
        # Create temporary file
        local temp_file="${image_path}.tmp"
        cp "$image_path" "$temp_file"
        
        # Optimize with optipng
        if optipng -o7 -strip all "$temp_file" >/dev/null 2>&1; then
            local optimized_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null)
            local savings=$((original_size - optimized_size))
            local savings_percent=$((savings * 100 / original_size))
            
            if [ "$optimized_size" -lt "$original_size" ]; then
                mv "$temp_file" "$image_path"
                log_message "✅ PNG optimized: $(basename "$image_path") - Saved ${savings} bytes (${savings_percent}%)"
            else
                rm "$temp_file"
                log_message "ℹ️  PNG already optimized: $(basename "$image_path")"
            fi
        else
            rm "$temp_file"
            log_message "❌ Failed to optimize PNG: $(basename "$image_path")"
        fi
    else
        log_message "ℹ️  PNG already small enough: $(basename "$image_path") (${original_size} bytes)"
    fi
}

# Function to resize large images
resize_images() {
    local image_path="$1"
    local max_width=1920
    local max_height=1080
    
    # Get image dimensions
    local dimensions=$(identify -format "%wx%h" "$image_path" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_message "⚠️  Cannot get dimensions for: $(basename "$image_path")"
        return
    fi
    
    local width=$(echo "$dimensions" | cut -d'x' -f1)
    local height=$(echo "$dimensions" | cut -d'x' -f2)
    
    if [ "$width" -gt "$max_width" ] || [ "$height" -gt "$max_height" ]; then
        log_message "📏 Resizing image: $(basename "$image_path") (${width}x${height} -> max ${max_width}x${max_height})"
        
        # Create temporary file
        local temp_file="${image_path}.tmp"
        
        # Resize image maintaining aspect ratio
        if convert "$image_path" -resize "${max_width}x${max_height}>" "$temp_file" 2>/dev/null; then
            local new_dimensions=$(identify -format "%wx%h" "$temp_file" 2>/dev/null)
            mv "$temp_file" "$image_path"
            log_message "✅ Image resized: $(basename "$image_path") -> ${new_dimensions}"
        else
            rm "$temp_file"
            log_message "❌ Failed to resize: $(basename "$image_path")"
        fi
    fi
}

# Function to optimize CSS files
optimize_css() {
    local css_file="$1"
    
    if [ -f "$css_file" ]; then
        log_message "🎨 Optimizing CSS: $(basename "$css_file")"
        
        # Create backup
        local backup_file="${css_file}.backup"
        cp "$css_file" "$backup_file"
        
        # Remove comments and unnecessary whitespace
        local temp_file="${css_file}.tmp"
        
        # Remove comments and compress
        sed 's|/\*.*\*/||g' "$css_file" | \
        sed '/^[[:space:]]*$/d' | \
        sed 's/[[:space:]]\+/ /g' | \
        sed 's/[[:space:]]*{[[:space:]]*/{/g' | \
        sed 's/[[:space:]]*}[[:space:]]*/}/g' | \
        sed 's/[[:space:]]*:[[:space:]]*/:/g' | \
        sed 's/[[:space:]]*;[[:space:]]*/;/g' > "$temp_file"
        
        if [ $? -eq 0 ]; then
            local original_size=$(stat -c%s "$css_file" 2>/dev/null || stat -f%z "$css_file" 2>/dev/null)
            local optimized_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null)
            local savings=$((original_size - optimized_size))
            local savings_percent=$((savings * 100 / original_size))
            
            mv "$temp_file" "$css_file"
            log_message "✅ CSS optimized: $(basename "$css_file") - Saved ${savings} bytes (${savings_percent}%)"
        else
            rm "$temp_file"
            log_message "❌ Failed to optimize CSS: $(basename "$css_file")"
        fi
    fi
}

# Function to optimize JavaScript files
optimize_js() {
    local js_file="$1"
    
    if [ -f "$js_file" ]; then
        log_message "⚡ Optimizing JavaScript: $(basename "$js_file")"
        
        # Create backup
        local backup_file="${js_file}.backup"
        cp "$js_file" "$backup_file"
        
        # Remove comments and unnecessary whitespace
        local temp_file="${js_file}.tmp"
        
        # Basic JS minification (remove single-line comments and extra whitespace)
        sed 's|//.*||g' "$js_file" | \
        sed '/^[[:space:]]*$/d' | \
        sed 's/[[:space:]]\+/ /g' | \
        sed 's/[[:space:]]*{[[:space:]]*/{/g' | \
        sed 's/[[:space:]]*}[[:space:]]*/}/g' | \
        sed 's/[[:space:]]*;[[:space:]]*/;/g' > "$temp_file"
        
        if [ $? -eq 0 ]; then
            local original_size=$(stat -c%s "$js_file" 2>/dev/null || stat -f%z "$js_file" 2>/dev/null)
            local optimized_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null)
            local savings=$((original_size - optimized_size))
            local savings_percent=$((savings * 100 / original_size))
            
            mv "$temp_file" "$js_file"
            log_message "✅ JavaScript optimized: $(basename "$js_file") - Saved ${savings} bytes (${savings_percent}%)"
        else
            rm "$temp_file"
            log_message "❌ Failed to optimize JavaScript: $(basename "$js_file")"
        fi
    fi
}

# Function to create gzipped versions
create_gzip_versions() {
    local file="$1"
    
    if [ -f "$file" ]; then
        local gzip_file="${file}.gz"
        
        if gzip -c "$file" > "$gzip_file" 2>/dev/null; then
            local original_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
            local gzip_size=$(stat -c%s "$gzip_file" 2>/dev/null || stat -f%z "$gzip_file" 2>/dev/null)
            local savings=$((original_size - gzip_size))
            local savings_percent=$((savings * 100 / original_size))
            
            log_message "🗜️  Gzip created: $(basename "$gzip_file") - Saved ${savings} bytes (${savings_percent}%)"
        else
            log_message "❌ Failed to create gzip for: $(basename "$file")"
        fi
    fi
}

# Function to generate optimization report
generate_report() {
    local report_file="optimization_report_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "=== Asset Optimization Report ===" > "$report_file"
    echo "Generated: $(date)" >> "$report_file"
    echo "" >> "$report_file"
    
    # Count files
    local total_images=$(find "$IMAGES_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \) 2>/dev/null | wc -l)
    local total_css=$(find "$CSS_DIR" -name "*.css" 2>/dev/null | wc -l)
    local total_js=$(find "$JS_DIR" -name "*.js" 2>/dev/null | wc -l)
    
    echo "Files processed:" >> "$report_file"
    echo "- Images: $total_images" >> "$report_file"
    echo "- CSS: $total_css" >> "$report_file"
    echo "- JavaScript: $total_js" >> "$report_file"
    echo "" >> "$report_file"
    
    # Calculate total savings
    local total_savings=0
    if [ -f "$LOG_FILE" ]; then
        total_savings=$(grep "Saved" "$LOG_FILE" | awk '{sum += $NF} END {print sum}' | sed 's/[^0-9]//g')
        if [ -z "$total_savings" ]; then
            total_savings=0
        fi
    fi
    
    echo "Total space saved: ${total_savings} bytes" >> "$report_file"
    echo "Report saved to: $report_file" >> "$report_file"
    
    log_message "📊 Optimization report generated: $report_file"
}

# Function to show help
show_help() {
    echo "Asset Optimization Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -i, --images        Optimize images only"
    echo "  -c, --css           Optimize CSS only"
    echo "  -j, --js            Optimize JavaScript only"
    echo "  -a, --all           Optimize all assets (default)"
    echo "  -b, --backup        Create backup before optimization"
    echo "  -g, --gzip          Create gzipped versions of files"
    echo "  -r, --report        Generate optimization report"
    echo ""
    echo "Examples:"
    echo "  $0 --images         # Optimize images only"
    echo "  $0 --css            # Optimize CSS only"
    echo "  $0 --backup         # Create backup and optimize all"
    echo "  $0 --gzip           # Optimize and create gzip versions"
}

# Main function
main() {
    local optimize_images=true
    local optimize_css=true
    local optimize_js=true
    local create_backup_flag=false
    local create_gzip_flag=false
    local generate_report_flag=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--images)
                optimize_images=true
                optimize_css=false
                optimize_js=false
                shift
                ;;
            -c|--css)
                optimize_images=false
                optimize_css=true
                optimize_js=false
                shift
                ;;
            -j|--js)
                optimize_images=false
                optimize_css=false
                optimize_js=true
                shift
                ;;
            -a|--all)
                optimize_images=true
                optimize_css=true
                optimize_js=true
                shift
                ;;
            -b|--backup)
                create_backup_flag=true
                shift
                ;;
            -g|--gzip)
                create_gzip_flag=true
                shift
                ;;
            -r|--report)
                generate_report_flag=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Initialize log file
    touch "$LOG_FILE"
    log_message "🚀 Starting asset optimization..."
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Create backup if requested
    if [ "$create_backup_flag" = true ]; then
        if create_backup "$ASSETS_DIR" "assets"; then
            log_message "✅ Backup completed successfully"
        else
            log_message "❌ Backup failed, aborting optimization"
            exit 1
        fi
    fi
    
    # Optimize images
    if [ "$optimize_images" = true ] && [ -d "$IMAGES_DIR" ]; then
        log_message "🖼️  Starting image optimization..."
        
        # Find and optimize JPEG images
        find "$IMAGES_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" \) -print0 | while IFS= read -r -d '' file; do
            optimize_jpeg "$file"
            resize_images "$file"
        done
        
        # Find and optimize PNG images
        find "$IMAGES_DIR" -type f -name "*.png" -print0 | while IFS= read -r -d '' file; do
            optimize_png "$file"
            resize_images "$file"
        done
        
        log_message "✅ Image optimization completed"
    fi
    
    # Optimize CSS files
    if [ "$optimize_css" = true ] && [ -d "$CSS_DIR" ]; then
        log_message "🎨 Starting CSS optimization..."
        
        find "$CSS_DIR" -name "*.css" -print0 | while IFS= read -r -d '' file; do
            optimize_css "$file"
            
            if [ "$create_gzip_flag" = true ]; then
                create_gzip_versions "$file"
            fi
        done
        
        log_message "✅ CSS optimization completed"
    fi
    
    # Optimize JavaScript files
    if [ "$optimize_js" = true ] && [ -d "$JS_DIR" ]; then
        log_message "⚡ Starting JavaScript optimization..."
        
        find "$JS_DIR" -name "*.js" -print0 | while IFS= read -r -d '' file; do
            optimize_js "$file"
            
            if [ "$create_gzip_flag" = true ]; then
                create_gzip_versions "$file"
            fi
        done
        
        log_message "✅ JavaScript optimization completed"
    fi
    
    # Generate report if requested
    if [ "$generate_report_flag" = true ]; then
        generate_report
    fi
    
    log_message "✅ Asset optimization completed successfully!"
    
    # Show summary
    echo ""
    echo "🎉 Optimization Summary:"
    echo "========================"
    if [ "$optimize_images" = true ]; then
        echo "✅ Images optimized"
    fi
    if [ "$optimize_css" = true ]; then
        echo "✅ CSS optimized"
    fi
    if [ "$optimize_js" = true ]; then
        echo "✅ JavaScript optimized"
    fi
    if [ "$create_backup_flag" = true ]; then
        echo "✅ Backup created"
    fi
    if [ "$create_gzip_flag" = true ]; then
        echo "✅ Gzip versions created"
    fi
    echo ""
    echo "📝 Check $LOG_FILE for detailed information"
}

# Run main function with all arguments
main "$@"
