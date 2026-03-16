#!/usr/bin/env bash
# calculate_r2_storage.sh — Calculates total size of media files and estimates Cloudflare R2 cost

set -euo pipefail

SOURCE_DIR="${1:-/Volumes/DOMOVINA1TB/fetch_domovina_tv_output}"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Source directory not found: $SOURCE_DIR"
    echo "   Make sure the external drive is mounted."
    exit 1
fi

echo "🔍 Skeniram direktorij: '$SOURCE_DIR' za povezanima video i audio datotekama..."
echo "   (Ovo može potrajati ovisno o broju datoteka)"

# Brojimo medijske datoteke - mp4, webm, mkv za video i wav, mp3, m4a za audio
STATS=$(find "$SOURCE_DIR" -type f \( -name "*.mp4" -o -name "*.webm" -o -name "*.mkv" -o -name "*.wav" -o -name "*.mp3" -o -name "*.m4a" \) -exec stat -f "%z" {} + 2>/dev/null | awk '{s+=$1; c++} END {print c, s}')

COUNT=$(echo "$STATS" | awk '{print $1}')
TOTAL_BYTES=$(echo "$STATS" | awk '{print $2}')

if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
    echo "⚠️  Nisu pronađene medijske datoteke u $SOURCE_DIR."
    exit 0
fi

# R2 koristi gigabajte (GB) umjesto gibibajta (GiB) za obračun, 1 GB = 10^9 bytes
TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_BYTES / 1000000000}")
TOTAL_GIB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_BYTES / 1073741824}")

# Cloudflare R2: Prvih 10 GB je besplatno mjesečno, zatim $0.015 USD/GB
BILLABLE_GB=$(awk "BEGIN { val = $TOTAL_GB - 10; if (val < 0) val = 0; printf \"%.2f\", val }")
MONTHLY_COST=$(awk "BEGIN {printf \"%.2f\", $BILLABLE_GB * 0.015}")

echo ""
echo "📊 Rezultati kalkulacije (Cloudflare R2 Estimacija):"
echo "---------------------------------------------------"
echo "📁 Broj pronađenih medijskih datoteka: $COUNT"
echo "⚖️  Ukupna veličina datoteka:      $TOTAL_GB GB ($TOTAL_GIB GiB)"
echo "☁️  Cloudflare R2 Storage tarifa:  \$0.015 po GB mjesečno (prvih 10 GB besplatno)"
echo "💸 Naplativa veličina za pohranu:  $BILLABLE_GB GB"
echo "💰 Procijenjeni mjesečni trošak:  \$${MONTHLY_COST} USD"
echo "---------------------------------------------------"
echo "💡 Napomena: Izračun pokriva samo mjesečni 'storage' (pohranu)."
echo "   R2 ne naplaćuje egress (izlazni protok), ali naplaćuje operacije čitanja i pisanja:"
echo "   - Class A Operations (Upload/Put): \$4.50 / 1 milijun zahtjeva"
echo "   - Class B Operations (Download/Get): \$0.36 / 1 milijun zahtjeva"
echo ""
echo "   Za incijalni upload vaših $COUNT datoteka (Class A operacije), "
echo "   trošak uploada će biti oko \$$(awk "BEGIN {printf \"%.4f\", ($COUNT / 1000000) * 4.5}") USD (jednokratno)."
echo "---------------------------------------------------"
