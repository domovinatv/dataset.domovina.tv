#!/usr/bin/env bash
#
# sync_to_r2.sh — Skripta za sinkronizaciju lokalnih medijskih datoteka na Cloudflare R2
#
# Ova skripta koristi AWS CLI (koji je kompatibilan s Cloudflare R2) za upload datoteka.
# Sinkronizacija je podešena tako da upload-a samo nove ili izmijenjene datoteke.
# Brisanje lokalnih datoteka NEĆE obrisati datoteke na R2 (zato što Cloudflare R2 služi kao trajni storage).
#
# Preduvjeti:
#   1. Instaliran AWS CLI (brew install awscli)
#   2. Konfiguriran AWS CLI sa R2 akreditivima (aws configure --profile r2-domovina)
#      - AWS Access Key ID: <Tvoj R2 Access Key>
#      - AWS Secret Access Key: <Tvoj R2 Secret Key>
#      - Default region name: auto
#      - Default output format: json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Konfiguracija ---
DEFAULT_SOURCE="/Volumes/DOMOVINA1TB/fetch_domovina_tv_output"
# Promijeni ovo u naziv svog R2 bucketa
BUCKET_NAME="domovina-tv-katalog" 
# Promijeni ovo u svoj Cloudflare R2 Endpoint
# Pronalazi se u Cloudflare Dashboard pod R2 -> Settings -> "S3 API (Endpoint)"
# Format: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
ENDPOINT_URL="https://<YOUR_ACCOUNT_ID>.r2.cloudflarestorage.com"
# Profil iz ~/.aws/credentials i ~/.aws/config
AWS_PROFILE="default"

# --- Parametri ---
DRY_RUN=false
SOURCE="$DEFAULT_SOURCE"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --bucket) BUCKET_NAME="$2"; shift 2 ;;
        --endpoint) ENDPOINT_URL="$2"; shift 2 ;;
        --profile) AWS_PROFILE="$2"; shift 2 ;;
        --help|-h)
            echo "Korištenje: $0 [--dry-run] [--bucket NAME] [--endpoint URL] [--profile AWS_PROFILE] [SOURCE]"
            echo ""
            echo "Opcije:"
            echo "  --dry-run      Prikazuje plan sinkronizacije bez stvarnog uploada na R2 (simulacija)"
            echo "  --bucket NAME  Postavlja ime R2 bucketa (default: $BUCKET_NAME)"
            echo "  --endpoint URL Postavlja S3 Endpoint URL za R2"
            echo "  --profile PRF  Postavlja AWS CLI profil za R2 (default: $AWS_PROFILE)"
            echo ""
            echo "Default izvor:"
            echo "  SOURCE: $DEFAULT_SOURCE"
            echo ""
            echo "Napomena: AWS CLI mora biti instaliran (brew install awscli) i konfiguriran."
            exit 0
            ;;
        *)
            SOURCE="$1"
            shift
            ;;
    esac
done

if [ ! -d "$SOURCE" ]; then
    echo "❌ Izvorni direktorij nije pronađen: $SOURCE"
    echo "   Provjerite je li vanjski disk spojen."
    exit 1
fi

if [[ "$ENDPOINT_URL" == *"<YOUR_ACCOUNT_ID>"* ]] && [ "$DRY_RUN" = false ]; then
    echo "❌ Upozorenje: Molimo vas da postavite stvarni ENDPOINT_URL za Cloudflare R2."
    echo "   (Uredite ovu skriptu ili koristite --endpoint parametar)"
    echo "   Primjer: https://1234567890abcdef.r2.cloudflarestorage.com"
    exit 1
fi

# Provjera je li aws-cli instaliran
if ! command -v aws &> /dev/null; then
    echo "❌ 'aws' naredba nije pronađena. Molimo instalirajte AWS CLI."
    echo "   macOS: brew install awscli"
    exit 1
fi

echo "📂 Izvor:           $SOURCE"
echo "🪣 R2 Bucket:       $BUCKET_NAME"
echo "🌐 R2 Endpoint:     $ENDPOINT_URL"
echo "👤 AWS Profil:      $AWS_PROFILE"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "🧪 POKREĆEM DRY RUN: Ovo je samo simulacija, ništa neće biti uploadano!"
    echo "--------------------------------------------------------"
    AWS_ARGS="--dryrun"
else
    echo "🚀 POKREĆEM SINKRONIZACIJU NA R2 EKRAN (TRAJNA POHRANA)"
    echo "--------------------------------------------------------"
    AWS_ARGS=""
fi

# Filteri za aws s3 sync:
# 1. Isključujemo sve macOS resource fork datoteke (._*)
# 2. Isključujemo .DS_Store datoteke
# Opcionalno, možemo dodati --exclude "*" i --include "*.mp4" ako želimo eksplicitno slati samo neke formate,
# ali s obzirom da su strukture i metapodaci (poput .webp, .info.json) korisni za kompletni katalog, 
# ovdje isključujemo samo smeće datoteke operativnog sustava kako bi na R2 bio potpun repozitorij.

echo "Počinjem sa skeniranjem i prijenosom..."
aws s3 sync "$SOURCE" "s3://$BUCKET_NAME" \
    --endpoint-url "$ENDPOINT_URL" \
    --profile "$AWS_PROFILE" \
    --exclude "._*" \
    --exclude ".DS_Store" \
    --exclude ".fseventsd/*" \
    --exclude ".Spotlight-V100/*" \
    --exclude ".Trashes/*" \
    --no-progress \
    $AWS_ARGS

echo "--------------------------------------------------------"
if [ "$DRY_RUN" = true ]; then
    echo "✅ DRY RUN završen. Pogledajte iznad koje bi datoteke bile prebačene."
    echo "   Za stvarni upload, pokrenite skriptu bez --dry-run opcije."
else
    echo "✅ Sinkronizacija završena uspješno!"
    echo "   Lokalne datoteke u '$SOURCE' mogu se sada sigurno obrisati, a"
    echo "   pri idućem pokretanju skripte nove datoteke će se jednostavno nadodati na R2."
fi
