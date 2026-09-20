/** {{PROJECT}}: say here what this program is for. */

export function greet(name: string): string {
	const trimmed = name.trim();
	return trimmed.length === 0 ? 'Hello, world' : `Hello, ${trimmed}`;
}

// Run only when this file is the program, not when it is imported by a
// test or by another module.
if (import.meta.url === `file://${process.argv[1]}`) {
	console.log(greet(process.argv[2] ?? ''));
}
