#!/usr/bin/env bash
# Third-Party License Generator for n8n.
#
# Generates THIRD_PARTY_LICENSES.md by scanning all dependencies using license-checker,
# extracting license information, and formatting it into a markdown report.
#
# Usage: bash scripts/generate-third-party-licenses.sh

set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
	ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	ROOT_DIR="$SCRIPT_DIR"
fi

CLI_ROOT="$ROOT_DIR/packages/cli"
FORMAT_CONFIG="$SCRIPT_DIR/third-party-license-format.json"
TEMP_LICENSES="$(mktemp)"
OUTPUT_FILE="$CLI_ROOT/THIRD_PARTY_LICENSES.md"

echo -e "${BLUE}🚀 Generating third-party licenses for n8n...${NC}"

# Collect license data
echo -e "${YELLOW}📊 Running license-checker...${NC}"
(
	cd "$ROOT_DIR"
	pnpm exec license-checker --json --customPath "$FORMAT_CONFIG" > "$TEMP_LICENSES"
)
echo -e "${GREEN}✅ License data collected${NC}"

# Process JSON into markdown using embedded Node.js
mkdir -p "$CLI_ROOT"

node << NODEOF
'use strict';
const fs = require('fs');
const path = require('path');

const tempLicensesPath = '$TEMP_LICENSES';
const outputPath = '$OUTPUT_FILE';

const INVALID_LICENSE_FILES = ['readme.md', 'readme.txt', 'readme', 'package.json', 'changelog.md', 'history.md'];
const VALID_LICENSE_FILES = ['license', 'licence', 'copying', 'copyright', 'unlicense'];

const N8N_PATTERNS = [/^@n8n\//, /^@n8n_/, /^n8n-/, /-n8n/];

const FALLBACKS = {
  'CC-BY-3.0': 'Creative Commons Attribution 3.0 Unported License\n\nFull license text available at: https://creativecommons.org/licenses/by/3.0/legalcode',
  'LGPL-3.0-or-later': 'GNU Lesser General Public License v3.0 or later\n\nFull license text available at: https://www.gnu.org/licenses/lgpl-3.0.html',
  'PSF': 'Python Software Foundation License\n\nFull license text available at: https://docs.python.org/3/license.html',
  '(MIT OR CC0-1.0)': 'Licensed under MIT OR CC0-1.0\n\nMIT License full text available at: https://opensource.org/licenses/MIT\nCC0 1.0 Universal full text available at: https://creativecommons.org/publicdomain/zero/1.0/legalcode',
  'UNKNOWN': 'License information not available. Please check individual package repositories for license details.',
};

function parsePackageKey(key) {
  const lastAt = key.lastIndexOf('@');
  return { packageName: key.substring(0, lastAt), version: key.substring(lastAt + 1) };
}

function shouldExclude(name) {
  return N8N_PATTERNS.some(p => p.test(name));
}

function isValidLicenseFile(filePath) {
  if (!filePath) return false;
  const name = path.basename(filePath).toLowerCase();
  if (INVALID_LICENSE_FILES.some(inv => name === inv || name.endsWith(inv))) return false;
  return VALID_LICENSE_FILES.some(v => name.includes(v));
}

function cleanLicenseText(text) {
  return text.replaceAll('\\n', '\n').replaceAll('\\"', '"').replaceAll('\r\n', '\n').trim();
}

function getFallback(licenseType, packages) {
  if (licenseType.startsWith('Custom:')) return 'Custom license. See: ' + licenseType.replace('Custom: ', '');
  if (licenseType === 'UNKNOWN') {
    return 'License information not available for the following packages:\n' +
      packages.map(p => '- ' + p.name + ' ' + p.version).join('\n') +
      '\n\nPlease check individual package repositories for license details.';
  }
  return FALLBACKS[licenseType] || null;
}

const rawData = fs.readFileSync(tempLicensesPath, 'utf-8');
const packages = JSON.parse(rawData);
console.error('✅ Parsed ' + Object.keys(packages).length + ' packages');

const licenseGroups = new Map();
const licenseTexts = new Map();
let processedCount = 0;

for (const [key, pkg] of Object.entries(packages)) {
  const { packageName, version } = parsePackageKey(key);
  if (shouldExclude(packageName)) continue;

  const licenseType = pkg.licenses || 'Unknown';
  processedCount++;

  if (!licenseGroups.has(licenseType)) licenseGroups.set(licenseType, []);
  licenseGroups.get(licenseType).push({ name: packageName, version, repository: pkg.repository, copyright: pkg.copyright });

  if (!licenseTexts.has(licenseType)) licenseTexts.set(licenseType, null);
  if (!licenseTexts.get(licenseType) && pkg.licenseText && pkg.licenseText.trim() && isValidLicenseFile(pkg.licenseFile)) {
    licenseTexts.set(licenseType, cleanLicenseText(pkg.licenseText));
  }
}

// Apply fallbacks for missing texts
const missingTexts = [];
const fallbacksUsed = [];
for (const [licenseType, text] of licenseTexts.entries()) {
  if (!text || !text.trim()) {
    const pkgs = licenseGroups.get(licenseType) || [];
    const fallback = getFallback(licenseType, pkgs);
    if (fallback) { licenseTexts.set(licenseType, fallback); fallbacksUsed.push(licenseType); }
    else missingTexts.push(licenseType);
  }
}

console.error('📦 Processed ' + processedCount + ' packages in ' + licenseGroups.size + ' license groups');
if (fallbacksUsed.length > 0) console.error('ℹ️  Used fallback texts for: ' + fallbacksUsed.join(', '));
if (missingTexts.length > 0) console.error('⚠️  Still missing license texts for: ' + missingTexts.join(', '));
else console.error('✅ All license types have texts');

const sortedLicenseTypes = [...licenseGroups.keys()].sort();

let doc = '# Third-Party Licenses\n\nThis file lists third-party software components included in n8n and their respective license terms.\n\nThe n8n software includes open source packages, libraries, and modules, each of which is subject to its own license. The following sections list those dependencies and provide required attributions and license texts.\n\n';

for (const licenseType of sortedLicenseTypes) {
  const pkgs = [...licenseGroups.get(licenseType)].sort((a, b) => a.name.localeCompare(b.name));
  doc += '## ' + licenseType + '\n\n';
  for (const pkg of pkgs) {
    doc += '* ' + pkg.name + ' ' + pkg.version;
    if (pkg.copyright) doc += ', ' + pkg.copyright;
    doc += '\n';
  }
  doc += '\n';
}

doc += '# License Texts\n\n';
for (const licenseType of sortedLicenseTypes) {
  const licenseText = licenseTexts.get(licenseType);
  doc += '## ' + licenseType + ' License Text\n\n';
  if (licenseText && licenseText.trim()) {
    doc += '\`\`\`\n' + licenseText + '\n\`\`\`\n\n';
  } else {
    doc += licenseType + ' license text not available.\n\n';
  }
}

fs.writeFileSync(outputPath, doc);
console.error('\n🎉 License generation completed successfully!');
console.error('📄 Output: ' + outputPath);
console.error('📦 Packages: ' + processedCount);
NODEOF

# Clean up temp file
rm -f "$TEMP_LICENSES"

echo -e "${GREEN}✅ Third-party licenses written to $OUTPUT_FILE${NC}"
