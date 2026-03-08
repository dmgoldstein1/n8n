'use strict';

const { existsSync } = require('node:fs');

const XLSX_STUB_PATH = '/tmp/xlsx-stub.tgz';
const XLSX_LOCAL = `file://${XLSX_STUB_PATH}`;
const XLSX_CDN = 'https://cdn.sheetjs.com/xlsx-0.20.2/xlsx-0.20.2.tgz';

/**
 * pnpm hook – resolve xlsx from a local stub when available (fast offline installs),
 * falling back to the upstream CDN tarball when the local file is not present (e.g. CI).
 *
 * @see https://pnpm.io/pnpmfile
 */
function readPackage(pkg, context) {
	if (pkg.dependencies && 'xlsx' in pkg.dependencies) {
		if (existsSync(XLSX_STUB_PATH)) {
			pkg.dependencies.xlsx = XLSX_LOCAL;
		} else {
			pkg.dependencies.xlsx = XLSX_CDN;
			context.log(`xlsx: local stub not found at ${XLSX_STUB_PATH}, using CDN fallback`);
		}
	}
	return pkg;
}

module.exports = {
	hooks: {
		readPackage,
	},
};
