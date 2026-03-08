import { mockInstance } from '@n8n/backend-test-utils';
import { Container } from '@n8n/di';
import { mock } from 'jest-mock-extended';
import { ErrorReporter, StorageConfig } from 'n8n-core';
import { jsonParse } from 'n8n-workflow';
import fs, { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join, relative } from 'node:path';

import { EXECUTION_DATA_BUNDLE_FILENAME } from '../constants';
import { CorruptedExecutionDataError } from '../corrupted-execution-data.error';
import { ExecutionDataWriteError } from '../execution-data-write.error';
import { FsStore } from '../fs-store';
import { createExecutionRef } from '../types';
import type { ExecutionDataPayload } from '../types';
import { executionId, payload, ref, workflowId } from './mocks';

jest.unmock('node:fs/promises');

let fsStore: FsStore;
let storagePath: string;

beforeAll(async () => {
	storagePath = await mkdtemp(join(tmpdir(), 'n8n-fs-store-test-'));
	mockInstance(StorageConfig, { storagePath });
	mockInstance(ErrorReporter);
	fsStore = Container.get(FsStore);
});

beforeEach(async () => {
	const workflowsDir = join(storagePath, 'workflows');
	await rm(workflowsDir, { recursive: true, force: true }).catch(() => {});
});

afterEach(() => {
	jest.restoreAllMocks();
});

afterAll(async () => {
	await rm(storagePath, { recursive: true, force: true });
});

describe('init', () => {
	it('should create storage dir if absent', async () => {
		const customPath = join(storagePath, 'custom-init-dir');
		const customFsStore = new FsStore(
			mock<StorageConfig>({ storagePath: customPath }),
			Container.get(ErrorReporter),
		);

		await customFsStore.init();

		const stat = await fs.stat(customPath);
		expect(stat.isDirectory()).toBe(true);

		await rm(customPath, { recursive: true, force: true });
	});
});

describe('write', () => {
	it('should store execution data as JSON file', async () => {
		await fsStore.write(ref, payload);

		const filePath = join(
			storagePath,
			'workflows',
			workflowId,
			'executions',
			executionId,
			'execution_data',
			EXECUTION_DATA_BUNDLE_FILENAME,
		);

		const content = await fs.readFile(filePath, 'utf-8');
		const stored = jsonParse<ExecutionDataPayload>(content);

		expect(stored).toMatchObject({ ...payload, version: 1 });
	});

	it('should overwrite on duplicate `executionId`', async () => {
		await fsStore.write(ref, payload);

		const updatedPayload: ExecutionDataPayload = {
			...payload,
			data: '[[{"json":{"updated":true}},null]]',
		};

		await fsStore.write(ref, updatedPayload);

		const stored = await fsStore.read(ref);
		expect(stored).toMatchObject({ ...updatedPayload, version: 1 });
	});

	it('should throw `ExecutionDataWriteError` on write failure and clean up temp file', async () => {
		jest.spyOn(fs, 'rename').mockRejectedValueOnce(new Error('EACCES: permission denied'));

		await expect(fsStore.write(ref, payload)).rejects.toThrow(ExecutionDataWriteError);

		const executionDataDir = join(
			storagePath,
			'workflows',
			workflowId,
			'executions',
			executionId,
			'execution_data',
		);
		const files = await fs.readdir(executionDataDir);
		const tempFiles = files.filter((f) => f.includes('.tmp.'));

		expect(tempFiles).toHaveLength(0);
	});
});

describe('read', () => {
	it('should retrieve stored execution data', async () => {
		await fsStore.write(ref, payload);

		const stored = await fsStore.read(ref);

		expect(stored).toMatchObject({ ...payload, version: 1 });
	});

	it('should return `null` for non-existent execution', async () => {
		const result = await fsStore.read(createExecutionRef(workflowId, 'non-existent'));

		expect(result).toBeNull();
	});

	it('should throw `CorruptedExecutionDataError` for corrupted JSON', async () => {
		const bundlePath = join(
			storagePath,
			'workflows',
			workflowId,
			'executions',
			executionId,
			'execution_data',
			EXECUTION_DATA_BUNDLE_FILENAME,
		);

		await fs.mkdir(
			join(storagePath, 'workflows', workflowId, 'executions', executionId, 'execution_data'),
			{ recursive: true },
		);
		await fs.writeFile(bundlePath, 'invalid json{{{', 'utf-8');

		await expect(fsStore.read(ref)).rejects.toThrow(CorruptedExecutionDataError);
	});
});

describe('delete', () => {
	it('should delete execution directory', async () => {
		await fsStore.write(ref, payload);

		await fsStore.delete(ref);

		const result = await fsStore.read(ref);
		expect(result).toBeNull();

		const executionDir = join(storagePath, 'workflows', workflowId, 'executions', executionId);
		await expect(fs.stat(executionDir)).rejects.toThrow();
	});

	it('should delete data for multiple executions', async () => {
		const refs = [
			createExecutionRef(workflowId, 'exec-1'),
			createExecutionRef(workflowId, 'exec-2'),
			createExecutionRef(workflowId, 'exec-3'),
		];

		for (const r of refs) {
			await fsStore.write(r, payload);
		}

		await fsStore.delete([refs[0], refs[1]]);

		expect(await fsStore.read(refs[0])).toBeNull();
		expect(await fsStore.read(refs[1])).toBeNull();
		expect(await fsStore.read(refs[2])).not.toBeNull();
	});

	it('should skip deletion on empty array', async () => {
		await fsStore.write(ref, payload);

		await fsStore.delete([]);

		const result = await fsStore.read(ref);
		expect(result).not.toBeNull();
	});

	it('should not throw on deleting a non-existent execution', async () => {
		await expect(
			fsStore.delete(createExecutionRef(workflowId, 'non-existent')),
		).resolves.toBeUndefined();
	});
});

