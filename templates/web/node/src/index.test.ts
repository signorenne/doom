import { describe, expect, it } from 'vitest';

import { greet } from './index.js';

describe('greet', () => {
	it('greets the world when given nothing', () => {
		expect(greet('')).toBe('Hello, world');
	});

	it('greets a name', () => {
		expect(greet('Nicolo')).toBe('Hello, Nicolo');
	});

	it('ignores the space around a name', () => {
		expect(greet('  Nicolo  ')).toBe('Hello, Nicolo');
	});
});