describe('path traversal prevention', () => {
	// IDs that would escape the storage root if not sanitized
	const maliciousIds = [
		'../evil',
		'../../etc/passwd',
		'..\\..\\windows\\system32',
		'%2F..%2Fevil',
		'%5C..%5Cevil',
	];

	describe('write', () => {
		it.each(maliciousIds)(
			'should not write outside storage root with malicious workflowId: %s',
			async (maliciousWorkflowId) => {
				const maliciousRef = createExecutionRef(maliciousWorkflowId, executionId);
				await fsStore.write(maliciousRef, payload);

				const sanitized = maliciousWorkflowId.replace(/[^a-zA-Z0-9_-]/g, '_');
				const writtenPath = join(
					storagePath,
					'workflows',
					sanitized,
					'executions',
					executionId,
					'execution_data',
					EXECUTION_DATA_BUNDLE_FILENAME,
				);

				// Resolved path must stay within the storage root
				expect(relative(storagePath, writtenPath)).not.toMatch(/^\.\./);
				// Bundle file must actually exist at the sanitized location
				const stat = await fs.stat(writtenPath);
				expect(stat.isFile()).toBe(true);
			},
		);

		it.each(maliciousIds)(
			'should not write outside storage root with malicious executionId: %s',
			async (maliciousExecutionId) => {
				const maliciousRef = createExecutionRef(workflowId, maliciousExecutionId);
				await fsStore.write(maliciousRef, payload);

				const sanitized = maliciousExecutionId.replace(/[^a-zA-Z0-9_-]/g, '_');
				const writtenPath = join(
					storagePath,
					'workflows',
					workflowId,
					'executions',
					sanitized,
					'execution_data',
					EXECUTION_DATA_BUNDLE_FILENAME,
				);

				expect(relative(storagePath, writtenPath)).not.toMatch(/^\.\./);
				// Bundle file must actually exist at the sanitized location
				const stat = await fs.stat(writtenPath);
				expect(stat.isFile()).toBe(true);
			},
		);
	});

	describe('read', () => {
		it.each(maliciousIds)(
			'should return null (not escape storage root) with malicious workflowId: %s',
			async (maliciousWorkflowId) => {
				const maliciousRef = createExecutionRef(maliciousWorkflowId, executionId);
				// Nothing written at the sanitized path — must return null, not throw
				const result = await fsStore.read(maliciousRef);
				expect(result).toBeNull();
			},
		);

		it.each(maliciousIds)(
			'should return null (not escape storage root) with malicious executionId: %s',
			async (maliciousExecutionId) => {
				const maliciousRef = createExecutionRef(workflowId, maliciousExecutionId);
				const result = await fsStore.read(maliciousRef);
				expect(result).toBeNull();
			},
		);
	});

	describe('delete', () => {
		it('should not delete files outside storage root when workflowId contains path traversal', async () => {
			const sentinelDir = await mkdtemp(join(tmpdir(), 'n8n-sentinel-'));
			// Without sanitization, the resolved execution dir would be:
			//   storagePath/workflows/../../<sentinelBasename>/executions/executionId
			//     ↑ `..` from workflows/ → storagePath/
			//     ↑ `..` from storagePath/ → tmpdir/
			//   = tmpdir/<sentinelBasename>/executions/executionId
			// Place the sentinel inside that exact sub-directory so deletion would destroy it.
			const sentinelExecDir = join(sentinelDir, 'executions', executionId);
			await fs.mkdir(sentinelExecDir, { recursive: true });
			const sentinelFile = join(sentinelExecDir, 'sentinel.txt');
			await fs.writeFile(sentinelFile, 'should not be deleted', 'utf-8');

			try {
				// ../../sentinelBasename escapes storagePath/workflows/ up to tmpdir()
				const maliciousWorkflowId = `../../${basename(sentinelDir)}`;
				await fsStore.delete(createExecutionRef(maliciousWorkflowId, executionId));

				// The sentinel outside storagePath must survive
				await expect(fs.stat(sentinelFile)).resolves.toBeDefined();
			} finally {
				await rm(sentinelDir, { recursive: true, force: true });
			}
		});

		it('should not delete files outside storage root when executionId contains path traversal', async () => {
			const sentinelDir = await mkdtemp(join(tmpdir(), 'n8n-sentinel-'));
			// Without sanitization, the resolved execution dir would be:
			//   storagePath/workflows/workflowId/executions/../../../../<sentinelBasename>
			//     ↑ `..` from executions/ → storagePath/workflows/workflowId/
			//     ↑ `..` from workflowId/  → storagePath/workflows/
			//     ↑ `..` from workflows/   → storagePath/
			//     ↑ `..` from storagePath/ → tmpdir/
			//   = tmpdir/<sentinelBasename>  (the entire sentinelDir would be removed)
			const sentinelFile = join(sentinelDir, 'sentinel.txt');
			await fs.writeFile(sentinelFile, 'should not be deleted', 'utf-8');

			try {
				// ../../../../sentinelBasename escapes storagePath/workflows/workflowId/executions/ up to tmpdir()
				const maliciousExecutionId = `../../../../${basename(sentinelDir)}`;
				await fsStore.delete(createExecutionRef(workflowId, maliciousExecutionId));

				await expect(fs.stat(sentinelFile)).resolves.toBeDefined();
			} finally {
				await rm(sentinelDir, { recursive: true, force: true });
			}
		});
	});
});
